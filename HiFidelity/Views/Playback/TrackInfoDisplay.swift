//
//  TrackInfoDisplay.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Display current playing track information with artwork and favorite button
struct TrackInfoDisplay: View {
    // Don't observe the entire PlaybackController to avoid re-renders on currentTime updates
    private let playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    
    // Only observe the specific properties we need for this view
    @State private var currentTrack: Track?
    @State private var cachedAudioQuality: String = ""
    
    var body: some View {
        HStack(spacing: 8) {
            // Album artwork
            artworkView
            
            // Track details and favorite
            if let track = currentTrack {
                HStack(spacing: 4) {
                    trackDetails(for: track)
                    favoriteButton(for: track)
                    findSimilarButton(for: track)
                }
            } else {
                placeholderDetails
            }
        }
        .frame(minWidth: 220, maxWidth: 320, alignment: .leading)
        .onReceive(playback.$currentTrack) { track in
            currentTrack = track
            updateCachedAudioQuality()
        }
        .onReceive(playback.$currentStreamInfo) { _ in
            // Also update when streamInfo changes directly
            updateCachedAudioQuality()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { notification in
            // Update track data when library changes (e.g., artwork updated)
            if let trackId = notification.userInfo?["trackId"] as? Int64,
               trackId == currentTrack?.trackId {
                // Reload the track from database to get updated artwork
                Task {
                    if let updatedTrack = try? await DatabaseCache.shared.getTrack(by: trackId, forceRefresh: true) {
                        await MainActor.run {
                            // Always update local state for display
                            currentTrack = updatedTrack
                            
                            // Only update playback.currentTrack if the file URL changed (new file)
                            // If only metadata changed (same URL), don't update to avoid audio glitch
                            // This prevents the didSet from triggering applyReplayGain which could cause
                            // stream reload or position reset when writing metadata to playing file
                            let urlChanged = playback.currentTrack?.url != updatedTrack.url
                            if urlChanged || playback.currentTrack?.trackId != trackId {
                                // URL changed (new file) or different track - safe to update
                                playback.currentTrack = updatedTrack
                            } else {
                                // Same file, only metadata changed - update Now Playing info manually
                                // to refresh artwork without triggering audio side effects
                                playback.updateNowPlayingInfo()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            currentTrack = playback.currentTrack
            updateCachedAudioQuality()
        }
    }
    
    // MARK: - Artwork View
    
    @ViewBuilder
    private var artworkView: some View {
        if let track = currentTrack {
            TrackArtworkView(track: track, size: 56, cornerRadius: 6)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .id(track.id)  // Force reload when track instance changes
        } else {
            placeholderArtwork
        }
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(width: 56, height: 56)
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
    
    // MARK: - Track Details
    
    private func trackDetails(for track: Track) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollingTextPair(
                title: track.title,
                subtitle: track.artist,
                titleFont: .system(size: 12, weight: .semibold),
                subtitleFont: .system(size: 12, weight: .medium),
                titleColor: .primary,
                subtitleColor: .secondary.opacity(0.85),
                spacing: 3
            )
            .frame(height: 31)  // 14 + 3 + 14
            .id("\(track.id)-\(track.title)-\(track.artist)")  // Force recreation on track change

            // Audio quality info from BASS - uses cached string for performance
            if !cachedAudioQuality.isEmpty {
                Text(cachedAudioQuality)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }
    
    private var placeholderDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Not Playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.7))
            
            Text("Select a track to play")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
    
    // MARK: - Favorite Button
    
    private func favoriteButton(for track: Track) -> some View {
        FavoriteButton()
    }
    
    // MARK: - Find Similar Button
    
    private func findSimilarButton(for track: Track) -> some View {
        FindSimilarButton(track: track)
    }
    
    private struct FindSimilarButton: View {
        let track: Track
        @ObservedObject var theme = AppTheme.shared
        @State private var isHovered = false
        @State private var isActive = false

        var body: some View {
            Button(action: {
                guard let trackId = track.trackId else { return }
                // Toggle the filter
                NotificationCenter.default.post(
                    name: .findSimilarTracks,
                    object: nil,
                    userInfo: ["trackId": trackId, "toggle": true]
                )
            }) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(isActive ? .white : (isHovered ? theme.currentTheme.primaryColor : .secondary))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isActive ? theme.currentTheme.primaryColor : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                    )
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isActive)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .help(isActive ? "Clear Similar Tracks Filter" : "Find Similar Tracks")
            .onReceive(NotificationCenter.default.publisher(for: .similarTracksFilterChanged)) { notification in
                if let trackId = notification.userInfo?["trackId"] as? Int64,
                   let currentTrackId = track.trackId {
                    isActive = (trackId == currentTrackId)
                } else {
                    isActive = false
                }
            }
        }
    }
    
    private struct FavoriteButton: View {
        @ObservedObject private var playback = PlaybackController.shared
        @ObservedObject var theme = AppTheme.shared
        @State private var isHovered = false
        
        var body: some View {
            Button(action: { playback.toggleFavorite() }) {
                Image(systemName: (playback.currentTrack?.isFavorite ?? false) ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor((playback.currentTrack?.isFavorite ?? false) ? theme.currentTheme.primaryColor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: playback.currentTrack?.isFavorite)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .help((playback.currentTrack?.isFavorite ?? false) ? "Remove from Favorites" : "Add to Favorites")
        }
    }
    
    // MARK: - Audio Quality Formatting
    
    /// Format audio quality string - only called when streamInfo changes
    private func formatAudioQuality(_ info: BASSStreamInfo) -> String {
        let sampleRateKHz = Double(info.frequency) / 1000.0
        let channels = channelDescription(info.channels)
        let bitrateKbps = info.bitrate / 1000
        
        // Format: "24/96kHz 2304kbps Stereo" or "44.1kHz 1411kbps Stereo" for 16-bit
        if info.bitDepth > 0 {
            return "\(bitrateKbps)kbps \(channels)\n\(info.bitDepth)/\(String(format: "%.1f", sampleRateKHz))kHz "
        } else {
            return "\(bitrateKbps)kbps \(channels)\n\(String(format: "%.1f", sampleRateKHz))kHz"
        }
    }
    
    /// Update cached audio quality when streamInfo changes
    private func updateCachedAudioQuality() {
        if let streamInfo = playback.currentStreamInfo {
            cachedAudioQuality = formatAudioQuality(streamInfo)
        } else {
            cachedAudioQuality = ""
        }
    }
    
    private func channelDescription(_ channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 4: return "4.0"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels)ch"
        }
    }
}

// MARK: - Preview

#Preview {
    TrackInfoDisplay()
        .frame(width: 320, height: 80)
        .padding()
}

