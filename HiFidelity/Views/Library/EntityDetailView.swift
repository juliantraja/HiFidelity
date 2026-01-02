//
//  EntityDetailView.swift
//  HiFidelity
//
//  Generic detail view for Albums, Artists, Genres, and Playlists
//

import SwiftUI

/// Generic entity detail view showing tracks
struct EntityDetailView: View {
    @State private var entity: EntityType
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var playback = PlaybackController.shared
    
    @State private var tracks: [Track] = []
    @State private var filteredTracks: [Track] = []
    @State private var sortedTracks: [Track] = []
    @State private var isLoading = false
    @State private var selectedTrack: Track.ID?
    @State private var sortOrder = [KeyPathComparator(\Track.title, order: .forward)]
    @State private var selectedFilter: TrackFilter?
    @State private var artistArtwork: NSImage?
    @State private var artistArtworkToken = UUID()
    @AppStorage("playlistViewMode") private var isCompactView: Bool = false
    @State private var entityId: String = "" // Track entity ID separately to prevent unnecessary reloads
    @State private var hasLoadedInitialTracks: Bool = false // Track if we've loaded tracks for current entity
    @State private var playlistRefreshToken = UUID() // Force UI refresh when playlist metadata changes
    @State private var displayedTrackCount: Int = 0 // Keep track count stable during transitions
    
    // Sorting persistence - separate storage for each entity type
    @AppStorage("albumDetailSortField") private var albumSortField: String = "title"
    @AppStorage("albumDetailSortAscending") private var albumSortAscending: Bool = true
    @AppStorage("artistDetailSortField") private var artistSortField: String = "title"
    @AppStorage("artistDetailSortAscending") private var artistSortAscending: Bool = true
    @AppStorage("genreDetailSortField") private var genreSortField: String = "title"
    @AppStorage("genreDetailSortAscending") private var genreSortAscending: Bool = true
    @AppStorage("playlistDetailSortField") private var playlistSortField: String = "title"
    @AppStorage("playlistDetailSortAscending") private var playlistSortAscending: Bool = true
    
    init(entity: EntityType) {
        _entity = State(initialValue: entity)
        _entityId = State(initialValue: entity.uniqueId)
        _displayedTrackCount = State(initialValue: entity.estimatedTrackCount)
    }
    
    // Helper computed properties for current entity's sort storage
    private var currentSortField: Binding<String> {
        switch entity {
        case .album: return $albumSortField
        case .artist: return $artistSortField
        case .genre: return $genreSortField
        case .playlist: return $playlistSortField
        }
    }
    
    private var currentSortAscending: Binding<Bool> {
        switch entity {
        case .album: return $albumSortAscending
        case .artist: return $artistSortAscending
        case .genre: return $genreSortAscending
        case .playlist: return $playlistSortAscending
        }
    }
    
    // Playlist context for remove functionality (NSTrackTableView)
    private var playlistContext: NSTrackTableView.PlaylistContext? {
        guard case .playlist(let playlist) = entity, !playlist.isSmart else {
            return nil
        }
        return NSTrackTableView.PlaylistContext(
            playlist: playlist,
            onRemove: {
                Task { await loadTracks() }
            }
        )
    }
    
    // Playlist context for TrackContextMenu (different type)
    private var trackContextMenuPlaylistContext: TrackContextMenu.PlaylistContext? {
        guard case .playlist(let playlist) = entity, !playlist.isSmart else {
            return nil
        }
        return TrackContextMenu.PlaylistContext(
            playlist: playlist,
            onRemove: {
                Task { await loadTracks() }
            }
        )
    }
    
