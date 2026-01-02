//
//  QueueExternalDropDelegate.swift
//  HiFidelity
//
//  Drop delegate for adding external tracks to queue via drag & drop
//

import SwiftUI

struct QueueExternalDropDelegate: DropDelegate {
    let playbackController: PlaybackController
    
    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.text]).first else {
            return false
        }
        
        itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, error in
            guard let data = data as? Data,
                  let string = String(data: data, encoding: .utf8),
                  string.hasPrefix("track:") else {
                return
            }
            
            let trackIdString = string.replacingOccurrences(of: "track:", with: "")
            guard let trackId = Int64(trackIdString) else {
                return
            }
            
            Task {
                if let track = try? await DatabaseCache.shared.getTrack(by: trackId) {
                    await MainActor.run {
                        playbackController.addToQueue(track)
                    }
                }
            }
        }
        
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Visual feedback when entering drop zone
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .copy)
    }
}

