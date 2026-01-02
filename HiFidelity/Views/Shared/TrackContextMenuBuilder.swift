//
//  TrackContextMenuBuilder.swift
//  HiFidelity
//
//  Shared logic for track context menu actions
//

import Foundation
import AppKit

/// Centralized track context menu logic
/// Used by both SwiftUI context menus and NSMenu implementations
class TrackContextMenuBuilder {
    
    // MARK: - Playback Actions
    
    static func playTrack(_ track: Track) {
        PlaybackController.shared.playTracks([track], startingAt: 0)
    }
    
    static func playNext(_ track: Track) {
        PlaybackController.shared.playNext(track)
    }
    
    static func addToQueue(_ track: Track) {
        PlaybackController.shared.addToQueue(track)
    }
    
    // MARK: - Playlist Actions
    
    static func showCreatePlaylist(with track: Track) {
        guard let coordinator = AppCoordinator.shared else { return }
        coordinator.showCreatePlaylist(with: track)
    }
    
    static func addToPlaylist(_ track: Track, playlist: Playlist) {
        guard let playlistId = playlist.id,
              let trackId = track.trackId else { return }
        
        Task {
            do {
                try await DatabaseManager.shared.addTrackToPlaylist(trackId: trackId, playlistId: playlistId)
                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "'\(track.title)' was added to '\(playlist.name)'")
                }
            } catch DatabaseError.duplicateTrackInPlaylist {
                await MainActor.run {
                    NotificationManager.shared.addMessage(.warning, "'\(track.title)' is already in '\(playlist.name)'")
                }
            } catch {
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to add track to playlist")
                }
            }
        }
    }
    
    static func removeFromPlaylist(_ track: Track, playlistItem: PlaylistItem, onRemove: @escaping () -> Void) {
        guard case .user(let playlist) = playlistItem.type,
              let playlistId = playlist.id,
              let trackId = track.trackId else { return }
        
        Task {
            do {
                try await DatabaseManager.shared.removeTrackFromPlaylist(trackId: trackId, playlistId: playlistId)
                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "'\(track.title)' was removed from '\(playlistItem.name)'")
                    onRemove()
                }
            } catch {
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to remove track from playlist")
                }
            }
        }
    }
    
    // MARK: - File Actions
    
    static func showInFinder(_ track: Track) {
        NSWorkspace.shared.activateFileViewerSelecting([track.url])
    }
    
    static func showTrackInfo(_ track: Track, allTracks: [Track] = [], currentIndex: Int = 0) {
        // Post notification to show track info with context
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowTrackInfo"),
            object: track,
            userInfo: [
                "allTracks": allTracks,
                "currentIndex": currentIndex
            ]
        )
    }

    static func reAnalyzeTrack(_ track: Track) {
        guard let trackId = track.trackId else { return }

        Task {
            do {
                NotificationManager.shared.addMessage(.info, "Re-analyzing '\(track.title)'...")

                // Step 1: Re-extract metadata from file (like fresh import)
                let metadata = TagLibMetadataManager.extractMetadata(from: track.url)
                var updatedTrack = track
                TagLibMetadataManager.applyMetadata(to: &updatedTrack, from: metadata, at: track.url)

                // Step 2: Analyze audio features with metadata BPM
                let metadataBPM = metadata.bpm.map { Double($0) }
                
                // Calculate dynamic timeout based on track duration (same as regular analysis)
                let trackDuration = track.duration
                let timeoutSeconds: TimeInterval
                if trackDuration > 0 {
                    // Timeout: 90 seconds base + 30% of track duration, capped at 5 minutes
                    timeoutSeconds = min(90.0 + (trackDuration * 0.3), 300.0)
                } else {
                    // Default to 3 minutes if duration is 0
                    timeoutSeconds = 180.0
                }
                
                let result = try await withTimeout(seconds: timeoutSeconds) {
                    try await AudioFeatureAnalyzer.shared.analyzeAudioFile(at: track.url, metadataBPM: metadataBPM) { progress in
                        Logger.debug("Re-analysis progress: \(Int(progress * 100))%")
                    }
                }

                // Step 3: Create SongFeatures object with fresh analysis
                var features = SongFeatures(
                    trackId: trackId,
                    tempo: result.bpm,
                    key: result.key,
                    mode: result.mode,
                    extractedAt: Date(),
                    extractorVersion: "1.0",
                    confidence: result.confidence,
                    needsUpdate: false
                )
                features.deriveCamelotKey()

                // Step 3.5: Regenerate waveform
                do {
                    let waveform = try await WaveformGenerator.generateWaveform(from: track.url, targetCount: 400)
                    // Use trackId (database ID) instead of id (ephemeral UUID)
                    WaveformCache.shared.cacheWaveform(trackId: String(trackId), samples: waveform)
                    Logger.debug("Waveform regenerated for '\(track.title)'")
                } catch {
                    Logger.error("Failed to regenerate waveform for '\(track.title)': \(error)")
                    // Don't fail the entire re-analyze if waveform fails
                }

                // Step 4: Update everything in database (metadata + audio features)
                // Capture immutable copies for the closure
                let trackToUpdate = updatedTrack
                let featuresToSave = features

                try await DatabaseManager.shared.dbQueue.write { db in
                    // Update track metadata
                    try trackToUpdate.update(db)

                    // Update song features
                    var mutableFeatures = featuresToSave
                    try mutableFeatures.insert(db, onConflict: .replace)
                }

                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "Re-analysis complete - BPM: \(result.bpm.map { String(format: "%.0f", $0) } ?? "N/A")")
                    // Notify UI to refresh
                    NotificationCenter.default.post(name: .refreshLibraryData, object: nil)
                    NotificationCenter.default.post(
                        name: .songFeaturesDidUpdate,
                        object: trackId,
                        userInfo: ["trackId": trackId]
                    )
                }
            } catch {
                Logger.error("Failed to re-analyze track: \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to re-analyze track")
                }
            }
        }
    }

    // Helper function for timeout
    private static func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AudioAnalysisError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    enum AudioAnalysisError: Error {
        case timeout
    }
    
    // MARK: - Favorite Actions
    
    static func toggleFavorite(_ track: Track) {
        var updatedTrack = track
        updatedTrack.isFavorite.toggle()
        
        // Capture values before Task
        let finalTrack = updatedTrack
        let trackId = updatedTrack.trackId
        
        Task {
            do {
                try await DatabaseManager.shared.updateTrackFavoriteStatus(finalTrack)
                // Post notification to refresh UI
                await MainActor.run {
                    if let trackId = trackId {
                        NotificationCenter.default.post(
                            name: .libraryDataDidChange,
                            object: nil,
                            userInfo: ["trackId": trackId]
                        )
                    }
                }
            } catch {
                Logger.error("Failed to update favorite: \(error)")
            }
        }
    }
    
    // MARK: - Playlists Helper
    
    static func getUserPlaylists() -> [Playlist] {
        DatabaseCache.shared.allPlaylists.filter { !$0.isSmart }
    }
    
    // MARK: - R128 Scanning Actions
    
    static func scanTrackR128(_ track: Track) {
        R128LoudnessScanner.shared.scanTracks([track])
        NotificationManager.shared.addMessage(.info, "Scanning '\(track.title)' for R128 loudness...")
    }
    
    static func scanAlbumR128(_ track: Track) {
        R128LoudnessScanner.shared.scanAlbum(album: track.album, artist: track.artist)
        NotificationManager.shared.addMessage(.info, "Scanning album '\(track.album)' for R128 loudness...")
    }
    
    static func scanArtistR128(_ track: Track) {
        R128LoudnessScanner.shared.scanArtist(artist: track.artist)
        NotificationManager.shared.addMessage(.info, "Scanning tracks by '\(track.artist)' for R128 loudness...")
    }
    
    // MARK: - Navigation Actions
    
    static func navigateToAlbum(_ track: Track) {
        Task {
            do {
                // Fetch the album from the database
                if let albumId = try await DatabaseManager.shared.getAlbumId(title: track.album, artist: track.artist) {
                    let album = try await DatabaseManager.shared.getAlbum(albumId: albumId)
                    
                    await MainActor.run {
                        // Navigate to the album
                        NotificationCenter.default.post(
                            name: .navigateToEntity,
                            object: EntityType.album(album)
                        )
                    }
                } else {
                    await MainActor.run {
                        NotificationManager.shared.addMessage(.warning, "Album '\(track.album)' not found")
                    }
                }
            } catch {
                Logger.error("Failed to navigate to album: \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to navigate to album")
                }
            }
        }
    }
    
    static func navigateToArtist(_ track: Track) {
        Task {
            do {
                // Fetch the artist from the database
                if let artistId = try await DatabaseManager.shared.getArtistId(name: track.artist) {
                    let artist = try await DatabaseManager.shared.getArtist(artistId: artistId)
                    
                    await MainActor.run {
                        // Navigate to the artist
                        NotificationCenter.default.post(
                            name: .navigateToEntity,
                            object: EntityType.artist(artist)
                        )
                    }
                } else {
                    await MainActor.run {
                        NotificationManager.shared.addMessage(.warning, "Artist '\(track.artist)' not found")
                    }
                }
            } catch {
                Logger.error("Failed to navigate to artist: \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to navigate to artist")
                }
            }
        }
    }
}
