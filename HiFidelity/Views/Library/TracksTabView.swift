//
//  TracksTabView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Tracks tab view displaying all library tracks with list/grid view and sorting
struct TracksTabView: View {
    let isVisible: Bool
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var playback = PlaybackController.shared
    
    @State private var tracks: [Track] = []
    @State private var filteredTracks: [Track] = []
    @State private var sortedTracks: [Track] = []
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @AppStorage("tracksViewType") private var savedViewType: String = "list"
    @AppStorage("tracksSortField") private var savedSortField: String = "title"
    @AppStorage("tracksSortAscending") private var savedSortAscending: Bool = true
    @State private var viewType: ViewType = .list
    
    // Compact view state
    @AppStorage("tracksCompactView") private var isCompactView: Bool = false
    @State private var selectedTrack: Track.ID?
    @State private var sortOrder: [KeyPathComparator<Track>] = [KeyPathComparator(\Track.title, order: .forward)]
    @State private var selectedFilter: TrackFilter? = nil
    @State private var similarTracksFilter: [Track]? = nil
    @State private var isShowingSimilarTracks = false
    
    init(isVisible: Bool = true) {
        self.isVisible = isVisible
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            
            Divider()
            
            // Content
            if isLoading {
                loadingView
            } else if tracks.isEmpty {
                emptyState
            } else {
                trackContent
            }
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue && !hasLoadedOnce {
                Task {
                    await loadTracks()
                    hasLoadedOnce = true
                }
            }
        }
        .onAppear {
            // Restore saved view type
            if savedViewType == "compact" {
                viewType = .list
                isCompactView = true
            } else {
                viewType = savedViewType == "grid" ? .grid : .list
                isCompactView = false
            }
            
            // Restore saved sort order
            if let field = TrackSortField.allFields.first(where: { $0.rawValue == savedSortField }) {
                sortOrder = [field.getComparator(ascending: savedSortAscending)]
            }
            
            if isVisible && !hasLoadedOnce {
                Task {
                    await loadTracks()
                    hasLoadedOnce = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshLibraryData)) { notification in
            // Try to get trackId from the notification if it was included
            // This is set when metadata is saved from Track Info panel
            let trackIdFromNotification = notification.userInfo?["trackId"] as? Int64

            Logger.debug("💾 Starting selection save:")
            Logger.debug("   selectedTrack UUID: \(String(describing: selectedTrack?.uuidString ?? "nil"))")
            Logger.debug("   trackId from notification: \(String(describing: trackIdFromNotification))")
            Logger.debug("   tracks.count: \(tracks.count)")
            Logger.debug("   sortedTracks.count: \(sortedTracks.count)")

            // Priority 1: Use trackId from notification (when saving metadata)
            // Priority 2: Find selected track in tracks array (when manually refreshing)
            let selectedDatabaseId: Int64?
            if let notificationTrackId = trackIdFromNotification {
                selectedDatabaseId = notificationTrackId
                Logger.debug("   ✅ Using trackId from notification: \(notificationTrackId)")
            } else if let selectedId = selectedTrack {
                if let foundTrack = tracks.first(where: { $0.id == selectedId }) {
                    selectedDatabaseId = foundTrack.trackId
                    Logger.debug("   ✅ Found selected track in tracks array: trackId=\(String(describing: foundTrack.trackId)), title=\(foundTrack.title)")
                } else if let foundTrack = sortedTracks.first(where: { $0.id == selectedId }) {
                    selectedDatabaseId = foundTrack.trackId
                    Logger.debug("   ✅ Found selected track in sortedTracks array: trackId=\(String(describing: foundTrack.trackId)), title=\(foundTrack.title)")
                } else {
                    selectedDatabaseId = nil
                    Logger.debug("   ❌ Selected track UUID exists but not found in any tracks array")
                }
            } else {
                selectedDatabaseId = nil
                Logger.debug("   ℹ️ No track selected (selectedTrack is nil)")
            }

            Logger.debug("💾 Final database ID to restore: \(selectedDatabaseId ?? -1)")

            Task {
                await loadTracks()
                // Wait for filtering/sorting to complete
                try? await Task.sleep(for: .milliseconds(100))

                // Ensure selection restoration happens on main thread
                await MainActor.run {
                    if let databaseId = selectedDatabaseId {
                        if let restoredTrack = tracks.first(where: { $0.trackId == databaseId }) {
                            Logger.debug("✅ Restoring selection: trackId=\(databaseId), newId=\(restoredTrack.id)")
                            Logger.debug("   tracks.count=\(tracks.count), sortedTracks.count=\(sortedTracks.count)")
                            Logger.debug("   track in sortedTracks: \(sortedTracks.contains(where: { $0.id == restoredTrack.id }))")

                            // Clear selection first to force update
                            selectedTrack = nil
                        } else {
                            Logger.debug("❌ Could not find track with trackId=\(databaseId) in \(tracks.count) tracks")
                        }
                    } else {
                        Logger.debug("ℹ️ No selection to restore (selectedDatabaseId is nil)")
                    }
                }

                // Small delay then restore selection
                try? await Task.sleep(for: .milliseconds(50))
                await MainActor.run {
                    if let databaseId = selectedDatabaseId {
                        if let restoredTrack = tracks.first(where: { $0.trackId == databaseId }) {
                            Logger.debug("🔵 Setting selection to: \(restoredTrack.id)")
                            selectedTrack = restoredTrack.id
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateTrackSelection)) { notification in
            // Update selection when navigating in Track Info panel - use database trackId
            if let databaseTrackId = notification.userInfo?["databaseTrackId"] as? Int64 {
                Logger.debug("📍 Updating table selection from Track Info navigation: databaseTrackId=\(databaseTrackId)")
                // Find the track with this database ID in the current tracks array
                if let foundTrack = tracks.first(where: { $0.trackId == databaseTrackId }) {
                    selectedTrack = foundTrack.id
                    Logger.debug("📍 Selection updated to track with UUID: \(foundTrack.id)")
                } else {
                    Logger.debug("📍 Could not find track with databaseTrackId=\(databaseTrackId)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findSimilarTracks)) { notification in
            if let trackId = notification.userInfo?["trackId"] as? Int64 {
                let shouldToggle = notification.userInfo?["toggle"] as? Bool ?? false

                if shouldToggle && isShowingSimilarTracks {
                    // If already showing similar tracks, clear the filter
                    clearSimilarTracksFilter()
                } else {
                    // Otherwise, find similar tracks
                    Task {
                        await findSimilarTracks(toTrackId: trackId)
                    }
                }
            }
        }
        .onChange(of: sortOrder) { oldValue, newValue in
            if oldValue != newValue {
                saveSortOrder(newValue)
                performBackgroundSort(with: newValue)
            }
        }
        .onChange(of: tracks) { _, newTracks in
            if !newTracks.isEmpty {
                applyFilter()
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            applyFilter()
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            // Track count
            Text("\(sortedTracks.count) tracks")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            // Sort and Filter dropdown
            TrackTableOptionsDropdown(
                sortOrder: $sortOrder,
                selectedFilter: $selectedFilter
            )
            .frame(width: 32)

            viewToggle
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(height: 46)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    
    private var viewToggle: some View {
        // View type toggle - 3 buttons: compact (left), normal/list (middle), artwork/grid (right)
        // The existing button (list.bullet) is used for compact view as requested
        HStack(spacing: 0) {
            // Compact view button (left) - using the existing list.bullet icon
            Button {
                viewType = .list
                isCompactView = true
                savedViewType = "compact"
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13))
                    .foregroundColor(isCompactView && viewType == .list ? .white : .primary)
                    .frame(width: 32, height: 28)
                    .background(
                        isCompactView && viewType == .list ? theme.currentTheme.primaryColor : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Compact View")
            
            // Normal/list view button (middle) - using rectangle.grid.1x2 to match EntityDetailView
            Button {
                viewType = .list
                isCompactView = false
                savedViewType = "list"
            } label: {
                Image(systemName: "rectangle.grid.1x2")
                    .font(.system(size: 13))
                    .foregroundColor(viewType == .list && !isCompactView ? .white : .primary)
                    .frame(width: 32, height: 28)
                    .background(
                        viewType == .list && !isCompactView ? theme.currentTheme.primaryColor : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Normal View")
            
            // Artwork/grid view button (right)
            Button {
                viewType = .grid
                isCompactView = false
                savedViewType = "grid"
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13))
                    .foregroundColor(viewType == .grid ? .white : .primary)
                    .frame(width: 32, height: 28)
                    .background(
                        viewType == .grid ? theme.currentTheme.primaryColor : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Artwork View")
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - Track Content
    
    @ViewBuilder
    private var trackContent: some View {
        if viewType == .list {
            if isCompactView {
                compactTrackListView
            } else {
                trackListView
            }
        } else {
            trackGridView
        }
    }
    
    // MARK: - List View
    
    private var trackListView: some View {
        TrackTableView(
            tracks: sortedTracks,
            selection: $selectedTrack,
            sortOrder: $sortOrder,
            onPlayTrack: playTrack,
            isCurrentTrack: isCurrentTrack
        )
    }
    
    // MARK: - Compact List View
    
    private var compactTrackListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                    compactTrackRow(track: track, index: index)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func compactTrackRow(track: Track, index: Int) -> some View {
        HStack(spacing: 10) {
            // Position number
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 20)
            
            // Album artwork
            TrackArtworkView(track: track, size: 40, cornerRadius: 3)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 12))
                    .foregroundColor(isCurrentTrack(track) ? theme.currentTheme.primaryColor : .primary)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            // Duration
            Text(track.formattedDuration)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            playTrack(track)
        }
        .contextMenu {
            TrackContextMenu(
                track: track,
                playlistContext: nil
            )
        }
        .onDrag {
            // Create drag item with track ID
            if let trackId = track.trackId {
                return NSItemProvider(object: "track:\(trackId)" as NSString)
            }
            return NSItemProvider()
        } preview: {
            // Drag preview
            HStack(spacing: 8) {
                TrackArtworkView(track: track, size: 32, cornerRadius: 4)
                Text(track.title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(radius: 4)
            )
        }
    }
    
    // MARK: - Grid View
    
    private var trackGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
            ], spacing: 16) {
                ForEach(sortedTracks.isEmpty ? tracks : sortedTracks) { track in
                    TrackGridCard(track: track) {
                        playTrack(track)
                    }
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 18) {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.3))
                
                Text("No Tracks")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Add music folders to see your library here")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(theme.currentTheme.primaryColor)
                
                Text("Loading tracks...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func isCurrentTrack(_ track: Track) -> Bool {
        guard let currentTrack = playback.currentTrack else { return false }
        return currentTrack.url.path == track.url.path
    }
    
    private func playTrack(_ track: Track) {
        guard let trackIndex = sortedTracks.firstIndex(where: { $0.id == track.id }) else {
            playback.playTracks([track], startingAt: 0)
            return
        }
        
        playback.playTracks(sortedTracks, startingAt: trackIndex)
    }
    
    // MARK: - Data Loading
    
    private func loadTracks() async {
        // Use smooth animation to prevent UI blinking
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                isLoading = true
            }
        }

        do {
            let newTracks = try await DatabaseCache.shared.getAllTracks(forceRefresh: true)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tracks = newTracks
                }
            }
        } catch {
            Logger.error("Failed to load tracks: \(error)")
        }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                isLoading = false
            }
        }
    }
    
    // MARK: - Filtering
    
    private func applyFilter() {
        // Priority: similar tracks filter > selected filter
        if let similarTracks = similarTracksFilter {
            filteredTracks = similarTracks
            isShowingSimilarTracks = true
        } else if let filter = selectedFilter {
            isShowingSimilarTracks = false
            switch filter {
            case .favorites:
                filteredTracks = tracks.filter { $0.isFavorite }
            case .recentlyAdded:
                let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                filteredTracks = tracks.filter { 
                    guard let dateAdded = $0.dateAdded else { return false }
                    return dateAdded >= thirtyDaysAgo
                }
            case .unplayed:
                filteredTracks = tracks.filter { $0.playCount == 0 }
            }
        } else {
            isShowingSimilarTracks = false
            filteredTracks = tracks
        }
        
        // Re-sort after filtering
        initializeSortedTracks()
    }
    
    // MARK: - Similar Tracks
    
    private func findSimilarTracks(toTrackId trackId: Int64) async {
        isLoading = true

        do {
            // Try to find similar tracks by key and BPM
            let similarTracks = try await DatabaseManager.shared.findSimilarTracksByKeyAndBPM(
                toTrackId: trackId,
                bpmTolerance: 5.0,
                limit: 100,
                includeCompatibleKeys: true
            )

            await MainActor.run {
                similarTracksFilter = similarTracks
                applyFilter()

                // Notify that filter is now active
                NotificationCenter.default.post(
                    name: .similarTracksFilterChanged,
                    object: nil,
                    userInfo: ["trackId": trackId]
                )

                // Switch to Tracks tab if not already there
                NotificationCenter.default.post(name: .goToHome, object: nil)
            }
        } catch {
            Logger.error("Failed to find similar tracks: \(error)")
            await MainActor.run {
                similarTracksFilter = nil
                applyFilter()
            }
        }

        isLoading = false
    }
    
    /// Clear similar tracks filter
    private func clearSimilarTracksFilter() {
        similarTracksFilter = nil
        isShowingSimilarTracks = false
        applyFilter()

        // Notify that filter is now cleared
        NotificationCenter.default.post(
            name: .similarTracksFilterChanged,
            object: nil,
            userInfo: [:] // Empty userInfo means filter is cleared
        )
    }
    
    // MARK: - Sorting Helpers
    
    private func initializeSortedTracks() {
        // Use current sort order instead of resetting to default
        sortedTracks = filteredTracks.sorted(using: sortOrder)
    }
    
    private func performBackgroundSort(with newSortOrder: [KeyPathComparator<Track>]) {
        let tracksToSort = self.filteredTracks
        Task.detached(priority: .userInitiated) {
            let sorted = tracksToSort.sorted(using: newSortOrder)
            await MainActor.run {
                self.sortedTracks = sorted
            }
        }
    }
    
    private func saveSortOrder(_ sortOrder: [KeyPathComparator<Track>]) {
        guard let firstSort = sortOrder.first else { return }
        
        let sortString = String(describing: firstSort)
        let isAscending = sortString.contains("forward")
        
        // Map comparator to field
        let sortKeyMap: [String: TrackSortField] = [
            "title": .title,
            "artist": .artist,
            "album": .album,
            "genre": .genre,
            "year": .year,
            "duration": .duration,
            "playCount": .playCount,
            "codec": .codec,
            "dateAdded": .dateAdded,
            "filename": .filename,
            "trackNumber": .trackNumber,
            "discNumber": .discNumber,
        ]
        
        for (key, field) in sortKeyMap {
            if sortString.contains(key) {
                savedSortField = field.rawValue
                savedSortAscending = isAscending
                break
            }
        }
    }
}

// MARK: - View Type

enum ViewType {
    case list
    case grid
}

// MARK: - Track Filter

enum TrackFilter: String, CaseIterable {
    case favorites = "Favorites"
    case recentlyAdded = "Recently Added"
    case unplayed = "Unplayed"
}

// MARK: - Track Sort Field

enum TrackSortField: String, Hashable {
    case title
    case artist
    case album
    case genre
    case year
    case bpm
    case key
    case duration
    case playCount
    case codec
    case dateAdded
    case filename
    case trackNumber
    case discNumber

    var displayName: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .genre: return "Genre"
        case .year: return "Year"
        case .bpm: return "BPM"
        case .key: return "Key"
        case .duration: return "Duration"
        case .playCount: return "Play Count"
        case .codec: return "Codec"
        case .dateAdded: return "Date Added"
        case .filename: return "Filename"
        case .trackNumber: return "Track Number"
        case .discNumber: return "Disc Number"
        }
    }

    static var regularFields: [TrackSortField] {
        [.title, .artist, .album, .genre, .year, .bpm, .key, .duration, .playCount, .codec, .dateAdded, .filename, .trackNumber, .discNumber]
    }

    static var allFields: [TrackSortField] {
        [.title, .artist, .album, .genre, .year, .bpm, .key, .duration, .playCount, .codec, .dateAdded, .filename, .trackNumber, .discNumber]
    }
    
    func getComparator(ascending: Bool) -> KeyPathComparator<Track> {
        let order: SortOrder = ascending ? .forward : .reverse

        switch self {
        case .title:
            return KeyPathComparator(\Track.title, order: order)
        case .artist:
            return KeyPathComparator(\Track.artist, order: order)
        case .album:
            return KeyPathComparator(\Track.album, order: order)
        case .genre:
            return KeyPathComparator(\Track.genre, order: order)
        case .year:
            return KeyPathComparator(\Track.year, order: order)
        case .bpm:
            return KeyPathComparator(\Track.sortableBPM, order: order)
        case .key:
            return KeyPathComparator(\Track.sortableKey, order: order)
        case .duration:
            return KeyPathComparator(\Track.duration, order: order)
        case .playCount:
            return KeyPathComparator(\Track.playCount, order: order)
        case .codec:
            return KeyPathComparator(\Track.codec, order: order)
        case .dateAdded:
            return KeyPathComparator(\Track.dateAdded, order: order)
        case .filename:
            return KeyPathComparator(\Track.filename, order: order)
        case .trackNumber:
            return KeyPathComparator(\Track.trackNumber, order: order)
        case .discNumber:
            return KeyPathComparator(\Track.discNumber, order: order)
        }
    }
}

// MARK: - Track Table Options Dropdown

struct TrackTableOptionsDropdown: View {
    @Binding var sortOrder: [KeyPathComparator<Track>]
    @Binding var selectedFilter: TrackFilter?
    
