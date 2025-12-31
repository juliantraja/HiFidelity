//
//  QueuePanel.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Queue panel showing upcoming tracks
struct QueuePanel: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared

    @State private var hoveredIndex: Int? = nil
    @State private var draggedIndex: Int?
    @AppStorage("queueViewMode") private var isCompactView: Bool = false
    @State private var currentTrackMetadata: Track?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with now playing
            header
            
            Divider()
            
            // Queue list
            if playback.queue.isEmpty && playback.currentTrack == nil {
                emptyState
            } else {
                queueList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 145)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(playback.$currentTrack) { track in
            currentTrackMetadata = track
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { notification in
            guard let trackId = notification.userInfo?["trackId"] as? Int64 else { return }
            Task {
                await refreshTrackMetadata(trackId: trackId)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.system(size: 16, weight: .bold))
                    .frame(height: 28)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Autoplay toggle
                AutoplayToggle()
                
                // Clear queue button
                if !playback.queue.isEmpty {
                    Button {
                        playback.clearQueue()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            // Now Playing section
            if let currentTrack = currentTrackMetadata ?? playback.currentTrack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)

                    currentTrackCard(track: currentTrack)
                }
                .frame(height: 200)
                .padding(.bottom, 0)
            }

            // Next up header with layout toggle
            if !playback.queue.isEmpty {
                HStack {
                    Text("Next up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Layout view toggle buttons
                    HStack(spacing: 8) {
                        // Normal view button
                        Button(action: {
                            isCompactView = false
                        }) {
                            Image(systemName: "rectangle.grid.1x2")
                                .font(.system(size: 14))
                                .foregroundColor(isCompactView ? .secondary.opacity(0.5) : theme.currentTheme.primaryColor)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)

                        // Compact view button
                        Button(action: {
                            isCompactView = true
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 14))
                                .foregroundColor(isCompactView ? theme.currentTheme.primaryColor : .secondary.opacity(0.5))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .padding(.top, 8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func currentTrackCard(track: Track) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                ZStack {
                    // Artwork
                    TrackArtworkView(track: track, size: 56, cornerRadius: 6)

                    // Play/Pause overlay for current track
                    Color.black.opacity(0.5)
                        .cornerRadius(4)

                    Button(action: {
                        if playback.isPlaying {
                            playback.pause()
                        } else {
                            playback.play()
                        }
                    }) {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                }
                .frame(width: 48, height: 48)


                // Info
                ScrollingTextTriple(
                    title: track.title,
                    subtitle: track.artist,
                    tertiary: track.album,
                    titleFont: .system(size: 14, weight: .semibold),
                    subtitleFont: .system(size: 13),
                    tertiaryFont: .system(size: 12),
                    titleColor: theme.currentTheme.primaryColor,
                    subtitleColor: .secondary,
                    tertiaryColor: .secondary.opacity(0.8),
                    spacing: 3
                )
                .frame(height: 50)  // Title + Artist + Album
                .id("\(track.id)-\(track.title)-\(track.artist)")  // Force recreation on track change

                Spacer()
            }

            // Audio controls row (filters and pitch)
            AudioControlsRow()
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .contextMenu {
            if !track.album.isEmpty && track.album != "Unknown Album" {
                Button("Go to Album '\(track.album)'") {
                    TrackContextMenuBuilder.navigateToAlbum(track)
                }
            }

            if !track.artist.isEmpty && track.artist != "Unknown Artist" {
                Button("Go to Artist '\(track.artist)'") {
                    TrackContextMenuBuilder.navigateToArtist(track)
                }
            }

            if (!track.album.isEmpty && track.album != "Unknown Album") || (!track.artist.isEmpty && track.artist != "Unknown Artist") {
                Divider()
            }

            Button("Get Info") {
                TrackContextMenuBuilder.showTrackInfo(track)
            }
        }

    }
    
    // MARK: - Queue List
    
    private var queueList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(playback.queue.enumerated()), id: \.offset) { index, track in
                    queueItem(track: track, index: index)
                        .background(
                            Group {
                                if index == playback.currentQueueIndex {
                                    theme.currentTheme.primaryColor.opacity(0.1)
                                } else if hoveredIndex == index {
                                    Color(nsColor: .controlBackgroundColor)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .onHover { hovering in
                            hoveredIndex = hovering ? index : nil
                        }
                }
            }
        }
    }
    
    private func queueItem(track: Track, index: Int) -> some View {
        Group {
            if isCompactView {
                // Compact view: smaller, more condensed
                HStack(spacing: 10) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.4))
                        .frame(width: 14)

                    // Smaller album artwork
                    TrackArtworkView(track: track, size: 32, cornerRadius: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )

                    // Track info - more compact
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 12, weight: index == playback.currentQueueIndex ? .semibold : .regular))
                            .foregroundColor(index == playback.currentQueueIndex ? theme.currentTheme.primaryColor : .primary)
                            .lineLimit(1)

                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Actions (show on hover)
                    if hoveredIndex == index {
                        QueueRemoveButton {
                            playback.removeFromQueue(at: index)
                        }
                    } else {
                        // Duration
                        Text(track.formattedDuration)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.7))
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            } else {
                // Normal view: current layout
                HStack(spacing: 14) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 18)

                    // Album artwork thumbnail (lazy-loaded)
                    TrackArtworkView(track: track, size: 48, cornerRadius: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )

                    // Track info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 14, weight: index == playback.currentQueueIndex ? .semibold : .regular))
                            .foregroundColor(index == playback.currentQueueIndex ? theme.currentTheme.primaryColor : .primary)
                            .lineLimit(1)

                        Text(track.artist)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Actions (show on hover)
                    if hoveredIndex == index {
                        HStack(spacing: 8) {
                            // Remove from queue
                            QueueRemoveButton {
                                playback.removeFromQueue(at: index)
                            }
                        }
                    } else {
                        // Duration
                        Text(track.formattedDuration)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .background(
            Group {
                if draggedIndex == index {
                    Color(nsColor: .controlBackgroundColor).opacity(0.3)
                } else if hoveredIndex == index {
                    Color(nsColor: .controlBackgroundColor).opacity(0.5)
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            playback.play(track: track)
        }
        .contextMenu {
            Button("Play Now") {
                playback.play(track: track)
            }
            
            if (!track.album.isEmpty && track.album != "Unknown Album") || (!track.artist.isEmpty && track.artist != "Unknown Artist") {
                Divider()
            }
            
            if !track.album.isEmpty && track.album != "Unknown Album" {
                Button("Go to Album '\(track.album)'") {
                    TrackContextMenuBuilder.navigateToAlbum(track)
                }
            }
            
            if !track.artist.isEmpty && track.artist != "Unknown Artist" {
                Button("Go to Artist '\(track.artist)'") {
                    TrackContextMenuBuilder.navigateToArtist(track)
                }
            }
            
            Divider()
            
            Button("Remove from Queue", role: .destructive) {
                playback.removeFromQueue(at: index)
            }
        }

        .onDrag({
            self.draggedIndex = index
            let itemProvider = NSItemProvider(object: String(index) as NSString)
            return itemProvider
        }, preview: {
            // Lightweight drag preview - just the track title
            Text(track.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(radius: 4)
                )
        })
        .onDrop(of: [.text], delegate: QueueDropDelegate(
            targetIndex: index,
            draggedIndex: $draggedIndex,
            playbackController: playback
        ))
    }
    
    // MARK: - Queue Remove Button
    
    private struct QueueRemoveButton: View {
        let action: () -> Void
        @State private var isHovered = false
        
        var body: some View {
            Button(action: action) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isHovered ? .red.opacity(0.8) : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .scaleEffect(isHovered ? 1.1 : 1.0)
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
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.2))
            
            VStack(spacing: 8) {
                Text("No Upcoming Songs")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Queue is empty. Play something to get started.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 145)
    }
}

// MARK: - Drop Delegate for Drag & Drop Reordering

struct QueueDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draggedIndex: Int?
    let playbackController: PlaybackController
    
    func performDrop(info: DropInfo) -> Bool {
        draggedIndex = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let fromIndex = draggedIndex else { return }
        
        let toIndex = targetIndex
        
        // Don't swap with itself
        if fromIndex == toIndex { return }
        
        // Perform the move
        withAnimation(.easeInOut(duration: 0.2)) {
            playbackController.moveQueueItem(from: fromIndex, to: toIndex)
            draggedIndex = toIndex
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Autoplay Toggle

/// Toggle button for autoplay feature
private struct AutoplayToggle: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    @State private var showTooltip = false
    
    var body: some View {
        Button {
            playback.isAutoplayEnabled.toggle()
        } label: {
            HStack(spacing: 6) {
                Text("Autoplay")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(playback.isAutoplayEnabled ? theme.currentTheme.primaryColor : .secondary)
                    
                Image(systemName: playback.isAutoplayEnabled ? "infinity.circle.fill" : "infinity.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(playback.isAutoplayEnabled ? theme.currentTheme.primaryColor : .secondary)
                
                if showTooltip {
                    Text(playback.isAutoplayEnabled ? "On" : "Off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(playback.isAutoplayEnabled ? theme.currentTheme.primaryColor : .secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(playback.isAutoplayEnabled ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help("Autoplay: Automatically add recommended tracks when queue ends")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showTooltip = hovering
            }
        }
    }
}

// MARK: - Audio Controls Row

/// Row containing audio filter buttons and pitch control
private struct AudioControlsRow: View {
    @ObservedObject var filterSettings = AudioFilterSettings.shared
    @ObservedObject var effectsManager = AudioEffectsManager.shared
    @ObservedObject var theme = AppTheme.shared

    var body: some View {
        VStack(spacing: 0) {
            // Top separator line with text labels aligned on the line
            ZStack(alignment: .center) {
                // Full-width line
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                
                // Text labels with background to create gaps, aligned with knobs below
                // Match exact spacing: EQ knobs (50+4+50+4+50) + separator (10) + vertical line (1) + Pitch (50)
                HStack(spacing: 10) {
                    Spacer()
                    
                    // EQ knobs section - align EQ text with MID knob
                    HStack(spacing: 4) {
                        // Space for LOW knob (50px)
                        Spacer()
                            .frame(width: 50)
                        
                        // EQ label - centered over MID knob
                        Text("EQ")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .frame(width: 50)
                        
                        // Space for HI knob (50px)
                        Spacer()
                            .frame(width: 50)
                    }

                    // Vertical separator (matching the one below)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 1)

                    // Pitch label - centered over Pitch knob
                    Text("PITCH")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .frame(width: 50)
                    
                    Spacer()
                }
            }
            
            // Knobs row - aligned horizontally
            HStack(alignment: .center, spacing: 10) {
                Spacer()
                
                // EQ knobs
                HStack(spacing: 4) {
                    // LOW Filter knob (High-Pass)
                    VStack(spacing: 2) {
                        Text("LOW")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .center)

                        FilterKnob(
                            gainDB: $filterSettings.hpfGain,
                            label: "LOW"
                        )
                    }
                    .frame(width: 50)

                    // MID Filter knob (Band-Pass)
                    VStack(spacing: 2) {
                        Text("MID")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .center)

                        FilterKnob(
                            gainDB: $filterSettings.bpfGain,
                            label: "MID"
                        )
                    }
                    .frame(width: 50)

                    // HI Filter knob (Low-Pass)
                    VStack(spacing: 2) {
                        Text("HI")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .center)

                        FilterKnob(
                            gainDB: $filterSettings.lpfGain,
                            label: "HI"
                        )
                    }
                    .frame(width: 50)
                }

                // Vertical separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 28)

                // Pitch control - aligned with EQ knobs (label removed, using top line label)
                // Add invisible spacer above to match EQ knobs' label height exactly
                VStack(spacing: 2) {
                    Text("LOW")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .center)
                        .opacity(0)

                    AnaloguePitchKnob(
                        pitchPercent: $filterSettings.pitchShift,
                        maxRange: filterSettings.pitchRange
                    )
                }
                .frame(width: 50)
                
                Spacer()
            }
            .padding(.vertical, 6)
            
            // Bottom separator line (full width)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
                .padding(.top, 4)
        }
        .padding(.bottom, 0)
        .onChange(of: filterSettings.hpfGain) { _, newValue in
            effectsManager.applyHPFGain(newValue)
        }
        .onChange(of: filterSettings.bpfGain) { _, newValue in
            effectsManager.applyBPFGain(newValue)
        }
        .onChange(of: filterSettings.lpfGain) { _, newValue in
            effectsManager.applyLPFGain(newValue)
        }
        .onChange(of: filterSettings.pitchShift) { _, newValue in
            effectsManager.applyPitchShift(newValue)
        }
    }
}

// MARK: - Metadata Refresh
extension QueuePanel {
    private func refreshTrackMetadata(trackId: Int64) async {
        guard let updated = try? await DatabaseCache.shared.getTrack(by: trackId, forceRefresh: true) else { return }
        
        await MainActor.run {
            // Update display metadata for current track without disturbing playback state
            if playback.currentTrack?.trackId == trackId {
                currentTrackMetadata = updated
            }
            
            // Update queue entries to reflect new metadata/artwork
            var newQueue = playback.queue
            var didChange = false
            for idx in newQueue.indices where newQueue[idx].trackId == trackId {
                newQueue[idx] = updated
                didChange = true
            }
            if didChange {
                playback.queue = newQueue
            }
        }
    }
}

// MARK: - Preview

#Preview {
    QueuePanel()
        .frame(height: 600)
}
