//
//  DBTrack.swift
//  HiFidelity
//
//  Created by Varun Rathod on 30/10/25.
//

import Foundation
import GRDB

// MARK: - Local Enums

enum TrackProcessResult {
    case new(Track, TrackMetadata)
    case update(Track, TrackMetadata)
    case skipped
}

// This extension contains methods for track processing as found from folders added.
extension DatabaseManager {
    /// Process a new batch of music files with normalized data support
    /// - Parameters:
    ///   - batch: Array of (url, folderId) tuples to process
    ///   - existingTracks: Dictionary of existing tracks indexed by URL for update checking
    /// - Note: Checks for duplicates, extracts metadata concurrently, updates or inserts in single transaction
    func processBatch(_ batch: [(url: URL, folderId: Int64)], existingTracks: [URL: Track] = [:]) async throws {
        guard !batch.isEmpty else { return }
       
        let batchStartTime = Date()
        Logger.debug("⏱️ [IMPORT] [BATCH] Starting batch processing: \(batch.count) tracks")

        let metadataResults = try await withThrowingTaskGroup(
            of: (URL, TrackProcessResult).self
        ) { group in
            for (fileURL, folderId) in batch {
                group.addTask {
                    do {
                        let trackStartTime = Date()
                        Logger.debug("⏱️ [IMPORT] Starting processing: \(fileURL.lastPathComponent)")
                        
                        // Check if track already exists
                        if let existingTrack = existingTracks[fileURL] {
                            // Check if file was modified
                            let attributes = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                            if let fileModDate = attributes.contentModificationDate,
                               let dbModDate = existingTrack.dateModified {
                                
                                // File was modified, update metadata
                                if fileModDate > dbModDate {
                                    var updatedTrack = existingTrack
                                    let metadataStartTime = Date()
                                    Logger.debug("⏱️ [IMPORT] [METADATA] Starting extraction: \(fileURL.lastPathComponent)")
                                    let metadata = TagLibMetadataManager.extractMetadata(from: fileURL)
                                    let metadataDuration = Date().timeIntervalSince(metadataStartTime)
                                    Logger.debug("⏱️ [IMPORT] [METADATA] Completed in \(String(format: "%.3f", metadataDuration))s: \(fileURL.lastPathComponent)")
                                    
                                    TagLibMetadataManager.applyMetadata(to: &updatedTrack, from: metadata, at: fileURL)
                                    
                                    let totalDuration = Date().timeIntervalSince(trackStartTime)
                                    Logger.info("⏱️ [IMPORT] File modified, updating metadata: \(fileURL.lastPathComponent) (total: \(String(format: "%.3f", totalDuration))s)")
                                    return (fileURL, TrackProcessResult.update(updatedTrack, metadata))
                                } else {
                                    // File unchanged, skip
                                    return (fileURL, TrackProcessResult.skipped)
                                }
                            }
                        }
                        
                        // New track - extract metadata and prepare for insertion
                        var track = Track(url: fileURL)
                        let metadataStartTime = Date()
                        Logger.debug("⏱️ [IMPORT] [METADATA] Starting extraction: \(fileURL.lastPathComponent)")
                        let metadata = TagLibMetadataManager.extractMetadata(from: fileURL)
                        let metadataDuration = Date().timeIntervalSince(metadataStartTime)
                        Logger.debug("⏱️ [IMPORT] [METADATA] Completed in \(String(format: "%.3f", metadataDuration))s: \(fileURL.lastPathComponent)")
                        
                        track.folderId = folderId
                        TagLibMetadataManager.applyMetadata(to: &track, from: metadata, at: fileURL)

                        let totalDuration = Date().timeIntervalSince(trackStartTime)
                        Logger.debug("⏱️ [IMPORT] Metadata processing complete: \(fileURL.lastPathComponent) (total: \(String(format: "%.3f", totalDuration))s)")
                        
                        return (fileURL, TrackProcessResult.new(track, metadata))
                        
                    } catch {
                        Logger.error("Failed to process track \(fileURL.lastPathComponent): \(error)")
                        return (fileURL, TrackProcessResult.skipped)
                    }
                }
            }
            
            // Collect all results
            var results: [(URL, TrackProcessResult)] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
        
        // Step 4: Separate new, update, and skipped tracks
        var newTracks: [(Track, TrackMetadata)] = []
        var updatedTracks: [(Track, TrackMetadata)] = []
        var skippedCount = 0
        
        for (_, result) in metadataResults {
            switch result {
            case .new(let track, let metadata):
                newTracks.append((track, metadata))
            case .update(let track, let metadata):
                updatedTracks.append((track, metadata))
            case .skipped:
                skippedCount += 1
            }
        }
        
        // Step 5: Insert and update all in single transaction for atomicity
        guard !newTracks.isEmpty || !updatedTracks.isEmpty else {
            Logger.info("Batch complete: \(skippedCount) unchanged")
            return
        }
        
        let dbStartTime = Date()
        Logger.debug("⏱️ [IMPORT] [DATABASE] Starting batch write transaction")
        let (insertedCount, updatedCount, insertedTrackIds) = try await dbQueue.write { [newTracks, updatedTracks] db -> (Int, Int, [Int64]) in
            var inserted = 0
            var updated = 0
            var trackIds: [Int64] = []
            
            // Insert new tracks
            for (track, metadata) in newTracks {
                do {
                    let trackDbStartTime = Date()
                    Logger.debug("⏱️ [IMPORT] [DATABASE] Processing new track: \(track.title)")
                    let trackId = try self.processNewTrack(track, metadata: metadata, in: db)
                    if let id = trackId {
                        trackIds.append(id)
                    }
                    let trackDbDuration = Date().timeIntervalSince(trackDbStartTime)
                    Logger.debug("⏱️ [IMPORT] [DATABASE] Track inserted in \(String(format: "%.3f", trackDbDuration))s: \(track.title)")
                    inserted += 1
                } catch {
                    Logger.error("Failed to insert track '\(track.title)': \(error)")
                }
            }
            
            // Update existing tracks
            for (track, metadata) in updatedTracks {
                do {
                    let trackDbStartTime = Date()
                    Logger.debug("⏱️ [IMPORT] [DATABASE] Processing updated track: \(track.title)")
                    try self.processUpdatedTrack(track, metadata: metadata, in: db)
                    let trackDbDuration = Date().timeIntervalSince(trackDbStartTime)
                    Logger.debug("⏱️ [IMPORT] [DATABASE] Track updated in \(String(format: "%.3f", trackDbDuration))s: \(track.title)")
                    updated += 1
                } catch {
                    Logger.error("Failed to update track '\(track.title)': \(error)")
                }
            }
            
            return (inserted, updated, trackIds)
        }
        let dbDuration = Date().timeIntervalSince(dbStartTime)
        Logger.debug("⏱️ [IMPORT] [DATABASE] Batch write transaction completed in \(String(format: "%.3f", dbDuration))s")
        
        let batchDuration = Date().timeIntervalSince(batchStartTime)
        Logger.info("⏱️ [IMPORT] [BATCH] Batch complete in \(String(format: "%.3f", batchDuration))s: \(insertedCount) inserted, \(updatedCount) updated, \(skippedCount) unchanged")

        // Queue all new tracks for analysis together (enables parallel processing)
        if !insertedTrackIds.isEmpty {
            Logger.debug("⏱️ [IMPORT] [QUEUE] Queuing \(insertedTrackIds.count) tracks for parallel analysis")
            AudioAnalysisService.shared.queueForAnalysis(trackIds: insertedTrackIds)
        }

        // Generate waveforms for newly inserted tracks (now they have trackIds from database)
        if insertedCount > 0 {
            // Extract URLs before async closure to avoid Swift 6 concurrency capture error
            let trackPaths = newTracks.map { ($0.0.url.path, $0.0.url) }

            // Collect track IDs and URLs for waveform generation
            let tracksForWaveform = try await dbQueue.read { db -> [(Int64, URL)] in
                var result: [(Int64, URL)] = []
                for (path, url) in trackPaths {
                    // Query the database to get the trackId that was assigned using path column
                    if let dbTrack = try Track.filter(Track.Columns.path == path).fetchOne(db),
                       let trackId = dbTrack.trackId {
                        result.append((trackId, url))
                    }
                }
                return result
            }

            if !tracksForWaveform.isEmpty {
                Logger.info("⏱️ [IMPORT] [WAVEFORM] Queuing generation for \(tracksForWaveform.count) new tracks (background)")
                // Fire-and-forget: Generate waveforms in background without blocking import
                for (trackId, url) in tracksForWaveform {
                    Task.detached(priority: .utility) {
                        do {
                            let waveformStartTime = Date()
                            Logger.debug("⏱️ [IMPORT] [WAVEFORM] Starting: \(url.lastPathComponent)")
                            let waveform = try await WaveformGenerator.generateWaveform(from: url, targetCount: 400)
                            let waveformDuration = Date().timeIntervalSince(waveformStartTime)
                            Logger.debug("⏱️ [IMPORT] [WAVEFORM] Completed in \(String(format: "%.3f", waveformDuration))s: \(url.lastPathComponent)")
                            
                            let cacheStartTime = Date()
                            WaveformCache.shared.cacheWaveform(trackId: String(trackId), samples: waveform)
                            let cacheDuration = Date().timeIntervalSince(cacheStartTime)
                            Logger.debug("⏱️ [IMPORT] [WAVEFORM] Cached in \(String(format: "%.3f", cacheDuration))s: \(url.lastPathComponent)")
                        } catch {
                            Logger.error("Failed to generate waveform for \(url.lastPathComponent): \(error)")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Track Processing
    
    /// Process a new track with normalized data
    /// - Returns: Track ID if inserted, nil if updated or failed
    private func processNewTrack(_ track: Track, metadata: TrackMetadata, in db: Database) throws -> Int64? {
        let processStartTime = Date()
        var mutableTrack = track
        
        // Determine where to store artwork based on album validity
        let hasValidAlbum = !track.album.isEmpty && track.album != "Unknown Album"
        
        // Create/get normalized entities and link them
        let albumStartTime = Date()
        Logger.debug("⏱️ [IMPORT] [DATABASE] [NORMALIZE] Getting/creating album: \(track.album)")
        mutableTrack.albumId = try DatabaseManager.getOrCreateAlbum(
            in: db,
            title: track.album,
            albumArtist: track.albumArtist,
            artist: track.artist,
            year: track.year,
            releaseType: metadata.extended.releaseType,
            recordLabel: metadata.extended.label,
            musicbrainzAlbumId: metadata.extended.musicBrainzAlbumId,
            releaseDate: metadata.releaseDate,
            musicbrainzReleaseGroupId: metadata.extended.musicBrainzReleaseGroupId,
            barcode: metadata.extended.barcode,
            catalogNumber: metadata.extended.catalogNumber,
            releaseCountry: metadata.extended.releaseCountry
        )
        let albumDuration = Date().timeIntervalSince(albumStartTime)
        Logger.debug("⏱️ [IMPORT] [DATABASE] [NORMALIZE] Album operation took \(String(format: "%.3f", albumDuration))s")
        
        let artistStartTime = Date()
        Logger.debug("⏱️ [IMPORT] [DATABASE] [NORMALIZE] Getting/creating artist: \(track.artist)")
        mutableTrack.artistId = try DatabaseManager.getOrCreateArtist(
            in: db,
            name: track.artist,
            musicbrainzArtistId: metadata.extended.musicBrainzArtistId,
            artistType: metadata.extended.artistType,
            country: metadata.extended.releaseCountry
        )
        let artistDuration = Date().timeIntervalSince(artistStartTime)
        Logger.debug("⏱️ [IMPORT] [DATABASE] [NORMALIZE] Artist operation took \(String(format: "%.3f", artistDuration))s")
        
        let genreStartTime = Date()
        Logger.debug("⏱️ [IMPORT] [DATABASE] [NORMALIZE] Getting/creating genre: \(track.genre)")
        mutableTrack.genreId = try DatabaseManager.getOrCreateGenre(
            in: db,
            name: track.genre,
            style: nil  // Style is typically not in tags; could be inferred later
        )
        let genreDuration = Date().timeIntervalSince(genreStartTime)
        Logger.debug("⏱️ [IMPORT] [DATABASE] [NORMALIZE] Genre operation took \(String(format: "%.3f", genreDuration))s")
        
        // Store artwork appropriately
        let artworkStartTime = Date()
        if let artworkData = metadata.artworkData {
            let artworkSourceType: String
            if hasValidAlbum, let albumId = mutableTrack.albumId {
                // Store artwork in album table
                try storeAlbumArtwork(albumId: albumId, artworkData: artworkData, in: db)
                // Remove artwork from track to save space
                mutableTrack.artworkData = nil
                artworkSourceType = "album"
            } else {
                // Store artwork in track table (for tracks without proper album)
                mutableTrack.artworkData = artworkData
                artworkSourceType = "track"
            }
            
            // Also store artwork in artist table if artist exists
            if let artistId = mutableTrack.artistId {
                try storeArtistArtwork(artistId: artistId, artworkData: artworkData, sourceType: artworkSourceType, in: db)
            }
        }
        let artworkDuration = Date().timeIntervalSince(artworkStartTime)
        if artworkDuration > 0.001 {
            Logger.debug("⏱️ [IMPORT] [DATABASE] [ARTWORK] Artwork storage took \(String(format: "%.3f", artworkDuration))s")
        }
        
        // Check if track with this path already exists (handle race conditions)
        let insertStartTime = Date()
        if let existingTrack = try Track.filter(Track.Columns.path == mutableTrack.url.path).fetchOne(db) {
            // Track already exists, update it instead
            mutableTrack.trackId = existingTrack.trackId
            try mutableTrack.update(db)
            Logger.info("Updated existing track: \(mutableTrack.title) (ID: \(mutableTrack.trackId ?? -1))")
            return nil // Return nil for updates
        } else {
            // Insert the track - didInsert() automatically sets trackId
            try mutableTrack.insert(db)
            let insertDuration = Date().timeIntervalSince(insertStartTime)
            Logger.debug("⏱️ [IMPORT] [DATABASE] [INSERT] Track insertion took \(String(format: "%.3f", insertDuration))s")
            
            // Verify insertion succeeded
            guard let trackId = mutableTrack.trackId else {
                throw DatabaseError.invalidTrackId
            }
            
            // Note: Statistics are automatically updated by database triggers
            
            let totalProcessDuration = Date().timeIntervalSince(processStartTime)
            Logger.info("⏱️ [IMPORT] [DATABASE] Added new track: \(mutableTrack.title) (ID: \(trackId)) - Total DB time: \(String(format: "%.3f", totalProcessDuration))s")
            
            // Log interesting metadata in debug builds
            #if DEBUG
            logTrackMetadata(mutableTrack)
            #endif
            
            return trackId // Return trackId for new inserts
        }
    }
    
    /// Process an updated track with normalized data
    private func processUpdatedTrack(_ track: Track, metadata: TrackMetadata, in db: Database) throws {
        var mutableTrack = track
        
        // Determine where to store artwork based on album validity
        let hasValidAlbum = !track.album.isEmpty && track.album != "Unknown Album"
        
        // Create/get normalized entities and link them
        mutableTrack.albumId = try DatabaseManager.getOrCreateAlbum(
            in: db,
            title: track.album,
            albumArtist: track.albumArtist,
            artist: track.artist,
            year: track.year,
            releaseType: metadata.extended.releaseType,
            recordLabel: metadata.extended.label,
            musicbrainzAlbumId: metadata.extended.musicBrainzAlbumId,
            releaseDate: metadata.releaseDate,
            musicbrainzReleaseGroupId: metadata.extended.musicBrainzReleaseGroupId,
            barcode: metadata.extended.barcode,
            catalogNumber: metadata.extended.catalogNumber,
            releaseCountry: metadata.extended.releaseCountry
        )
        
        mutableTrack.artistId = try DatabaseManager.getOrCreateArtist(
            in: db,
            name: track.artist,
            musicbrainzArtistId: metadata.extended.musicBrainzArtistId,
            artistType: metadata.extended.artistType,
            country: metadata.extended.releaseCountry
        )
        
        mutableTrack.genreId = try DatabaseManager.getOrCreateGenre(
            in: db,
            name: track.genre,
            style: nil  // Style is typically not in tags; could be inferred later
        )
        
        // Update artwork storage if metadata contains artwork
        if let artworkData = metadata.artworkData {
            let artworkSourceType: String
            if hasValidAlbum, let albumId = mutableTrack.albumId {
                // Store artwork in album table
                try storeAlbumArtwork(albumId: albumId, artworkData: artworkData, in: db)
                // Remove artwork from track to save space
                mutableTrack.artworkData = nil
                artworkSourceType = "album"
            } else {
                // Store artwork in track table (for tracks without proper album)
                mutableTrack.artworkData = artworkData
                artworkSourceType = "track"
            }
            
            // Also store artwork in artist table if artist exists
            if let artistId = mutableTrack.artistId {
                try storeArtistArtwork(artistId: artistId, artworkData: artworkData, sourceType: artworkSourceType, in: db)
            }
        }
        
        // Update the track
        try mutableTrack.update(db)
        
        guard let trackId = mutableTrack.trackId else {
            throw DatabaseError.invalidTrackId
        }
        
        // Note: Statistics are automatically updated by database triggers
        // The triggers handle both old and new entity statistics when IDs change
        
        Logger.info("Updated track: \(mutableTrack.title) (ID: \(trackId))")
        
        // Queue for audio analysis if features don't exist yet
        // Check if features already exist
        Task {
            let hasFeatures = (try? await DatabaseManager.shared.getSongFeatures(forTrackId: trackId)) != nil
            if !hasFeatures {
                AudioAnalysisService.shared.queueForAnalysis(trackId: trackId)
            }
        }
    }
    
    // MARK: - Metadata Logging
    
    private func logTrackMetadata(_ track: Track) {
        // Log interesting metadata for debugging
        if let extendedMetadata = track.extendedMetadata {
            var interestingFields: [String] = []
            
            if let isrc = extendedMetadata.isrc { interestingFields.append("ISRC: \(isrc)") }
            if let label = extendedMetadata.label { interestingFields.append("Label: \(label)") }
            if let conductor = extendedMetadata.conductor { interestingFields.append("Conductor: \(conductor)") }
            if let producer = extendedMetadata.producer { interestingFields.append("Producer: \(producer)") }
            
            if !interestingFields.isEmpty {
                Logger.info("Extended metadata: \(interestingFields.joined(separator: ", "))")
            }
        }
        
        // Log multi-artist info
        if track.artist.contains(";") || track.artist.contains(",") || track.artist.contains("&") {
            Logger.info("Multi-artist track: \(track.artist)")
        }
        
        // Log album artist if different from artist
        if let albumArtist = track.albumArtist, albumArtist != track.artist {
            Logger.info("Album artist differs: \(albumArtist)")
        }
    }
    
    func getTracksInFolder(_ folder: Folder) -> [Track] {
        guard let folderId = folder.id else { return [] }
        return getTracksForFolder(folderId)
    }
    
    func getTracksForFolder(_ folderId: Int64) -> [Track] {
        do {
            let tracks = try dbQueue.read { db in
                try Track.lightweightRequest()
                    .filter(Track.Columns.folderId == folderId)
                    .order(Track.Columns.title)
                    .fetchAll(db)
            }
            
            return tracks
        } catch {
            Logger.error("Failed to fetch tracks for folder: \(error)")
            return []
        }
    }
    
    
    // Updates a track's favorite status
    func updateTrackFavoriteStatus(_ track: Track) async throws {
        _ = try await dbQueue.write { db in
            try track
                .update(db, columns: [Track.Columns.isFavorite])
        }
    }

    // Updates a track's play count and last played date
    func updateTrackPlayInfo(_ track: Track) async throws {
        _ = try await dbQueue.write { db in
            try track
                .update(db, columns: [Track.Columns.playCount, Track.Columns.lastPlayedDate])
        }
    }
    
    // MARK: - Path Management
    
    /// Update a single track's path in the database
    func updateTrackPath(trackId: Int64, newPath: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE tracks SET path = ? WHERE id = ?",
                arguments: [newPath, trackId]
            )
        }
        
        Logger.debug("Updated track path for ID \(trackId)")
    }
    
    /// Bulk update track paths (for folder relocation)
    /// Replaces oldPathPrefix with newPathPrefix for all matching tracks
    func bulkUpdateTrackPaths(oldPathPrefix: String, newPathPrefix: String) async throws -> Int {
        let count = try await dbQueue.write { db -> Int in
            // Get all affected tracks
            let affectedTracks = try Track
                .filter(Track.Columns.path.like("\(oldPathPrefix)%"))
                .fetchAll(db)
            
            var updatedCount = 0
            
            // Update each track's path
            for track in affectedTracks {
                let relativePath = String(track.url.path.dropFirst(oldPathPrefix.count))
                let newPath = newPathPrefix + relativePath
                
                // Verify file exists at new location before updating
                if FileManager.default.fileExists(atPath: newPath) {
                    try db.execute(
                        sql: "UPDATE tracks SET path = ? WHERE id = ?",
                        arguments: [newPath, track.trackId]
                    )
                    updatedCount += 1
                } else {
                    Logger.warning("Skipping track - file not found at new location: \(track.filename)")
                }
            }
            
            return updatedCount
        }
        
        Logger.info("Bulk updated \(count) track paths")
        return count
    }
    
    /// Get all tracks with missing files (for health check)
    func getTracksWithMissingFiles() async throws -> [Track] {
        try await dbQueue.read { db in
            let allTracks = try Track.lightweightRequest().fetchAll(db)
            
            return allTracks.filter { track in
                !FileManager.default.fileExists(atPath: track.url.path)
            }
        }
    }
    
    /// Verify track paths and return count of missing files
    func verifyTrackPaths() async throws -> (total: Int, missing: Int) {
        try await dbQueue.read { db in
            let allTracks = try Track
                .select(Track.Columns.path)
                .fetchAll(db)
            
            let totalCount = allTracks.count
            let missingCount = allTracks.filter { track in
                !FileManager.default.fileExists(atPath: track.url.path)
            }.count
            
            return (total: totalCount, missing: missingCount)
        }
    }
    
    // MARK: - Artwork Storage
    
    /// Store artwork data in the album table if not already present
    /// Only updates if album doesn't have artwork yet to preserve user-set custom artwork
    private func storeAlbumArtwork(albumId: Int64, artworkData: Data, in db: Database) throws {
        // Check if album already has artwork
        let hasArtwork = try Album
            .select(Album.Columns.artworkData)
            .filter(Album.Columns.id == albumId)
            .fetchOne(db)
            .flatMap { (row: Row) -> Data? in
                row[Album.Columns.artworkData] as Data?
            } != nil
        
        // Only update if album doesn't have artwork
        if !hasArtwork {
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
    }
    
    /// Store artwork data in the artist table if not already present
    /// Only updates if artist doesn't have artwork yet to preserve user-set custom artwork
    /// - Parameters:
    ///   - artistId: Artist ID to update
    ///   - artworkData: Artwork binary data
    ///   - sourceType: Source of artwork: "album", "track", or "custom"
    ///   - db: Database connection
    private func storeArtistArtwork(artistId: Int64, artworkData: Data, sourceType: String, in db: Database) throws {
        // Check if artist already has artwork
        let hasArtwork = try Artist
            .select(Artist.Columns.artworkData)
            .filter(Artist.Columns.id == artistId)
            .fetchOne(db)
            .flatMap { (row: Row) -> Data? in
                row[Artist.Columns.artworkData] as Data?
            } != nil
        
        // Only update if artist doesn't have artwork
        if !hasArtwork {
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
    }
    
}