    @ObservedObject private var theme = AppTheme.shared
    
    private var availableFields: [TrackSortField] {
        TrackSortField.regularFields
    }
    
    private var currentSortField: TrackSortField {
        guard let firstSort = sortOrder.first else { return .title }

        let sortString = String(describing: firstSort)

        let sortKeyMap: [String: TrackSortField] = [
            "title": .title,
            "artist": .artist,
            "album": .album,
            "genre": .genre,
            "year": .year,
            "sortableBPM": .bpm,
            "sortableKey": .key,
            "duration": .duration,
            "playCount": .playCount,
            "codec": .codec,
            "dateAdded": .dateAdded,
            "filename": .filename,
            "trackNumber": .trackNumber,
            "discNumber": .discNumber,
        ]

        for (key, field) in sortKeyMap {
            if sortString.contains(key) {
                return field
            }
        }

        return .title
    }
    
    private var isAscending: Bool {
        guard let firstSort = sortOrder.first else { return true }
        return String(describing: firstSort).contains("forward")
    }
    
    var body: some View {
        Menu {
            Section("Sort by") {
                ForEach(availableFields, id: \.self) { field in
                    Button {
                        setSortField(field)
                    } label: {
                        HStack {
                            Text(field.displayName)
                            if currentSortField == field {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            Section("Sort order") {
                Button {
                    setSortAscending(true)
                } label: {
                    HStack {
                        Text("Ascending")
                        if isAscending {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Button {
                    setSortAscending(false)
                } label: {
                    HStack {
                        Text("Descending")
                        if !isAscending {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            Section("Filter") {
                ForEach(TrackFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = (selectedFilter == filter) ? nil : filter
                    } label: {
                        HStack {
                            Text(filter.rawValue)
                            if selectedFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                if selectedFilter != nil {
                    Button("Clear Filter") {
                        selectedFilter = nil
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 16, weight: .medium))
                if selectedFilter != nil {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(theme.currentTheme.primaryColor)
                }
            }
            .foregroundColor(selectedFilter != nil ? theme.currentTheme.primaryColor : .secondary)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(selectedFilter != nil ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
    
    private func setSortField(_ field: TrackSortField) {
        let newComparator = field.getComparator(ascending: isAscending)
        sortOrder = [newComparator]
    }
    
    private func setSortAscending(_ ascending: Bool) {
        let newComparator = currentSortField.getComparator(ascending: ascending)
        sortOrder = [newComparator]
    }
}


#Preview {
    TracksTabView()
        .environmentObject(DatabaseManager.shared)
}
