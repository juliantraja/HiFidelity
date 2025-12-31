//
//  TrackInfoPanel.swift
//  HiFidelity
//
//  Track information panel showing detailed metadata
//

import SwiftUI
import GRDB
import AppKit

/// Manages track info panel state
@MainActor
class TrackInfoManager: ObservableObject {
    @Published var selectedTrack: Track?
    @Published var isVisible: Bool = false
    @Published var allTracks: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var clearedTrackIds: Set<Int64> = [] // Persist cleared artwork state across panel close/reopen

    func show(track: Track, allTracks: [Track] = [], currentIndex: Int = 0) {
        selectedTrack = track
        self.allTracks = allTracks
        self.currentIndex = currentIndex
        isVisible = true
    }

    func hide() {
        isVisible = false
        // Delay clearing to allow smooth animation
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            selectedTrack = nil
            allTracks = []
            currentIndex = 0
            // NOTE: Don't clear clearedTrackIds - we want to persist cleared artwork state
        }
    }
}

/// Panel showing detailed information about a selected track
struct TrackInfoPanel: View {
    @EnvironmentObject var trackInfoManager: TrackInfoManager
    @ObservedObject var theme = AppTheme.shared

    @State private var fullTrack: Track?
    @State private var isLoading = false
    @State private var songFeatures: SongFeatures?

    // Editable fields
    @State private var editableTitle: String = ""
    @State private var editableArtist: String = ""
    @State private var editableAlbum: String = ""
    @State private var editableYear: String = ""
    @State private var editableGenre: String = ""
    @State private var editableComposer: String = ""
    @State private var editableTrackNumber: String = ""
    @State private var editableDiscNumber: String = ""
    @State private var editableArtwork: NSImage?
    @State private var hasChanges: Bool = false
    @State private var isSaving: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var isArtworkLoading: Bool = false
    @State private var isHoveringArtwork: Bool = false
    @State private var isClearingArtwork: Bool = false
    @State private var isInitializingArtwork: Bool = false
    @State private var artworkCleared: Bool = false
    @State private var isSavingArtwork: Bool = false // Flag to prevent onChange from overwriting preserved artwork
    // clearedTrackIds is now stored in trackInfoManager to persist across panel close/reopen