    @State private var showEditPlaylist = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Entity header
            EntityHeader(
                entity: entity,
                trackCount: displayedTrackCount,
                totalDuration: calculateTotalDuration(),
                onPlay: playAll,
                onShuffle: shuffleAll,
                artistArtwork: artistArtwork,
                artistArtworkToken: artistArtworkToken,
                onEdit: {
                    showEditPlaylist = true
                }
            )
            .id(playlistRefreshToken) // Force re-render when playlist metadata changes
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 6) {
                    // View mode toggle (only for playlists)
                    if case .playlist = entity {
                        HStack(spacing: 4) {
                            // Compact view button (left)
                            Button(action: {
                                isCompactView = true
                            }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 12))
                                    .foregroundColor(isCompactView ? theme.currentTheme.primaryColor : .secondary.opacity(0.5))
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .help("Compact View")

                            // Normal view button (right)
                            Button(action: {
                                isCompactView = false
                            }) {
                                Image(systemName: "rectangle.grid.1x2")
                                    .font(.system(size: 12))
                                    .foregroundColor(isCompactView ? .secondary.opacity(0.5) : theme.currentTheme.primaryColor)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .help("Normal View")
                        }
                    }
                    
                    TrackTableOptionsDropdown(
                        sortOrder: $sortOrder,
                        selectedFilter: $selectedFilter
                    )
                    .frame(width: 32)
                }
                .padding(.bottom, 6)
                .padding(.trailing, 16)
            }
            
            // Tracks list - show nothing while loading, empty state only after loading completes
            if hasLoadedInitialTracks {
                if sortedTracks.isEmpty {
                    emptyStateView
                } else {
                    tracksList
                }
            } else {
                // Show empty space while loading (no loading indicator)
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showEditPlaylist) {
            if case .playlist(let playlistItem) = entity,
               case .user(let playlist) = playlistItem.type {
                CreatePlaylistView(playlistToEdit: playlist)
                    .environmentObject(databaseManager)
            }
        }
        .task(id: entityId) { // Only reload when entity ID changes (navigation), not metadata updates
            // Set loading state immediately to prevent showing empty state or old tracks
            // Use synchronous state updates (no animation) to ensure view updates immediately
            hasLoadedInitialTracks = false
            isLoading = true
            tracks = []
            filteredTracks = []
            sortedTracks = []
            
            // Restore saved sort order for this entity type
            restoreSortOrder()
            await loadTracks()
            await loadArtistArtwork()
        }
        .onChange(of: entity.uniqueId) { oldValue, newValue in
            // Update entityId when entity ID changes (navigation to different entity)
            if oldValue != newValue && entityId != newValue {
                entityId = newValue
            }
        }
        .onChange(of: sortOrder) { oldValue, newValue in
            if oldValue != newValue {
                saveSortOrder(newValue)
                performBackgroundSort(with: newValue)
            }
        }
        .onChange(of: tracks) { _, newTracks in
            applyFilter()
        }
        .onChange(of: selectedFilter) { _, _ in
            applyFilter()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { notification in
            Task {
                await handleLibraryDataChange(notification: notification)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            Task {
                await refreshPlaylistEntityIfNeeded()
            }
        }
        .onChange(of: artistArtworkToken) { _, _ in
            // Trigger refresh of artist artwork view
        }
    }
    
    // MARK: - Tracks List
    
    private var tracksList: some View {
        Group {
            if case .playlist = entity, isCompactView {
                // Compact list view for playlists
                compactTracksList
            } else {
                // Normal table view
                TrackTableView(
                    tracks: sortedTracks,
                    selection: $selectedTrack,
                    sortOrder: $sortOrder,
                    onPlayTrack: playTrack,
                    isCurrentTrack: isCurrentTrack,
                    playlistContext: playlistContext
                )
            }
        }
    }
    
    // MARK: - Compact Tracks List (for playlists)
    
    private var compactTracksList: some View {
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
                playlistContext: trackContextMenuPlaylistContext
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
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(theme.currentTheme.primaryColor)
                
                Text("Loading tracks...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Image(systemName: entity.icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("No tracks found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("This \(entity.displayName.lowercased()) has no tracks")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
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
    
    private func playAll() {
        playback.playTracks(sortedTracks)
    }
    
    private func shuffleAll() {
        playback.playTracksShuffled(sortedTracks)
    }
    
    private func calculateTotalDuration() -> Double {
        sortedTracks.reduce(0) { $0 + ($1.duration) }
    }

    // MARK: - Live Updates

    private func handleLibraryDataChange(notification: Notification) async {
        guard let trackId = notification.userInfo?["trackId"] as? Int64,
              let updatedTrack = try? await DatabaseCache.shared.getTrack(by: trackId, forceRefresh: true) else {
            // No specific track ID, do a silent refresh
            await refreshTracksSilently()
            return
        }
        
        switch entity {
        case .album(let album):
            if let albumId = album.id, albumId == updatedTrack.albumId {
                await refreshAlbumEntity(albumId: albumId)
            } else {
                // Update track in place if it's in our list
                await updateTrackInPlace(updatedTrack)
            }
        case .artist(let artist):
            if let artistId = artist.id, artistId == updatedTrack.artistId {
                await refreshArtistEntity(artistId: artistId)
                await loadArtistArtwork()
            } else {
                // Update track in place if it's in our list
                await updateTrackInPlace(updatedTrack)
            }
        case .genre(let genre):
            if let genreId = genre.id, genreId == updatedTrack.genreId {
                await refreshGenreEntity(genreId: genreId)
            } else {
                // Update track in place if it's in our list
                await updateTrackInPlace(updatedTrack)
            }
        case .playlist:
            // Update track in place instead of full reload
            await updateTrackInPlace(updatedTrack)
        }
    }
    
    /// Update a single track in the tracks array without full reload
    private func updateTrackInPlace(_ updatedTrack: Track) async {
        await MainActor.run {
            // Find and update the track in the array
            if let index = tracks.firstIndex(where: { $0.trackId == updatedTrack.trackId }) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    tracks[index] = updatedTrack
                }
            }
        }
    }
    
    /// Refresh playlist entity when playlist data changes
    private func refreshPlaylistEntityIfNeeded() async {
        guard case .playlist(let playlistItem) = entity,
              case .user(let playlist) = playlistItem.type,
              let playlistId = playlist.id else {
            return
        }

        // Fetch updated playlist directly from database with force refresh
        if let updatedPlaylist = try? await databaseManager.getPlaylist(playlistId: playlistId) {
            let oldTrackCount = playlist.trackCount
            let newTrackCount = updatedPlaylist.trackCount

            // Check if any metadata changed (name, description, artwork, isPinned)
            let nameChanged = playlist.name != updatedPlaylist.name
            let descriptionChanged = playlist.description != updatedPlaylist.description
            let artworkChanged = playlist.customArtworkData != updatedPlaylist.customArtworkData
            let isPinnedChanged = playlist.isFavorite != updatedPlaylist.isFavorite
            let metadataChanged = nameChanged || descriptionChanged || artworkChanged || isPinnedChanged

            await MainActor.run {
                // Update entity with new playlist data (entity ID stays the same, so .task won't trigger)
                // Force update by creating new PlaylistItem instance
                entity = .playlist(PlaylistItem(
                    id: playlistItem.id,
                    name: updatedPlaylist.name,
                    isPinned: updatedPlaylist.isFavorite,
                    type: .user(updatedPlaylist)
                ))

                // Force UI refresh if metadata changed by updating the refresh token
                if metadataChanged {
                    playlistRefreshToken = UUID()
                }
            }

            // Reload tracks if track count changed (to avoid unnecessary reload)
            if oldTrackCount != newTrackCount {
                await refreshTracksSilently()
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadTracks() async {
        do {
            let loadedTracks = try await entity.loadTracks(from: databaseManager)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tracks = loadedTracks
                    isLoading = false
                    hasLoadedInitialTracks = true
                    // Track count will be updated after filtering and sorting in initializeSortedTracks()
                }
            }
        } catch {
            Logger.error("Failed to load tracks for \(entity.displayName): \(error)")
            // Set isLoading to false on error so empty state can show if appropriate
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLoading = false
                    hasLoadedInitialTracks = true
                    displayedTrackCount = 0
                }
            }
        }
    }
    
    /// Refresh tracks without showing loading indicator (for silent updates)
    private func refreshTracksSilently() async {
        do {
            let loadedTracks = try await entity.loadTracks(from: databaseManager)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tracks = loadedTracks
                }
            }
        } catch {
            Logger.error("Failed to refresh tracks for \(entity.displayName): \(error)")
        }
    }
    
    // MARK: - Filtering
    
    private func applyFilter() {
        if let filter = selectedFilter {
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
            filteredTracks = tracks
        }
        
        // Re-sort after filtering
        initializeSortedTracks()
    }
    
    // MARK: - Sorting Helpers
    
    private func initializeSortedTracks() {
        // Use current sort order instead of resetting to default
        sortedTracks = filteredTracks.sorted(using: sortOrder)
        // Update displayed track count after sorting
        if hasLoadedInitialTracks {
            displayedTrackCount = sortedTracks.count
        }
    }

    private func performBackgroundSort(with newSortOrder: [KeyPathComparator<Track>]) {
        let tracksToSort = self.filteredTracks
        Task.detached(priority: .userInitiated) {
            let sorted = tracksToSort.sorted(using: newSortOrder)
            await MainActor.run {
                self.sortedTracks = sorted
                // Update displayed track count after sorting
                if self.hasLoadedInitialTracks {
                    self.displayedTrackCount = sorted.count
                }
            }
        }
    }

    private func refreshAlbumEntity(albumId: Int64) async {
        guard let updated = try? await databaseManager.getAlbum(albumId: albumId) else { return }
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                entity = .album(updated)
            }
        }
        // Silent refresh for metadata updates
        await refreshTracksSilently()
    }

    private func refreshArtistEntity(artistId: Int64) async {
        guard let updated = try? await databaseManager.getArtist(artistId: artistId) else { return }
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                entity = .artist(updated)
            }
        }
        // Silent refresh for metadata updates
        await refreshTracksSilently()
    }

    private func refreshGenreEntity(genreId: Int64) async {
        guard let updated = try? await databaseManager.dbQueue.read({ db in
            try Genre.fetchOne(db, key: genreId)
        }) else { return }
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                entity = .genre(updated)
            }
        }
        // Silent refresh for metadata updates
        await refreshTracksSilently()
    }

    private func loadArtistArtwork() async {
        guard case .artist(let artist) = entity, let artistId = artist.id else { return }
        await withCheckedContinuation { continuation in
            ArtworkCache.shared.getArtistArtwork(for: artistId, size: 160) { image in
                Task { @MainActor in
                    self.artistArtwork = image
                    self.artistArtworkToken = UUID()
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Sort Order Persistence
    
    private func restoreSortOrder() {
        let field = currentSortField.wrappedValue
        let isAscending = currentSortAscending.wrappedValue
        
        if let sortField = TrackSortField.allFields.first(where: { $0.rawValue == field }) {
            sortOrder = [sortField.getComparator(ascending: isAscending)]
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
                currentSortField.wrappedValue = field.rawValue
                currentSortAscending.wrappedValue = isAscending
                break
            }
        }
    }
}

// MARK: - Entity Type

enum EntityType: Identifiable, Hashable {
    case album(Album)
    case artist(Artist)
    case genre(Genre)
    case playlist(PlaylistItem)
    
    var id: String {
        switch self {
        case .album(let album): return "album_\(album.id ?? 0)"
        case .artist(let artist): return "artist_\(artist.id ?? 0)"
        case .genre(let genre): return "genre_\(genre.id ?? 0)"
        case .playlist(let playlist): return "playlist_\(playlist.id)"
        }
    }
    
    var uniqueId: String { id }
    
    var displayName: String {
        switch self {
        case .album(let album): return album.title
        case .artist(let artist): return artist.name
        case .genre(let genre): return genre.name
        case .playlist(let playlist): return playlist.name
        }
    }
    
    var icon: String {
        switch self {
        case .album: return "square.stack"
        case .artist: return "person.2"
        case .genre: return "guitars"
        case .playlist(let playlist): return playlist.icon
        }
    }
    
    var subtitle: String? {
        switch self {
        case .album(let album): return album.year
        case .artist(_): return nil
        case .genre(_): return nil
        case .playlist(let playlist):
            if case .smart(let smartType) = playlist.type {
                return smartType.description
            }
            return nil
        }
    }
    
    var playlistDescription: String? {
        switch self {
        case .playlist(let playlist):
            switch playlist.type {
            case .user(let p):
                return p.description
            case .smart(let smartType):
                return smartType.description
            }
        default:
            return nil
        }
    }
    
    var artworkData: Data? {
        switch self {
        case .album(let album): return album.artworkData
        case .artist: return nil
        case .genre: return nil
        case .playlist(let playlist): return playlist.artworkData
        }
    }
    
    var entityId: Int64? {
        switch self {
        case .album(let album): return album.id
        case .artist(let artist): return artist.id
        case .genre(let genre): return genre.id
        case .playlist(let playlist):
            if case .user(let p) = playlist.type {
                return p.id
            }
            return nil
        }
    }
    
    var isPinned: Bool {
        switch self {
        case .album, .artist, .genre: return false
        case .playlist(let playlist): return playlist.isPinned
        }
    }
    
    var colorScheme: String? {
        switch self {
        case .album, .artist, .genre: return nil
        case .playlist(let playlist):
            if case .user(let p) = playlist.type {
                return p.colorScheme
            }
            return nil
        }
    }
    
    var badgeText: String {
        switch self {
        case .album: return "ALBUM"
        case .artist: return "ARTIST"
        case .genre: return "GENRE"
        case .playlist(let playlist):
            if case .smart = playlist.type {
                return "SMART PLAYLIST"
            }
            return "PLAYLIST"
        }
    }
    
    var badgeIcon: String {
        switch self {
        case .album: return "square.stack"
        case .artist: return "person.2"
        case .genre: return "guitars"
        case .playlist(let playlist):
            if case .smart(let smartType) = playlist.type {
                return smartType.icon
            }
            return "music.note.list"
        }
    }

    var estimatedTrackCount: Int {
        switch self {
        case .album(let album): return album.trackCount
        case .artist(let artist): return artist.trackCount
        case .genre(let genre): return genre.trackCount
        case .playlist(let playlist): return playlist.trackCount
        }
    }
    
    func loadTracks(from database: DatabaseManager) async throws -> [Track] {
        switch self {
        case .album(let album):
            guard let albumId = album.id else { return [] }
            return try await database.getTracksForAlbum(albumId: albumId)
            
        case .artist(let artist):
            guard let artistId = artist.id else { return [] }
            return try await database.getTracksForArtist(artistId: artistId)
            
        case .genre(let genre):
            guard let genreId = genre.id else { return [] }
            return try await database.getTracksForGenre(genreId: genreId)
            
        case .playlist(let playlist):
            switch playlist.type {
            case .user(let p):
                guard let playlistId = p.id else { return [] }
                return try await database.getTracksForPlaylist(playlistId: playlistId)
                
            case .smart(let smartType):
                switch smartType {
                case .favorites:
                    return try await database.getFavoriteTracks()
                case .topPlayed:
                    return try await database.getTopPlayedTracks(limit: 25)
                case .recentlyPlayed:
                    return try await database.getRecentlyPlayedTracks(limit: 25)
                }
            }
        }
    }
}

// MARK: - Entity Header

struct EntityHeader: View {
    let entity: EntityType
    let trackCount: Int
    let totalDuration: Double
    let onPlay: () -> Void
    let onShuffle: () -> Void
    let artistArtwork: NSImage?
    let artistArtworkToken: UUID
    let onEdit: (() -> Void)?
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isPlayHovered = false
    @State private var isShuffleHovered = false
    @State private var isEditHovered = false
    
    init(entity: EntityType, trackCount: Int, totalDuration: Double, onPlay: @escaping () -> Void, onShuffle: @escaping () -> Void, artistArtwork: NSImage?, artistArtworkToken: UUID, onEdit: (() -> Void)? = nil) {
        self.entity = entity
        self.trackCount = trackCount
        self.totalDuration = totalDuration
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.artistArtwork = artistArtwork
        self.artistArtworkToken = artistArtworkToken
        self.onEdit = onEdit
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 40) {
            // Artwork
            artworkView
                .padding(.leading, 12)
            
            // Info and controls
            VStack(alignment: .leading, spacing: 0) {
                // Entity badge with edit button (for user playlists)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: entity.badgeIcon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(entity.badgeText)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(entity.isPinned ? theme.currentTheme.primaryColor : .secondary)
                    
                    // Edit button (only for user-created playlists)
                    if let onEdit = onEdit,
                       case .playlist(let playlistItem) = entity,
                       case .user = playlistItem.type {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(isEditHovered ? theme.currentTheme.primaryColor : .secondary)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(isEditHovered ? theme.currentTheme.primaryColor.opacity(0.1) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isEditHovered = hovering
                        }
                        .help("Edit Playlist")
                    }
                }
                .frame(height: 20, alignment: .center)
                .padding(.bottom, 12)
                
                // Entity name
                Text(entity.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: false)
                    .padding(.bottom, 4)
                    .animation(.easeInOut(duration: 0.2), value: entity.displayName)
                
                // Description (for playlists)
                if case .playlist = entity, let description = entity.playlistDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: false)
                        .padding(.bottom, 4)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: description)
                }
                
                // Stats (songs count and duration)
                HStack(spacing: 8) {
                    if entity.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 12))
                            .foregroundColor(theme.currentTheme.primaryColor)
                    }
                    
                    Text("\(trackCount) \(trackCount == 1 ? "song" : "songs")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.2), value: trackCount)
                    
                    if totalDuration > 0 {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text(formatDuration(totalDuration))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .animation(.easeInOut(duration: 0.2), value: totalDuration)
                    }
                }
                .padding(.bottom, 8)
                
                Spacer(minLength: 0)
                
                // Action buttons - aligned to bottom
                HStack(spacing: 12) {
                    // Play button
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(isPlayHovered ? theme.currentTheme.primaryColor.opacity(0.9) : theme.currentTheme.primaryColor)
                            )
                            .scaleEffect(isPlayHovered ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isPlayHovered = hovering
                    }
                    .disabled(trackCount == 0)
                    
                    // Shuffle button
                    Button(action: onShuffle) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(isShuffleHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.8) : Color(nsColor: .controlBackgroundColor))
                            )
                            .scaleEffect(isShuffleHovered ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isShuffleHovered = hovering
                    }
                    .disabled(trackCount == 0)
                }
            }
            .frame(height: 160, alignment: .top)
            
            Spacer()
        }
        .padding(20)
        .background(.regularMaterial)
