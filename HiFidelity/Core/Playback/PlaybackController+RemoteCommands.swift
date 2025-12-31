//
//  PlaybackController+RemoteCommands.swift
//  HiFidelity
//
//  Remote command center setup for media controls
//

import Foundation
import MediaPlayer

extension PlaybackController {
    // MARK: - Remote Command Center
    
    func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        // Next track
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        
        // Previous track
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }

        // Change playback position
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
        
        // Like/Dislike (favorite)
        commandCenter.likeCommand.isEnabled = true
        commandCenter.likeCommand.addTarget { [weak self] _ in
            guard let self = self, let track = self.currentTrack, !track.isFavorite else { return .commandFailed }
            self.toggleFavorite()
            return .success
        }
        
        commandCenter.dislikeCommand.isEnabled = true
        commandCenter.dislikeCommand.addTarget { [weak self] _ in
            guard let self = self, let track = self.currentTrack, track.isFavorite else { return .commandFailed }
            self.toggleFavorite()
            return .success
        }
        
        Logger.info("Remote command center setup complete")
    }
}