    // Navigation - removed local state, use trackInfoManager's tracks
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            if let track = fullTrack ?? trackInfoManager.selectedTrack {
                trackDetails(track: track)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: trackInfoManager.selectedTrack?.trackId) {
            if let selectedTrack = trackInfoManager.selectedTrack {
                await loadFullTrackInfo(for: selectedTrack)
            }
        }
        .onChange(of: fullTrack) { _, newTrack in
            if let track = newTrack {
                // CRITICAL: Don't reload artwork if we're in the middle of saving artwork
                // This prevents onChange from overwriting preserved artwork after saveChanges()
                if isSavingArtwork {
                    Logger.debug("🖼️ onChange(fullTrack): Skipping artwork reload - save in progress")
                    // Only update non-artwork fields
                    editableTitle = track.title
                    editableArtist = track.artist
                    editableAlbum = track.album
                    editableYear = track.year.isEmpty ? "" : track.year
                    editableGenre = track.genre.isEmpty ? "" : track.genre
                    editableComposer = track.composer.isEmpty ? "" : track.composer
                    editableTrackNumber = track.trackNumber.map { String($0) } ?? ""
                    editableDiscNumber = track.discNumber.map { String($0) } ?? ""
                    // Keep existing artwork (preserved by saveChanges)
                    return
                }
                
                // Check if this is the track that had its artwork cleared
                let isClearedTrack = track.trackId.map { trackInfoManager.clearedTrackIds.contains($0) } ?? false
                
                // Don't reload artwork if it was explicitly cleared for this track
                if isClearedTrack {
                    // This is the cleared track - only update non-artwork fields
                    Logger.debug("🖼️ Track \(track.trackId ?? 0) is cleared - skipping artwork load")
                    editableTitle = track.title
                    editableArtist = track.artist
                    editableAlbum = track.album
                    editableYear = track.year.isEmpty ? "" : track.year
                    editableGenre = track.genre.isEmpty ? "" : track.genre
                    editableComposer = track.composer.isEmpty ? "" : track.composer
                    editableTrackNumber = track.trackNumber.map { String($0) } ?? ""
                    editableDiscNumber = track.discNumber.map { String($0) } ?? ""
                    // Keep artwork as nil and cleared flag as true
                    editableArtwork = nil
                    artworkCleared = true
                    hasChanges = false
                } else {
                    // Different track or not cleared - initialize normally
                    // Reset cleared flag if this is a different track
                    // IMPORTANT: Don't remove from clearedTrackIds - keep it so we remember which tracks were cleared
                    if let trackId = track.trackId {
                        if trackInfoManager.clearedTrackIds.contains(trackId) {
                            // This track is cleared - don't initialize artwork
                            Logger.debug("🖼️ onChange(fullTrack): Track \(trackId) is cleared - skipping initializeEditableFields")
                            editableTitle = track.title
                            editableArtist = track.artist
                            editableAlbum = track.album
                            editableYear = track.year.isEmpty ? "" : track.year
                            editableGenre = track.genre.isEmpty ? "" : track.genre
                            editableComposer = track.composer.isEmpty ? "" : track.composer
                            editableTrackNumber = track.trackNumber.map { String($0) } ?? ""
                            editableDiscNumber = track.discNumber.map { String($0) } ?? ""
                            editableArtwork = nil
                            artworkCleared = true
                            hasChanges = false
                        } else {
                            artworkCleared = false
                            initializeEditableFields(from: track)
                        }
                    } else {
                        artworkCleared = false
                        initializeEditableFields(from: track)
                    }
                }
            }
        }
        .onChange(of: trackInfoManager.selectedTrack?.trackId) { oldTrackId, newTrackId in
            // Force artwork update when navigating to different track (only if trackId actually changed)
            if oldTrackId != newTrackId, let track = trackInfoManager.selectedTrack {
                // Reset artwork to force reload
                isInitializingArtwork = true
                editableArtwork = nil
                
                // Check if this is the track that had its artwork cleared
                // IMPORTANT: Don't remove from clearedTrackIds - keep it so we know which tracks were cleared
                if let newTrackId = newTrackId, trackInfoManager.clearedTrackIds.contains(newTrackId) {
                    // This is the cleared track - keep artworkCleared = true
                    Logger.debug("🖼️ Navigating to cleared track \(newTrackId) - keeping artwork cleared")
                    artworkCleared = true
                    // Don't call initializeEditableFields - let loadFullTrackInfo handle it
                } else {
                    // Different track - reset cleared flag for this track only
                    // But keep clearedTrackIds set so we remember which tracks were cleared
                    Logger.debug("🖼️ Navigating to different track \(newTrackId ?? 0) - resetting cleared flag (clearedTrackIds: \(trackInfoManager.clearedTrackIds))")
                    artworkCleared = false
                    // Don't remove from clearedTrackIds - we want to remember which tracks were cleared
                    initializeEditableFields(from: track)
                }
                // Reset flag after a brief delay to allow artwork to load
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    isInitializingArtwork = false
                }
            }
        }
        .onChange(of: editableArtwork) { oldValue, newValue in
            // When new artwork is selected, clear old artwork first
            // This ensures the old artwork is deleted and replaced with the new one
            if newValue != nil && oldValue != nil && !isInitializingArtwork {
                // User is replacing existing artwork - clear old one first
                // The old artwork will be cleared when we save with the new artwork
                Logger.debug("🖼️ Replacing artwork - old artwork will be cleared on save")
            }
            
            // Reset cleared flag when new artwork is set
            if newValue != nil {
                artworkCleared = false
                // Remove from cleared track IDs if artwork is added back
                if let trackId = fullTrack?.trackId {
                    trackInfoManager.clearedTrackIds.remove(trackId)
                }
            }
            
            // Auto-save when artwork is changed by user (not during initialization, clearing, or loading)
            // Only save if:
            // 1. Value actually changed
            // 2. Not currently saving
            // 3. Not clearing artwork
            // 4. Not initializing/loading artwork from database
            if oldValue != newValue 
                && !isSaving 
                && !isClearingArtwork 
                && !isInitializingArtwork {
                // User explicitly changed artwork (via image picker)
                hasChanges = true
                isArtworkLoading = true
                Task {
                    await saveChanges()
                    isArtworkLoading = false
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $editableArtwork)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("Track Info")
                .font(.system(size: 16, weight: .bold))
                .frame(height: 28)
                .foregroundColor(.primary)

            Spacer()

            // Navigation buttons
            HStack(spacing: 8) {
                // Show saving indicator when saving (fixed width to prevent layout shift)
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    // Invisible spacer to maintain layout when not saving
                    Color.clear
                        .frame(width: 16, height: 16)
                }

                // Previous track button
                Button(action: {
                    navigateToPreviousTrack()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
                .help("Previous track")

                // Next track button
                Button(action: {
                    navigateToNextTrack()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
                .help("Next track")
            }

            Button(action: {
                trackInfoManager.hide()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Data Loading
    
    private func loadFullTrackInfo(for track: Track) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch full track data from database including all metadata
            if let trackId = track.trackId {
                fullTrack = try await DatabaseManager.shared.dbQueue.read { db in
                    try Track
                        .filter(Track.Columns.trackId == trackId)
                        .fetchOne(db)
                }

                // Fetch song features (BPM, Key, etc.)
                songFeatures = try? await DatabaseManager.shared.getSongFeatures(forTrackId: trackId)

                Logger.debug("Loaded full track info for: \(track.title)")
            } else {
                fullTrack = track
                songFeatures = nil
            }
        } catch {
            Logger.error("Failed to load full track info: \(error)")
            fullTrack = track
            songFeatures = nil
        }
    }

    // MARK: - Navigation

    private func navigateToPreviousTrack() {
        guard !trackInfoManager.allTracks.isEmpty else { return }

        let newIndex = (trackInfoManager.currentIndex - 1 + trackInfoManager.allTracks.count) % trackInfoManager.allTracks.count
        let previousTrack = trackInfoManager.allTracks[newIndex]

        trackInfoManager.show(track: previousTrack, allTracks: trackInfoManager.allTracks, currentIndex: newIndex)

        // Update library view selection - use database trackId instead of UUID
        if let trackId = previousTrack.trackId {
            NotificationCenter.default.post(
                name: .updateTrackSelection,
                object: nil,
                userInfo: ["databaseTrackId": trackId]
            )
        }
    }

    private func navigateToNextTrack() {
        guard !trackInfoManager.allTracks.isEmpty else { return }

        let newIndex = (trackInfoManager.currentIndex + 1) % trackInfoManager.allTracks.count
        let nextTrack = trackInfoManager.allTracks[newIndex]

        trackInfoManager.show(track: nextTrack, allTracks: trackInfoManager.allTracks, currentIndex: newIndex)

        // Update library view selection - use database trackId instead of UUID
        if let trackId = nextTrack.trackId {
            NotificationCenter.default.post(
                name: .updateTrackSelection,
                object: nil,
                userInfo: ["databaseTrackId": trackId]
            )
        }
    }
    
    // MARK: - Initialize Editable Fields
    
    private func initializeEditableFields(from track: Track) {
        // CRITICAL: Check if this track is cleared FIRST - before doing anything else
        // This prevents any artwork from being loaded for cleared tracks, regardless of where this function is called from
        if let trackId = track.trackId, trackInfoManager.clearedTrackIds.contains(trackId) {
            Logger.debug("🖼️ initializeEditableFields: Track \(trackId) is cleared - skipping ALL artwork loading")
            editableTitle = track.title
            editableArtist = track.artist
            editableAlbum = track.album
            editableYear = track.year.isEmpty ? "" : track.year
            editableGenre = track.genre.isEmpty ? "" : track.genre
            editableComposer = track.composer.isEmpty ? "" : track.composer
            editableTrackNumber = track.trackNumber.map { String($0) } ?? ""
            editableDiscNumber = track.discNumber.map { String($0) } ?? ""
            editableArtwork = nil
            artworkCleared = true
            isInitializingArtwork = false
            hasChanges = false
            return
        }
        
        editableTitle = track.title
        editableArtist = track.artist
        editableAlbum = track.album
        editableYear = track.year.isEmpty ? "" : track.year
        editableGenre = track.genre.isEmpty ? "" : track.genre
        editableComposer = track.composer.isEmpty ? "" : track.composer
        editableTrackNumber = track.trackNumber.map { String($0) } ?? ""
        editableDiscNumber = track.discNumber.map { String($0) } ?? ""
        
        // Load artwork for the track (set flag to prevent save trigger)
        // Note: We already checked if track is cleared at the start of this function, so we can safely load artwork here
        isInitializingArtwork = true
        artworkCleared = false // Reset cleared flag when initializing new track
        if let artworkData = track.artworkData, let image = NSImage(data: artworkData) {
            editableArtwork = image
            artworkCleared = false
            // Reset flag after a delay to ensure onChange doesn't trigger save
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                isInitializingArtwork = false
            }
        } else {
            // Try to load from album/artist if track doesn't have direct artwork
            editableArtwork = nil // Clear first to show loading state
            artworkCleared = false // Not explicitly cleared, just loading
            Task {
                if let trackId = track.trackId {
                    await loadArtworkForTrack(trackId: trackId)
                }
                // Reset flag after loading completes (with delay to ensure stability)
                try? await Task.sleep(for: .milliseconds(200))
                isInitializingArtwork = false
            }
        }
        
        hasChanges = false
    }
    
    private func loadArtworkForTrack(trackId: Int64) async {
        // Only set if we still don't have editable artwork (user might have set custom artwork)
        guard editableArtwork == nil else { return }
        
        // CRITICAL: Don't load if artwork was explicitly cleared for this track
        // Check this FIRST before any other logic
        if trackInfoManager.clearedTrackIds.contains(trackId) {
            Logger.debug("🖼️ loadArtworkForTrack: Track \(trackId) is cleared - skipping load")
            editableArtwork = nil
            artworkCleared = true
            return
        }
        
        // Don't load if artwork was explicitly cleared (general check)
        guard !artworkCleared else {
            editableArtwork = nil
            return
        }
        
        // Load artwork from cache/database using async/await pattern
        await withCheckedContinuation { continuation in
            ArtworkCache.shared.getArtwork(for: trackId, size: 280) { image in
                Task { @MainActor in
                    // CRITICAL: Double-check cleared state before setting artwork
                    // The track might have been cleared while we were loading
                    if trackInfoManager.clearedTrackIds.contains(trackId) {
                        Logger.debug("🖼️ loadArtworkForTrack: Track \(trackId) was cleared during load - skipping")
                        editableArtwork = nil
                        artworkCleared = true
                        continuation.resume()
                        return
                    }
                    
                    // Only set if we still don't have editable artwork and wasn't cleared
                    if editableArtwork == nil && !artworkCleared && !trackInfoManager.clearedTrackIds.contains(trackId) {
                        isInitializingArtwork = true
                        editableArtwork = image
                        // Reset flag after setting artwork
                        Task {
                            try? await Task.sleep(for: .milliseconds(100))
                            isInitializingArtwork = false
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Track Details
    
    private func trackDetails(track: Track) -> some View {
        ScrollView() {
            VStack(spacing: 24) {
                // Large album artwork (editable)
                artworkView(track: track)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    .padding(.top, 32)
                    .id("artwork-wrapper-\(artworkCleared)-\(editableArtwork != nil ? "has" : "nil")")
                
                // Track info (editable)
                VStack(spacing: 8) {
                    EditableTextField(
                        text: $editableTitle,
                        placeholder: "Title",
                        onSubmit: { Task { await saveChanges() } },
                        enableScrolling: true,
                        font: AppFonts.trackTitle,
                        foregroundColor: .primary
                    )
                    .id("title-\(track.id)")

                    EditableTextField(
                        text: $editableArtist,
                        placeholder: "Artist",
                        onSubmit: { Task { await saveChanges() } },
                        enableScrolling: true,
                        font: AppFonts.trackArtist,
                        foregroundColor: .secondary
                    )
                    .id("artist-\(track.id)")

                    EditableTextField(
                        text: $editableAlbum,
                        placeholder: "Album",
                        onSubmit: { Task { await saveChanges() } },
                        enableScrolling: true,
                        font: AppFonts.trackAlbum,
                        foregroundColor: .secondary.opacity(0.8)
                    )
                    .id("album-\(track.id)")
                }
                .padding(.horizontal, 24)
                
                // Track details
                VStack(spacing: 12) {
                    // Read-only fields
                    DetailRow(icon: "clock", label: "Duration", value: track.formattedDuration)
                    
                    // Editable fields
                    EditableDetailRow(icon: "calendar", label: "Year", text: $editableYear, placeholder: "Year") {
                        Task { await saveChanges() }
                    }

                    EditableDetailRow(icon: "guitars", label: "Genre", text: $editableGenre, placeholder: "Genre") {
                        Task { await saveChanges() }
                    }

                    EditableDetailRow(icon: "music.note.list", label: "Composer", text: $editableComposer, placeholder: "Composer") {
                        Task { await saveChanges() }
                    }

                    // Track/Disc numbers (editable)
                    EditableDetailRow(icon: "number", label: "Track #", text: $editableTrackNumber, placeholder: "Track Number") {
                        Task { await saveChanges() }
                    }

                    EditableDetailRow(icon: "opticaldisc", label: "Disc #", text: $editableDiscNumber, placeholder: "Disc Number") {
                        Task { await saveChanges() }
                    }
                    
                    // Read-only fields
                    DetailRow(icon: "play.circle", label: "Play Count", value: "\(track.playCount)")
                    
                    if let lastPlayed = track.lastPlayedDate {
                        DetailRow(icon: "clock.arrow.circlepath", label: "Last Played", value: formatDate(lastPlayed))
                    }
                    
                    // Audio quality (read-only)
                    if let bitrate = track.bitrate {
                        DetailRow(icon: "waveform", label: "Bitrate", value: "\(bitrate) kbps")
                    }
                    
                    if let sampleRate = track.sampleRate {
                        let formattedRate = formatSampleRate(sampleRate)
                        DetailRow(icon: "dial.high", label: "Sample Rate", value: formattedRate)
                    }
                    
                    if let codec = track.codec {
                        DetailRow(icon: "waveform.circle", label: "Codec", value: codec)
                    }
                    
                    // File info (read-only)
                    DetailRow(icon: "doc", label: "Format", value: track.format)
                    
                    if let fileSize = track.fileSize {
                        DetailRow(icon: "externaldrive", label: "File Size", value: formatFileSize(fileSize))
                    }
                    
                    // Additional metadata (read-only)
                    if let dateAdded = track.dateAdded {
                        DetailRow(icon: "calendar.badge.plus", label: "Date Added", value: formatDate(dateAdded))
                    }
                    
                    if let bpm = track.bpm {
                        DetailRow(icon: "metronome", label: "BPM", value: "\(bpm)")
                    }

                    if let features = songFeatures,
                       let key = features.key,
                       let mode = features.mode {
                        let formatRaw = UserDefaults.standard.string(forKey: "keyDisplayFormat") ?? KeyDisplayFormat.note.rawValue
                        let format = KeyDisplayFormat(rawValue: formatRaw) ?? .note
                        let keyDisplay = KeyNotation.displayName(key: key, mode: mode, format: format)
                        DetailRow(icon: "music.quarternote.3", label: "Key", value: keyDisplay)
                    }
                    
                    // Filename (read-only, but displayed)
                    DetailRow(icon: "doc.text", label: "Filename", value: track.filename)
                }
                .padding(.horizontal, 24)
                
                // Bottom spacer for playback bar clearance
                Spacer()
                    .frame(height: 110)
            }
        }
    }
    
    // MARK: - Artwork View
    
    @ViewBuilder
    private func artworkView(track: Track) -> some View {
        ZStack {
            if artworkCleared {
                // Explicitly cleared - always show placeholder
                placeholderArtworkView
                    .id("cleared-\(track.trackId ?? 0)")
            } else if let image = editableArtwork {
                // Has artwork - show it
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .id("artwork-\(image.hashValue)")
                    .opacity(isHoveringArtwork ? 0.7 : 1.0) // Reduce opacity on hover to indicate clickability
            } else {
                // No artwork set yet - show placeholder
                placeholderArtworkView
                    .id("placeholder-\(track.trackId ?? 0)")
                    .opacity(isHoveringArtwork ? 0.7 : 1.0) // Reduce opacity on hover to indicate clickability
            }

            // Button overlays - only show on hover
            if isHoveringArtwork {
                VStack {
                    HStack {
                        Spacer()

                        // Clear button (show if there's artwork)
                        if editableArtwork != nil {
                            Button(action: {
                                // Immediately clear artwork to show placeholder - set state synchronously
                                isClearingArtwork = true
                                artworkCleared = true
                                if let trackId = track.trackId {
                                    trackInfoManager.clearedTrackIds.insert(trackId) // Remember which track was cleared
                                }
                                editableArtwork = nil
                                hasChanges = true
                                
                                // Invalidate cache immediately so artwork doesn't reload
                                if let trackId = track.trackId {
                                    ArtworkCache.shared.invalidate(trackId: trackId)
                                    if let albumId = track.albumId {
                                        ArtworkCache.shared.invalidateAlbum(albumId: albumId)
                                    }
                                    if let artistId = track.artistId {
                                        ArtworkCache.shared.invalidateArtist(artistId: artistId)
                                    }
                                }
                                
                                // Save the change after a brief delay to allow state to update
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(50))
                                    isClearingArtwork = false
                                    await saveChanges()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }

                    Spacer()
                }
                .frame(width: 280, height: 280)
                .transition(.opacity)
            }
        }
        .frame(width: 280, height: 280)
        .id("artwork-container-\(artworkCleared)-\(editableArtwork != nil)")
        .contentShape(Rectangle()) // Make entire area clickable
        .onTapGesture {
            // Clicking on artwork opens image picker
            showImagePicker = true
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHoveringArtwork = hovering
            }
        }
    }
    
    private var placeholderArtworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
            
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.3))
        }
        .frame(width: 280, height: 280)
    }
    
    // MARK: - Save Changes
    
    private func saveChanges() async {
        Logger.info("🔵 saveChanges() called")
        guard var track = fullTrack, track.trackId != nil else {
            Logger.error("Cannot save: no track or trackId")
            return
        }
        let playback = PlaybackController.shared
        let editingPlaybackTrackId = track.trackId
        let isEditingCurrentPlaybackTrack = editingPlaybackTrackId != nil && playback.currentTrack?.trackId == editingPlaybackTrackId
        let savedPlaybackPosition = isEditingCurrentPlaybackTrack ? playback.currentTime : nil
        let wasPlayingTrack = isEditingCurrentPlaybackTrack ? playback.isPlaying : false
        
        // Prevent duplicate saves
        guard !isSaving else {
            Logger.debug("Already saving, skipping duplicate saveChanges() call")
            return
        }

        isSaving = true
        // Set flag to prevent onChange handler from reloading artwork during save
        isSavingArtwork = true
        defer { 
            isSaving = false
            // Reset flag after a brief delay to allow saved state to settle
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                isSavingArtwork = false
            }
        }

        Logger.debug("Starting metadata save for track: \(track.title)")
        
        do {
            // Update track fields
            track.title = editableTitle.isEmpty ? track.title : editableTitle
            track.artist = editableArtist.isEmpty ? track.artist : editableArtist
            track.album = editableAlbum.isEmpty ? track.album : editableAlbum
            track.year = editableYear.isEmpty ? "" : editableYear
            track.genre = editableGenre.isEmpty ? "" : editableGenre
            track.composer = editableComposer.isEmpty ? "" : editableComposer
            track.trackNumber = Int(editableTrackNumber)
            track.discNumber = Int(editableDiscNumber)
            
            // Update artwork if changed (including clearing it)
            var artworkDataToSave: Data?
            if let image = editableArtwork {
                if let tiffData = image.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    track.artworkData = pngData
                    artworkDataToSave = pngData
                    hasChanges = true
                }
            } else {
                // Artwork was cleared - set to nil
                track.artworkData = nil
                artworkDataToSave = nil
                hasChanges = true
            }
            
            // Capture all values needed for database operations (avoid capturing mutable 'track')
            let title = track.title
            let artist = track.artist
            let album = track.album
            let year = track.year
        let genre = track.genre
        let albumArtist = track.albumArtist
        let composer = track.composer
        let trackNumber = track.trackNumber
        let discNumber = track.discNumber
        let originalGenreId = track.genreId
        let originalAlbumId = track.albumId
        let originalArtistId = track.artistId
        let artworkData = artworkDataToSave
        let trackId = track.trackId
        let duration = track.duration
        // format is automatically set from URL during Track initialization, no need to capture
        let folderId = track.folderId
            let isFavorite = track.isFavorite
            let playCount = track.playCount
            let lastPlayedDate = track.lastPlayedDate
            let rating = track.rating
            let totalTracks = track.totalTracks
            let totalDiscs = track.totalDiscs
            let compilation = track.compilation
            let releaseDate = track.releaseDate
            let originalReleaseDate = track.originalReleaseDate
            let bpm = track.bpm
            let mediaType = track.mediaType
            let sortTitle = track.sortTitle
            let sortArtist = track.sortArtist
            let sortAlbum = track.sortAlbum
            let sortAlbumArtist = track.sortAlbumArtist
            let bitrate = track.bitrate
            let sampleRate = track.sampleRate
            let channels = track.channels
            let codec = track.codec
            let bitDepth = track.bitDepth
            let fileSize = track.fileSize
            let dateModified = track.dateModified
            let isMetadataLoaded = track.isMetadataLoaded
            let isDuplicate = track.isDuplicate
            let dateAdded = track.dateAdded
            let primaryTrackId = track.primaryTrackId
            let duplicateGroupId = track.duplicateGroupId
            let extendedMetadata = track.extendedMetadata
            let r128IntegratedLoudness = track.r128IntegratedLoudness
            let url = track.url
                
            // Save to database
            try await DatabaseManager.shared.dbQueue.write { db in
                // Update normalized entities
                let albumId = try DatabaseManager.getOrCreateAlbum(
                    in: db,
                    title: album,
                    albumArtist: albumArtist,
                    artist: artist,
                    year: year,
                    releaseType: nil,
                    recordLabel: nil,
                    musicbrainzAlbumId: nil,
                    releaseDate: nil,
                    musicbrainzReleaseGroupId: nil,
                    barcode: nil,
                    catalogNumber: nil,
                    releaseCountry: nil
                )
                
                let artistId = try DatabaseManager.getOrCreateArtist(
                    in: db,
                    name: artist,
                    musicbrainzArtistId: nil,
                    artistType: nil,
                    country: nil
                )
                
                let genreId = try DatabaseManager.getOrCreateGenre(
                    in: db,
                    name: genre,
                    style: nil
                )
                
                // Create updated track from captured values (no mutation of captured var)
                var updatedTrack = Track(url: url)
                updatedTrack.trackId = trackId
                updatedTrack.title = title
                updatedTrack.artist = artist
                updatedTrack.album = album
                updatedTrack.duration = duration
                // format is a let constant, set automatically from URL during Track initialization
                updatedTrack.folderId = folderId
                updatedTrack.albumArtist = albumArtist
                updatedTrack.composer = composer
                updatedTrack.genre = genre
                updatedTrack.year = year
                updatedTrack.isFavorite = isFavorite
                updatedTrack.playCount = playCount
                updatedTrack.lastPlayedDate = lastPlayedDate
                updatedTrack.rating = rating
                updatedTrack.trackNumber = trackNumber
                updatedTrack.totalTracks = totalTracks
                updatedTrack.discNumber = discNumber
                updatedTrack.totalDiscs = totalDiscs
                updatedTrack.compilation = compilation
                updatedTrack.releaseDate = releaseDate
                updatedTrack.originalReleaseDate = originalReleaseDate
                updatedTrack.bpm = bpm
                updatedTrack.mediaType = mediaType
                updatedTrack.sortTitle = sortTitle
                updatedTrack.sortArtist = sortArtist
                updatedTrack.sortAlbum = sortAlbum
                updatedTrack.sortAlbumArtist = sortAlbumArtist
                updatedTrack.bitrate = bitrate
                updatedTrack.sampleRate = sampleRate
                updatedTrack.channels = channels
                updatedTrack.codec = codec
                updatedTrack.bitDepth = bitDepth
                updatedTrack.fileSize = fileSize
                updatedTrack.dateModified = dateModified
                updatedTrack.isMetadataLoaded = isMetadataLoaded
                updatedTrack.isDuplicate = isDuplicate
                updatedTrack.dateAdded = dateAdded
                updatedTrack.primaryTrackId = primaryTrackId
                updatedTrack.duplicateGroupId = duplicateGroupId
                updatedTrack.extendedMetadata = extendedMetadata
                updatedTrack.r128IntegratedLoudness = r128IntegratedLoudness
                updatedTrack.albumId = albumId
                updatedTrack.artistId = artistId
                updatedTrack.genreId = genreId
                
                // Update artwork storage (or clear it)
                if let artworkData = artworkData {
                    let hasValidAlbum = !album.isEmpty && album != "Unknown Album"
                    if hasValidAlbum, let albumId = albumId {
                        try Self.storeAlbumArtwork(albumId: albumId, artworkData: artworkData, in: db)
                        updatedTrack.artworkData = nil
                    } else {
                        updatedTrack.artworkData = artworkData
                    }
                    
                    if let artistId = artistId {
                        try Self.storeArtistArtwork(artistId: artistId, artworkData: artworkData, sourceType: hasValidAlbum ? "album" : "track", in: db)
                    }
                } else {
                    // Artwork was cleared - remove from track, album, and artist
                    updatedTrack.artworkData = nil
                    if let albumId = albumId {
                        try db.execute(
                            sql: "UPDATE albums SET artwork_data = NULL WHERE id = ?",
                            arguments: [albumId]
                        )
                    }
                    if let artistId = artistId {
                        try db.execute(
                            sql: "UPDATE artists SET artwork_data = NULL WHERE id = ?",
                            arguments: [artistId]
                        )
                    }
                }
                
                // Update the track
                try updatedTrack.update(db)

                // If genre changed, clean up old genre if orphaned
                if originalGenreId != genreId {
                    try DatabaseManager.deleteGenreIfOrphan(in: db, genreId: originalGenreId)
                }
                if originalAlbumId != albumId {
                    try DatabaseManager.deleteAlbumIfOrphan(in: db, albumId: originalAlbumId)
                }
                if originalArtistId != artistId {
                    try DatabaseManager.deleteArtistIfOrphan(in: db, artistId: originalArtistId)
                }
            }
            
            // Create track object for file writing (using captured values)
            var trackForFile = Track(url: url)
            trackForFile.trackId = trackId
            trackForFile.title = title
            trackForFile.artist = artist
            trackForFile.album = album
            trackForFile.genre = genre
            trackForFile.year = year
            trackForFile.albumArtist = albumArtist
            trackForFile.composer = composer
            trackForFile.trackNumber = trackNumber
            trackForFile.discNumber = discNumber
            trackForFile.artworkData = artworkData
            
            // Write metadata to file (defer if the track is currently playing to avoid audio glitches)
            let shouldDeferFileWrite = isEditingCurrentPlaybackTrack && playback.audioEngine.isPlaying()
            
            let performFileWrite: () -> Void = {
                Logger.debug("Attempting to write metadata to file: \(url.path)")
                Logger.debug("File exists: \(FileManager.default.fileExists(atPath: url.path))")
                Logger.debug("Metadata to write - Title: \(title), Artist: \(artist), Album: \(album), Genre: \(genre), Year: \(year)")

                // Tell folder watcher to ignore this file before we write to it
                FolderWatcherService.shared.ignoreFile(at: url)

                do {
                    try TagLibMetadataWriter.writeTrackMetadata(to: url, track: trackForFile)
                    Logger.info("✅ Successfully wrote metadata to file: \(url.lastPathComponent) - Genre: \(genre)")
                } catch {
                    Logger.error("❌ Failed to write metadata to file \(url.lastPathComponent): \(error.localizedDescription)")
                    Logger.error("Error details: \(error)")
                    // Continue even if file write fails - database is updated
                }
            }

            if shouldDeferFileWrite {
                Logger.info("⏸️ Deferring file metadata write until playback is idle for track: \(title)")
                Task.detached {
                    let playback = PlaybackController.shared
                    // Wait until we're no longer actively playing this track
                    var attempts = 0
                    while attempts < 120 { // ~60 seconds max
                        let isSameTrack = playback.currentTrack?.trackId == trackForFile.trackId
                        let isPlaying = playback.audioEngine.isPlaying()
                        if !isSameTrack || !isPlaying {
                            performFileWrite()
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(500))
                        attempts += 1
                    }
                    // Fallback: write anyway after waiting
                    performFileWrite()
                }
            } else {
                performFileWrite()
            }
            
            // Preserve editableArtwork before reloading track
            // CRITICAL: Preserve artwork BEFORE invalidating cache to ensure we have the new artwork
            let preservedArtwork = editableArtwork
            let wasClearingArtwork = (preservedArtwork == nil && artworkData == nil)
            
            // Capture album and artist IDs before reloading track (they might change)
            let albumIdForCache = fullTrack?.albumId
            let artistIdForCache = fullTrack?.artistId
            
            // Invalidate artwork cache BEFORE reloading track to ensure fresh data is loaded
            // This prevents loading stale artwork from cache
            if let trackId = trackId {
                ArtworkCache.shared.invalidate(trackId: trackId)
                // Also invalidate album and artist artwork if they exist
                if let albumId = albumIdForCache {
                    ArtworkCache.shared.invalidateAlbum(albumId: albumId)
                }
                if let artistId = artistIdForCache {
                    ArtworkCache.shared.invalidateArtist(artistId: artistId)
                }
            }
            
            // Reload track to get updated data
            if let trackId = trackId {
                fullTrack = try? await DatabaseManager.shared.dbQueue.read { db in
                    try Track
                        .filter(Track.Columns.trackId == trackId)
                        .fetchOne(db)
                }
                
                // Reinitialize editable fields with updated values
                if let reloadedTrack = fullTrack {
                    // Set flag to prevent save trigger during reload
                    isInitializingArtwork = true
                    
                    // Update all fields except artwork if we just cleared it
                    editableTitle = reloadedTrack.title
                    editableArtist = reloadedTrack.artist
                    editableAlbum = reloadedTrack.album
                    editableYear = reloadedTrack.year.isEmpty ? "" : reloadedTrack.year
                    editableGenre = reloadedTrack.genre.isEmpty ? "" : reloadedTrack.genre
                    editableComposer = reloadedTrack.composer.isEmpty ? "" : reloadedTrack.composer
                    editableTrackNumber = reloadedTrack.trackNumber.map { String($0) } ?? ""
                    editableDiscNumber = reloadedTrack.discNumber.map { String($0) } ?? ""
                    
                    // Only reload artwork if we weren't clearing it
                    if wasClearingArtwork {
                        // Keep artwork as nil (cleared) - don't reload from database
                        editableArtwork = nil
                        artworkCleared = true
                        trackInfoManager.clearedTrackIds.insert(trackId) // Remember which track was cleared
                    } else {
                        // Reset cleared flag if we're loading new artwork (unless this is the cleared track)
                        // trackId is already unwrapped in the outer if let, so it's Int64 here
                        if trackInfoManager.clearedTrackIds.contains(trackId) {
                            // This is the cleared track - keep it cleared
                            artworkCleared = true
                        } else {
                            // Different track or no cleared track - reset flag
                            artworkCleared = false
                            // Don't remove from clearedTrackIds - we want to remember all cleared tracks
                        }
                        // Restore preserved artwork or load from track
                        // CRITICAL: Always use preservedArtwork if it exists (when replacing artwork)
                        // Don't reload from database as it might have stale data
                        if let preserved = preservedArtwork {
                            // We have preserved artwork (new artwork that was just saved)
                            editableArtwork = preserved
                            Logger.debug("🖼️ Restored preserved artwork after save")
                        } else {
                            // No preserved artwork - this means artwork was cleared
                            // Load from track/album/artist only if not clearing
                            if let artworkData = reloadedTrack.artworkData, let image = NSImage(data: artworkData) {
                                editableArtwork = image
                            } else {
                                editableArtwork = nil
                                // Only load from album/artist if we're not in the middle of clearing and this isn't the cleared track
                                // trackId is already unwrapped, so compare directly
                                if !isClearingArtwork, !trackInfoManager.clearedTrackIds.contains(trackId) {
                                    Task {
                                        if let reloadedTrackId = reloadedTrack.trackId {
                                            await loadArtworkForTrack(trackId: reloadedTrackId)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    hasChanges = false
                    
                    // Reset flag after reload completes
                    Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        isInitializingArtwork = false
                    }
                }
            }
            hasChanges = false

            // Note: Artwork cache was already invalidated above before reloading track
            // No need to invalidate again here

            // Restore playback state if we edited the currently playing track
            if isEditingCurrentPlaybackTrack,
               let savedPosition = savedPlaybackPosition,
               let playbackTrackId = playback.currentTrack?.trackId,
               let editingTrackId = editingPlaybackTrackId,
               playbackTrackId == editingTrackId {
                // Only intervene if playback actually slipped backwards noticeably
                let tolerance: Double = 0.75
                let current = playback.currentTime
                if current + tolerance < savedPosition {
                    playback.seek(to: savedPosition)
                }
                if wasPlayingTrack && !playback.isPlaying {
                    playback.play()
                }
            }

            // Post notifications to refresh all views (we're already on MainActor)
            // Post both notifications: refreshLibraryData for general refresh, libraryDataDidChange for playback panel
            // Use a debounced notification to prevent rapid-fire updates
            Task { @MainActor in
                // Small delay to batch multiple rapid updates
                try? await Task.sleep(for: .milliseconds(100))
                NotificationCenter.default.post(
                    name: .refreshLibraryData,
                    object: nil,
                    userInfo: ["trackId": trackId as Any]
                )
                // Also post libraryDataDidChange so playback panel updates artwork
                NotificationCenter.default.post(
                    name: .libraryDataDidChange,
                    object: nil,
                    userInfo: ["trackId": trackId as Any]
                )
            }
            
            Logger.info("Successfully saved track metadata for: \(title)")
        } catch {
            Logger.error("Failed to save track metadata: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    nonisolated private static func storeAlbumArtwork(albumId: Int64, artworkData: Data, in db: Database) throws {
        // Always update since user is explicitly editing
        try db.execute(
            sql: """
            UPDATE albums 
            SET artwork_data = ?
            WHERE id = ?
            """,
            arguments: [artworkData, albumId]
        )
        Logger.info("Stored artwork for album ID: \(albumId)")
    }
    
    nonisolated private static func storeArtistArtwork(artistId: Int64, artworkData: Data, sourceType: String, in db: Database) throws {
        // Always update since user is explicitly editing
        try db.execute(
            sql: """
            UPDATE artists 
            SET artwork_data = ?, artwork_source_type = ?
            WHERE id = ?
            """,
            arguments: [artworkData, sourceType, artistId]
        )
        Logger.info("Stored artwork for artist ID: \(artistId) from source: \(sourceType)")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatSampleRate(_ rate: Int) -> String {
        if rate >= 1000 {
            let kHz = Double(rate) / 1000.0
            return String(format: "%.1f kHz", kHz)
        }
        return "\(rate) Hz"
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Editable Text Field

// Custom NSTextView that handles text editing without select-all
class CustomTextView: NSTextView {
    var onTextChange: ((String) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var preventSelectAll: Bool = true
    private var initialSelection = false

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result && preventSelectAll && !initialSelection {
            initialSelection = true
            // Move cursor to beginning - no async needed
            self.setSelectedRange(NSRange(location: 0, length: 0))
        }
        return result
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
    }

    override func insertNewline(_ sender: Any?) {
        onCommit?()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignFirstResponder() -> Bool {
        initialSelection = false
        // When losing focus, commit changes
        onCommit?()
        return super.resignFirstResponder()
    }
}

// NSView wrapper for CustomTextView
class CustomTextViewWrapper: NSView {
    let textView: CustomTextView
    let scrollView: NSScrollView
    private let containerView: NSView

    init(font: NSFont, textColor: NSColor, alignment: NSTextAlignment) {
        textView = CustomTextView()
        scrollView = NSScrollView()
        containerView = NSView()

        super.init(frame: .zero)

        // Configure text view - use LEFT alignment to match SwiftUI Text positioning
        textView.font = font
        textView.textColor = textColor
        textView.alignment = .left  // Always use left alignment
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isFieldEditor = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true  // Allow horizontal resizing to fit content
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // CRITICAL: Set these to 0 to prevent any text shifting
        textView.textContainerInset = .zero
        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.widthTracksTextView = false  // Don't track width
            textContainer.maximumNumberOfLines = 1
            textContainer.lineBreakMode = .byClipping
            // Set initial size to allow text to flow
            textContainer.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 100)
        }

        // Configure scroll view - no scrollbars, just clip overflow
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsetsZero

        containerView.addSubview(scrollView)
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        addSubview(containerView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        // Calculate the natural width of the text
        let textWidth: CGFloat
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            textWidth = ceil(usedRect.width)
        } else {
            textWidth = bounds.width
        }

        // If text is shorter than container, center it; otherwise use full width
        if textWidth <= bounds.width {
            let xOffset = (bounds.width - textWidth) / 2
            containerView.frame = CGRect(x: xOffset, y: 0, width: textWidth, height: bounds.height)
            scrollView.frame = CGRect(x: 0, y: 0, width: textWidth, height: bounds.height)
            textView.frame = CGRect(x: 0, y: 0, width: textWidth, height: bounds.height)
        } else {
            // Text is longer - fill container and allow scrolling
            containerView.frame = bounds
            scrollView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            textView.frame = CGRect(x: 0, y: 0, width: textWidth, height: bounds.height)
        }

        // Update text container size to allow text to expand
        textView.textContainer?.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: bounds.height)
    }
}

// SwiftUI wrapper
struct InlineTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let textColor: NSColor
    let isEditable: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CustomTextViewWrapper {
        let wrapper = CustomTextViewWrapper(font: font, textColor: textColor, alignment: .center)
        wrapper.textView.string = text
        wrapper.textView.isEditable = isEditable
        wrapper.textView.onTextChange = { newText in
            text = newText
        }
        wrapper.textView.onCommit = onCommit
        wrapper.textView.onCancel = onCancel
        context.coordinator.wrapper = wrapper

        return wrapper
    }

    func updateNSView(_ nsView: CustomTextViewWrapper, context: Context) {
        let needsTextUpdate = nsView.textView.string != text
        if needsTextUpdate {
            nsView.textView.string = text
        }
        nsView.textView.font = font
        nsView.textView.textColor = textColor

        let wasEditable = nsView.textView.isEditable
        nsView.textView.isEditable = isEditable

        // Trigger layout update if text changed
        if needsTextUpdate {
            nsView.needsLayout = true
            nsView.layout()
        }

        // Only make first responder when transitioning to editable
        if isEditable && !wasEditable {
            context.coordinator.requestFocus()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var wrapper: CustomTextViewWrapper?

        func requestFocus() {
            guard let wrapper = wrapper else { return }
            // Schedule focus request with slight delay to ensure view hierarchy is ready
            Task { @MainActor [weak wrapper] in
                try? await Task.sleep(for: .milliseconds(10))
                wrapper?.window?.makeFirstResponder(wrapper?.textView)
            }
        }
    }
}

// Main editable field component
struct EditableTextField: View {
    @Binding var text: String
    let placeholder: String
    var onSubmit: (() -> Void)?
    var enableScrolling: Bool = false
    var font: Font = .body
    var foregroundColor: Color = .primary

    @State private var isEditing: Bool = false
    @State private var editingText: String = ""
    @State private var originalValue: String = ""

    private var fieldHeight: CGFloat {
        if font == AppFonts.trackTitle {
            return 28
        } else if font == AppFonts.trackArtist {
            return 24
        } else if font == AppFonts.trackAlbum {
            return 20
        }
        return 24
    }

    private var nsFont: NSFont {
        if font == AppFonts.trackTitle {
            return NSFont.systemFont(ofSize: 20, weight: .bold)
        } else if font == AppFonts.trackArtist {
            return NSFont.systemFont(ofSize: 16, weight: .regular)
        } else if font == AppFonts.trackAlbum {
            return NSFont.systemFont(ofSize: 14, weight: .regular)
        }
        return NSFont.systemFont(ofSize: 15, weight: .regular)
    }

    var body: some View {
        ZStack {
            if enableScrolling {
                // Always show InlineTextEditor, control its interactivity
                InlineTextEditor(
                    text: $editingText,
                    font: nsFont,
                    textColor: NSColor(foregroundColor),
                    isEditable: isEditing,
                    onCommit: {
                        commitChanges()
                    },
                    onCancel: {
                        cancelEditing()
                    }
                )
                .frame(height: fieldHeight)
                .opacity(isEditing ? 1 : 0)
                .allowsHitTesting(isEditing)

                // Display mode: Scrolling text overlay
                if !isEditing {
                    ScrollingSingleText(
                        text: text,
                        font: font,
                        foregroundColor: foregroundColor,
                        alignment: .center
                    )
                    .frame(height: fieldHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingText = text
                        originalValue = text
                        isEditing = true
                    }
                    .id(text)  // Force re-render when text changes
                }
            } else {
                Text(text)
                    .font(font)
                    .foregroundColor(foregroundColor)
                    .frame(height: fieldHeight)
            }
        }
        .frame(height: fieldHeight)
        .onAppear {
            originalValue = text
            editingText = text
        }
        .onChange(of: text) { oldValue, newValue in
            // Track changed - always exit edit mode and update to new value
            if newValue != editingText {
                isEditing = false
            }
            originalValue = newValue
            editingText = newValue
        }
    }

    private func commitChanges() {
        text = editingText
        if text != originalValue {
            Logger.debug("Field changed from '\(originalValue)' to '\(text)' - saving")
            onSubmit?()
            originalValue = text
        }
        isEditing = false
    }

    private func cancelEditing() {
        // Revert to original value
        editingText = originalValue
        text = originalValue
        isEditing = false
    }
}

// MARK: - Editable Detail Row

struct EditableDetailRow: View {
    let icon: String
    let label: String
    @Binding var text: String
    let placeholder: String
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var originalValue: String = ""
    @State private var editingText: String = ""

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(AppFonts.captionLarge)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(label)
                .font(AppFonts.trackMetadata)
                .foregroundColor(.secondary)

            Spacer()

            TextField(placeholder, text: $editingText)
                .textFieldStyle(.plain)
                .font(AppFonts.labelLarge)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onAppear {
                    originalValue = text
                    editingText = text
                }
                .onChange(of: text) { _, newValue in
                    // Update when text changes externally (e.g., track navigation)
                    if !isFocused {
                        originalValue = newValue
                        editingText = newValue
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused && editingText != originalValue {
                        // Save on blur if value changed
                        commitChanges()
                    }
                }
                .onSubmit {
                    // Save on Enter key
                    commitChanges()
                }
                .onKeyPress(.escape) {
                    // Revert on ESC key
                    cancelEditing()
                    return .handled
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }

    private func commitChanges() {
        if editingText != originalValue {
            text = editingText
            Logger.debug("Field '\(label)' changed from '\(originalValue)' to '\(editingText)' - saving")
            onSubmit?()
            originalValue = editingText
        }
        isFocused = false
    }

    private func cancelEditing() {
        editingText = originalValue
        text = originalValue
        isFocused = false
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(AppFonts.captionLarge)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(AppFonts.trackMetadata)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(AppFonts.labelLarge)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - Image Picker

struct ImagePicker: NSViewRepresentable {
    @Binding var selectedImage: NSImage?
    @Environment(\.dismiss) var dismiss
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Open panel immediately when view appears
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    if let image = NSImage(contentsOf: url) {
                        selectedImage = image
                    }
                }
                dismiss()
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(AppFonts.bodySmall)
                
                Text(label)
                    .font(AppFonts.buttonMedium)
                
                Spacer()
            }
            .foregroundColor(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? color.opacity(0.1) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Empty State

extension TrackInfoPanel {
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "info.circle")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.2))
            
            Text("No Track Selected")
                .font(AppFonts.heading2)
                .foregroundColor(.primary)
            
            Text("Right-click any track and select 'Get Info' to see detailed information.")
                .font(AppFonts.bodySmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
