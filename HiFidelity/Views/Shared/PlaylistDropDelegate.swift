//
//  PlaylistDropDelegate.swift
//  HiFidelity
//
//  Drop delegate for adding tracks to playlists via drag & drop
//

import SwiftUI
import UniformTypeIdentifiers

struct PlaylistDropDelegate: DropDelegate {
    let playlist: PlaylistItem
    @Binding var draggedPlaylist: PlaylistItem?
    let onDrop: (Int64) async -> Void
    let onDropEntered: () -> Void
    let onDropExited: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedPlaylist = nil }

        guard !isPlaylistDrag(info) else {
            return false
        }

        // Clear drop target highlight
        onDropExited()

        let providers = info.itemProviders(for: [.utf8PlainText, .plainText, .text])
        guard let itemProvider = providers.first else {
            return false
        }

        let typeIdentifier = itemProvider.registeredTypeIdentifiers.first ?? UTType.text.identifier

        itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { data, error in
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
                await onDrop(trackId)
            }
        }

        return true
    }

    func dropEntered(info: DropInfo) {
        // Only highlight for track drops, not playlist drags
        if !isPlaylistDrag(info) {
            onDropEntered()
        }
    }

    func dropExited(info: DropInfo) {
        // Remove highlight when drag exits
        onDropExited()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Don't show proposal for playlist drags
        if isPlaylistDrag(info) {
            return nil
        }
        // Use .move instead of .copy to remove green plus symbol
        // The track won't actually be moved from source, just added to playlist
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        // Only accept track drops, not playlist drags
        if isPlaylistDrag(info) {
            return false
        }
        // Accept text drops (tracks use "track:" prefix)
        return info.hasItemsConforming(to: [.text, .plainText, .utf8PlainText])
    }

    private func isPlaylistDrag(_ info: DropInfo) -> Bool {
        draggedPlaylist != nil
    }
}
