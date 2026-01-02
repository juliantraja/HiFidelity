//
//  DBPlaylist.swift
//  HiFidelity
//
//  Database operations for playlists and smart playlists
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Get Tracks for Playlist
    
    func getTracksForPlaylist(playlistId: Int64) async throws -> [Track] {
        try await dbQueue.read { db in
            // Get playlist track entries
            let playlistTracks = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .order(PlaylistTrack.Columns.position.asc)
                .fetchAll(db)
            
            // Get actual tracks
            var tracks: [Track] = []
            for playlistTrack in playlistTracks {
                if let track = try Track
                    .filter(Track.Columns.trackId == playlistTrack.trackId)
                    .fetchOne(db) {
                    tracks.append(track)
                }
            }
            
            return tracks
        }
    }
    
    // MARK: - Smart Playlists
    
    /// Get all favorite tracks
    func getFavoriteTracks() async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.isFavorite == true)
                .order(Track.Columns.dateAdded.desc)
                .fetchAll(db)
        }
    }
    
    /// Get top played tracks
    func getTopPlayedTracks(limit: Int = 25) async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.playCount > 5)
                .order(Track.Columns.playCount.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Get recently played tracks
    func getRecentlyPlayedTracks(limit: Int = 25) async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.lastPlayedDate != nil)
                .order(Track.Columns.lastPlayedDate.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    // MARK: - Update Playlist
    
    func updatePlaylist(_ playlist: Playlist) async throws {
        // Log description value for debugging
        let descriptionPreview = playlist.description?.prefix(200) ?? "nil"
        let descriptionLength = playlist.description?.count ?? 0
        let hasSpaces = playlist.description?.contains(" ") ?? false
        
        Logger.debug("Updating playlist '\(playlist.name)' (ID: \(playlist.id ?? -1))")
        Logger.debug("Description length: \(descriptionLength), contains spaces: \(hasSpaces)")
        
        do {
            try await dbQueue.write { db in
                // Validate description before update
                if let desc = playlist.description {
                    // Check for null bytes which could cause issues
                    if desc.contains("\0") {
                        Logger.warning("Playlist description contains null bytes, removing them: \(playlist.name)")
                    }
                    // Ensure valid UTF-8 encoding
                    guard desc.data(using: .utf8) != nil else {
                        Logger.error("Playlist description contains invalid UTF-8 characters: \(playlist.name)")
                        throw DatabaseError.updateFailed
                    }
                }
                
                try playlist.update(db)
            }
            
            Logger.info("Successfully updated playlist: \(playlist.name)")
        } catch {
            let errorMessage = error.localizedDescription
            let isCorruptionError = errorMessage.contains("error 11") || errorMessage.contains("database disk image is malformed")
            
            Logger.error("Failed to update playlist '\(playlist.name)': \(errorMessage)")
            Logger.error("Description preview: \(descriptionPreview)")
            Logger.error("Description length: \(descriptionLength), contains spaces: \(hasSpaces)")
            
            // If this is a corruption error (SQLite error 11), try to rebuild FTS table and retry
            if isCorruptionError {
                Logger.warning("Detected database corruption error (SQLite error 11). Attempting to repair playlists_fts table...")
                
                do {
                    // Rebuild the playlists_fts table to fix corruption
                    try await rebuildPlaylistsFTS()
                    Logger.info("Successfully rebuilt playlists_fts table, retrying playlist update...")
                    
                    // Retry the update after rebuilding FTS table
                    try await dbQueue.write { db in
                        try playlist.update(db)
                    }
                    
                    Logger.info("Successfully updated playlist after FTS rebuild: \(playlist.name)")
                } catch let repairError {
                    Logger.error("Failed to repair FTS table or retry update: \(repairError.localizedDescription)")
                    throw error // Throw original error
                }
            } else {
                // Not a corruption error, throw as normal
                throw error
            }
        }
        
        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }
    
    /// Rebuild the playlists_fts table to fix corruption
    private func rebuildPlaylistsFTS() async throws {
        try await dbQueue.write { db in
            Logger.info("Rebuilding playlists_fts table to fix corruption...")
            
            // Try to rebuild first (faster, non-destructive)
            do {
                try db.execute(sql: "INSERT INTO playlists_fts(playlists_fts) VALUES('rebuild')")
                Logger.info("Successfully rebuilt playlists_fts table using rebuild command")
                return
            } catch {
                Logger.warning("Rebuild command failed, dropping and recreating playlists_fts table: \(error.localizedDescription)")
                
                // If rebuild fails, drop and recreate the table
                try db.execute(sql: "DROP TABLE IF EXISTS playlists_fts")
                
                // Drop the triggers
                try db.execute(sql: "DROP TRIGGER IF EXISTS playlists_fts_insert")
                try db.execute(sql: "DROP TRIGGER IF EXISTS playlists_fts_delete")
                try db.execute(sql: "DROP TRIGGER IF EXISTS playlists_fts_update")
                
                // Recreate the FTS table
                try db.execute(sql: """
                    CREATE VIRTUAL TABLE IF NOT EXISTS playlists_fts USING fts5(
                        id UNINDEXED,
                        name,
                        description,
                        content='playlists',
                        content_rowid='id',
                        tokenize='unicode61 remove_diacritics 2'
                    )
                """)
                
                // Recreate the triggers
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS playlists_fts_insert AFTER INSERT ON playlists BEGIN
                        INSERT INTO playlists_fts(rowid, id, name, description)
                        VALUES (new.id, new.id, new.name, COALESCE(new.description, ''));
                    END;
                """)
                
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS playlists_fts_delete AFTER DELETE ON playlists BEGIN
                        DELETE FROM playlists_fts WHERE rowid = old.id;
                    END;
                """)
                
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS playlists_fts_update AFTER UPDATE ON playlists BEGIN
                        DELETE FROM playlists_fts WHERE rowid = old.id;
                        INSERT INTO playlists_fts(rowid, id, name, description)
                        VALUES (new.id, new.id, new.name, COALESCE(new.description, ''));
                    END;
                """)
                
                // Rebuild from existing data
                try db.execute(sql: "INSERT INTO playlists_fts(playlists_fts) VALUES('rebuild')")
                
                Logger.info("Successfully recreated and rebuilt playlists_fts table")
            }
        }
    }

    // MARK: - Create Playlist
    
    func createPlaylist(_ playlist: Playlist) async throws -> Playlist {
        let result = try await dbQueue.write { db in
            var mutable = playlist
            
            // Place new playlist at the end of current custom order
            let maxSortOrder = try Playlist
                .select(max(Playlist.Columns.sortOrder))
                .fetchOne(db) ?? -1
            mutable.sortOrder = maxSortOrder + 1
            
            try mutable.insert(db)
            return mutable
        }
        
        Logger.info("Created playlist: \(result.name) with ID: \(result.id ?? -1)")
        
        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
        
        return result
    }
    
    // MARK: - Delete Playlist
    
    func deletePlaylist(_ playlist: PlaylistItem) async throws {
        guard case .user(let playlistModel) = playlist.type else { return }
        
        let playlistId = playlistModel.id
        
        try await dbQueue.write { db in
            // Delete playlist tracks first (cascade)
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .deleteAll(db)
            
            // Delete playlist
            try Playlist
                .filter(Playlist.Columns.id == playlistId)
                .deleteAll(db)
        }
        
        Logger.info("Deleted playlist: \(playlist.name)")
        
        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }
    
    // MARK: - Add Track to Playlist

    func addTrackToPlaylist(trackId: Int64, playlistId: Int64) async throws {
        try await dbQueue.write { db in
            // Check if track already exists in playlist
            let existingCount = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .filter(PlaylistTrack.Columns.trackId == trackId)
                .fetchCount(db)

            if existingCount > 0 {
                Logger.info("Track \(trackId) already exists in playlist \(playlistId), skipping")
                throw DatabaseError.duplicateTrackInPlaylist
            }

            // Get current max position
            let maxPosition = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .select(max(PlaylistTrack.Columns.position))
                .fetchOne(db) ?? -1

            // Create playlist track entry
            var playlistTrack = PlaylistTrack(
                playlistId: playlistId,
                trackId: trackId,
                position: maxPosition + 1,
                dateAdded: Date()
            )

            try playlistTrack.insert(db)

            // Update playlist track count and duration
            if var playlist = try Playlist.fetchOne(db, id: playlistId),
               let track = try Track
                    .filter(Track.Columns.trackId == trackId)
                    .fetchOne(db) {
                playlist.trackCount += 1
                playlist.totalDuration += track.duration
                playlist.modifiedDate = Date()
                try playlist.update(db)
            }
        }

        Logger.info("Added track \(trackId) to playlist \(playlistId)")

        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }

    // MARK: - Reorder Playlists

    func reorderPlaylists(sourceId: Int64, targetId: Int64) async throws {
        try await dbQueue.write { db in
            // Get all playlists ordered by sortOrder
            var playlists = try Playlist
                .order(Playlist.Columns.sortOrder)
                .fetchAll(db)

            // Find source and target
            guard let sourceIndex = playlists.firstIndex(where: { $0.id == sourceId }),
                  let targetIndex = playlists.firstIndex(where: { $0.id == targetId }) else {
                return
            }

            // Remove source
            let source = playlists.remove(at: sourceIndex)

            // Insert relative to target:
            // - If moving downwards, insert after target to allow dropping to bottom
            // - If moving upwards, insert before target
            let insertionIndex: Int
            if sourceIndex < targetIndex {
                insertionIndex = min(targetIndex, playlists.count)
            } else {
                insertionIndex = targetIndex
            }
            playlists.insert(source, at: insertionIndex)

            // Update all sortOrders
            for (index, var playlist) in playlists.enumerated() {
                playlist.sortOrder = index
                try playlist.update(db)
            }
        }

        Logger.info("Reordered playlist \(sourceId) to position of \(targetId)")

        // Post notification
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }

    // MARK: - Remove Track from Playlist

    func removeTrackFromPlaylist(trackId: Int64, playlistId: Int64) async throws {
        try await dbQueue.write { db in
            // Delete playlist track entry
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .filter(PlaylistTrack.Columns.trackId == trackId)
                .deleteAll(db)
            
            // Update playlist track count and duration
            
            if var playlist = try Playlist.fetchOne(db, id: playlistId),
               let track = try Track
                .filter(Track.Columns.trackId == trackId)
                .fetchOne(db) {
                playlist.trackCount = max(0, playlist.trackCount - 1)
                playlist.totalDuration = max(0, playlist.totalDuration - (track.duration))
                playlist.modifiedDate = Date()
                try playlist.update(db)
            }
            
            // Reorder positions
            let playlistTracks = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .order(PlaylistTrack.Columns.position.asc)
                .fetchAll(db)
            
            for (index, var pt) in playlistTracks.enumerated() {
                pt.position = index
                try pt.update(db)
            }
        }
        
        Logger.info("Removed track \(trackId) from playlist \(playlistId)")
        
        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }
    
    // MARK: - M3U Import/Export
    
    /// Import playlist from M3U file
    /// - Parameter m3uURL: URL to the M3U file
    /// - Returns: Created playlist with imported tracks
    func importPlaylistFromM3U(m3uURL: URL) async throws -> (playlist: Playlist, foundCount: Int, skippedCount: Int) {
        // Parse M3U file
        let (baseName, trackPaths) = try M3UPlaylistHandler.importM3U(from: m3uURL)
        
        // Create playlist with unique name
        let playlistName = try await getUniquePlaylistName(baseName: baseName)
        let playlist = Playlist(name: playlistName, description: "Imported from \(m3uURL.lastPathComponent)")
        
        // Find matching tracks in database
        let (tracks, foundCount, skippedCount) = try await dbQueue.read { db -> ([Track], Int, Int) in
            var matchedTracks: [Track] = []
            var found = 0
            var skipped = 0
            
            for trackPath in trackPaths {
                // Try to find track by exact path match
                if let track = try Track
                    .filter(Track.Columns.path == trackPath.path)
                    .fetchOne(db) {
                    matchedTracks.append(track)
                    found += 1
                } else {
                    // Try to find by filename if exact path doesn't match
                    let filename = trackPath.lastPathComponent
                    if let track = try Track
                        .filter(Track.Columns.filename == filename)
                        .fetchOne(db) {
                        matchedTracks.append(track)
                        found += 1
                        Logger.debug("M3U Import: Matched by filename - \(filename)")
                    } else {
                        skipped += 1
                        Logger.warning("M3U Import: Track not in library - \(trackPath.path)")
                    }
                }
            }
            
            return (matchedTracks, found, skipped)
        }
        
        // Create playlist with found tracks
        let createdPlaylist = try await dbQueue.write { db in
            // Insert playlist
            var mutablePlaylist = playlist
            try mutablePlaylist.insert(db)
            
            guard let playlistId = mutablePlaylist.id else {
                throw DatabaseError.updateFailed
            }
            
            // Add tracks to playlist
            for (index, track) in tracks.enumerated() {
                guard let trackId = track.trackId else { continue }
                
                var playlistTrack = PlaylistTrack(
                    playlistId: playlistId,
                    trackId: trackId,
                    position: index,
                    dateAdded: Date()
                )
                
                try playlistTrack.insert(db)
            }
            
            // Update playlist stats
            mutablePlaylist.trackCount = tracks.count
            mutablePlaylist.totalDuration = tracks.reduce(0) { $0 + $1.duration }
            try mutablePlaylist.update(db)
            
            return mutablePlaylist
        }
        
        Logger.info("M3U Import: Created playlist '\(playlistName)' with \(foundCount) tracks (\(skippedCount) skipped)")
        
        // Post notification
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
        
        return (playlist: createdPlaylist, foundCount: foundCount, skippedCount: skippedCount)
    }
    
    /// Import multiple playlists from M3U files
    /// - Parameter m3uURLs: Array of URLs to M3U files (max 10)
    /// - Returns: Array of import results
    func importMultiplePlaylistsFromM3U(m3uURLs: [URL]) async throws -> [(playlist: Playlist, foundCount: Int, skippedCount: Int)] {
        // Limit to 10 files
        let limitedURLs = Array(m3uURLs.prefix(25))
        
        var results: [(playlist: Playlist, foundCount: Int, skippedCount: Int)] = []
        
        for url in limitedURLs {
            do {
                let result = try await importPlaylistFromM3U(m3uURL: url)
                results.append(result)
            } catch {
                Logger.error("Failed to import M3U from \(url.lastPathComponent): \(error)")
                // Continue with next file even if one fails
            }
        }
        
        return results
    }
    
    // MARK: - Folder Import
    
    /// Import playlist from a folder
    /// - Parameter folderURL: URL to the folder
    /// - Returns: Created playlist with imported tracks
    func importPlaylistFromFolder(folderURL: URL) async throws -> (playlist: Playlist, foundCount: Int, skippedCount: Int) {
        // Get all audio files from folder (first layer only)
        let audioFiles = try getAllAudioFiles(in: folderURL)
        
        guard !audioFiles.isEmpty else {
            throw DatabaseError.scanFailed("No audio files found in folder")
        }
        
        // Create playlist with folder name - check for duplicates
        let baseName = folderURL.lastPathComponent
        let playlistName = try await getUniquePlaylistName(baseName: baseName)
        let playlist = Playlist(name: playlistName, description: "Imported from folder: \(folderURL.path)")
        
        // Find matching tracks in database
        let (tracks, foundCount, skippedCount) = try await dbQueue.read { db -> ([Track], Int, Int) in
            var matchedTracks: [Track] = []
            var found = 0
            var skipped = 0
            
            for audioFile in audioFiles {
                // Try to find track by exact path match
                if let track = try Track
                    .filter(Track.Columns.path == audioFile.path)
                    .fetchOne(db) {
                    matchedTracks.append(track)
                    found += 1
                } else {
                    // Try to find by filename if exact path doesn't match
                    let filename = audioFile.lastPathComponent
                    if let track = try Track
                        .filter(Track.Columns.filename == filename)
                        .fetchOne(db) {
                        matchedTracks.append(track)
                        found += 1
                        Logger.debug("Folder Import: Matched by filename - \(filename)")
                    } else {
                        skipped += 1
                        Logger.warning("Folder Import: Track not in library - \(audioFile.path)")
                    }
                }
            }
            
            return (matchedTracks, found, skipped)
        }
        
        // Create playlist with found tracks
        let createdPlaylist = try await dbQueue.write { db in
            // Insert playlist
            var mutablePlaylist = playlist
            try mutablePlaylist.insert(db)
            
            guard let playlistId = mutablePlaylist.id else {
                throw DatabaseError.updateFailed
            }
            
            // Add tracks to playlist
            for (index, track) in tracks.enumerated() {
                guard let trackId = track.trackId else { continue }
                
                var playlistTrack = PlaylistTrack(
                    playlistId: playlistId,
                    trackId: trackId,
                    position: index,
                    dateAdded: Date()
                )
                
                try playlistTrack.insert(db)
            }
            
            // Update playlist stats
            mutablePlaylist.trackCount = tracks.count
            mutablePlaylist.totalDuration = tracks.reduce(0) { $0 + $1.duration }
            try mutablePlaylist.update(db)
            
            return mutablePlaylist
        }
        
        Logger.info("Folder Import: Created playlist '\(playlistName)' with \(foundCount) tracks (\(skippedCount) skipped)")
        
        // Post notification
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
        
        return (playlist: createdPlaylist, foundCount: foundCount, skippedCount: skippedCount)
    }
    
    /// Import multiple playlists from folders
    /// - Parameter folderURLs: Array of folder URLs (max 10)
    /// - Returns: Array of import results
    func importMultiplePlaylistsFromFolders(folderURLs: [URL]) async throws -> [(playlist: Playlist, foundCount: Int, skippedCount: Int)] {
        // Limit to 10 folders
        let limitedURLs = Array(folderURLs.prefix(25))
        
        var results: [(playlist: Playlist, foundCount: Int, skippedCount: Int)] = []
        
        for url in limitedURLs {
            do {
                let result = try await importPlaylistFromFolder(folderURL: url)
                results.append(result)
            } catch {
                Logger.error("Failed to import folder \(url.lastPathComponent): \(error)")
                // Continue with next folder even if one fails
            }
        }
        
        return results
    }
    
    /// Get all audio files in a folder (first layer only, no subdirectories)
    private func getAllAudioFiles(in folderURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        
        // Get contents of directory (first level only)
        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        
        // Filter for audio files only
        let audioFiles = contents.filter { url in
            // Check if it's a regular file
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile else {
                return false
            }
            
            // IMPORTANT: Skip macOS metadata files (._*)
            // These are AppleDouble files created on non-Mac filesystems
            let filename = url.lastPathComponent
            if filename.hasPrefix("._") {
                return false
            }
            
            // Check if it's an audio file
            let fileExtension = url.pathExtension.lowercased()
            return AudioFormat.isSupported(fileExtension)
        }
        
        // Sort files by name for consistent ordering
        return audioFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    /// Get a unique playlist name by checking for duplicates
    private func getUniquePlaylistName(baseName: String) async throws -> String {
        let existingNames = try await dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM playlists")
        }
        
        // If base name is unique, use it
        if !existingNames.contains(baseName) {
            return baseName
        }
        
        // Otherwise, append a number
        var counter = 2
        var uniqueName = "\(baseName) (\(counter))"
        
        while existingNames.contains(uniqueName) {
            counter += 1
            uniqueName = "\(baseName) (\(counter))"
        }
        
        return uniqueName
    }
    
    /// Export playlist to M3U file
    /// - Parameters:
    ///   - playlistId: ID of the playlist to export
    ///   - saveURL: URL where to save the M3U file
    ///   - useRelativePaths: Whether to use relative paths (default: false)
    func exportPlaylistToM3U(playlistId: Int64, saveURL: URL, useRelativePaths: Bool = false) async throws {
        // Get playlist and tracks
        let (playlist, tracks) = try await dbQueue.read { db in
            guard let playlist = try Playlist.fetchOne(db, id: playlistId) else {
                throw DatabaseError.recordNotFound(table: "playlists", id: playlistId)
            }
            
            // Get playlist tracks in order
            let playlistTracks = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .order(PlaylistTrack.Columns.position.asc)
                .fetchAll(db)
            
            var tracks: [Track] = []
            for playlistTrack in playlistTracks {
                if let track = try Track
                    .filter(Track.Columns.trackId == playlistTrack.trackId)
                    .fetchOne(db) {
                    tracks.append(track)
                }
            }
            
            return (playlist, tracks)
        }
        
        // Export to M3U
        try M3UPlaylistHandler.exportM3U(
            tracks: tracks,
            playlistName: playlist.name,
            to: saveURL,
            useRelativePaths: useRelativePaths
        )
        
        Logger.info("M3U Export: Successfully exported '\(playlist.name)' to \(saveURL.lastPathComponent)")
    }
}