//        .background(gradientBackground)
        .textSelection(.enabled)
    }
    
    // MARK: - Artwork View
    
    @ViewBuilder
    private var artworkView: some View {
        ZStack {
            if let imageData = entity.artworkData, let nsImage = NSImage(data: imageData) {
                let artworkKey = "\(entity.id)-\(imageData.hashValue)"
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 160, height: 160)
                    .cornerRadius(entity.isArtist ? 100 : 12)
                    .shadow(radius: 20)
                    .id("entity-art-\(artworkKey)")
                    .transition(.opacity)
            } else if case .artist = entity, let image = artistArtwork {
                let artworkKey = "\(entity.id)-artist-\(artistArtworkToken)"
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 160, height: 160)
                    .cornerRadius(100)
                    .shadow(radius: 20)
                    .id("entity-art-\(artworkKey)")
                    .transition(.opacity)
            } else if entity.isArtist, let artistId = entity.entityId {
                ArtistArtworkView(artistId: artistId, size: 160)
                    .shadow(radius: 20)
                    .transition(.opacity)
            } else if entity.isAlbum, let albumId = entity.entityId {
                AlbumArtworkView(albumId: albumId, size: 160, cornerRadius: 12)
                    .shadow(radius: 20)
                    .transition(.opacity)
            } else {
                placeholderArtwork
                    .transition(.opacity)
            }
        }
        .id(entity.id) // Stabilize artwork view
        .animation(.easeInOut(duration: 0.25), value: entity.artworkData?.hashValue)
    }
    
    private var placeholderArtwork: some View {
        Group {
            if entity.isArtist {
                Circle()
                    .fill(entityGradient)
                    .frame(width: 160, height: 160)
                    .overlay {
                        Image(systemName: entity.icon)
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .shadow(radius: 20)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(entityGradient)
                    .frame(width: 160, height: 160)
                    .overlay {
                        Image(systemName: entity.icon)
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .shadow(radius: 20)
            }
        }
    }
    
    private var entityGradient: LinearGradient {
        LinearGradient(
            colors: [
                theme.currentTheme.primaryColor.opacity(0.8),
                theme.currentTheme.primaryColor.opacity(0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var gradientBackground: some View {
        LinearGradient(
            colors: [
                theme.currentTheme.primaryColor.opacity(0.15),
                Color(nsColor: .windowBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Entity Type Helpers

extension EntityType {
    var isAlbum: Bool {
        if case .album = self { return true }
        return false
    }
    
    var isArtist: Bool {
        if case .artist = self { return true }
        return false
    }
    
    var isGenre: Bool {
        if case .genre = self { return true }
        return false
    }
    
    var isPlaylist: Bool {
        if case .playlist = self { return true }
        return false
    }
}

// MARK: - Convenience Wrapper

/// Playlist detail view using generic EntityDetailView
struct PlaylistDetailView: View {
    let playlist: PlaylistItem
    
    var body: some View {
        EntityDetailView(entity: .playlist(playlist))
    }
}
