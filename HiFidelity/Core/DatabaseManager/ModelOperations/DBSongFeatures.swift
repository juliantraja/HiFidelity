//
//  DBSongFeatures.swift
//  HiFidelity
//
//  Database operations for song features and embeddings
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Insert/Update Features
    
    /// Insert or update song features for a track
    func saveSongFeatures(_ features: SongFeatures) async throws {
        try await dbQueue.write { db in
            var mutableFeatures = features
            try mutableFeatures.insert(db, onConflict: .replace)
        }
        Logger.debug("Saved song features for track ID: \(features.trackId)")
    }
    
    /// Batch insert/update song features
    func batchSaveSongFeatures(_ featuresArray: [SongFeatures]) async throws {
        try await dbQueue.write { db in
            for var features in featuresArray {
                try features.save(db)
            }
        }
        Logger.info("Batch saved \(featuresArray.count) song features")
    }
    
    // MARK: - Fetch Features
    
    /// Get song features for a specific track
    func getSongFeatures(forTrackId trackId: Int64) async throws -> SongFeatures? {
        try await dbQueue.read { db in
            try SongFeatures
                .filter(SongFeatures.Columns.trackId == trackId)
                .fetchOne(db)
        }
    }
    
    /// Get song features for multiple tracks
    func getSongFeatures(forTrackIds trackIds: [Int64]) async throws -> [SongFeatures] {
        try await dbQueue.read { db in
            try SongFeatures
                .filter(trackIds.contains(SongFeatures.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Get all tracks that have features extracted
    func getTracksWithFeatures() async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .joining(required: Track.hasOne(SongFeatures.self, key: "features"))
                .fetchAll(db)
        }
    }
    
    /// Get tracks without features (need extraction)
    func getTracksWithoutFeatures(limit: Int = 100) async throws -> [Track] {
        try await dbQueue.read { db in
            // Get track IDs that have features
            let tracksWithFeatures = try SongFeatures
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            // Get tracks that don't have features
            return try Track
                .filter(!tracksWithFeatures.contains(Track.Columns.trackId))
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Get features that need update
    func getFeaturesNeedingUpdate(limit: Int = 100) async throws -> [SongFeatures] {
        try await dbQueue.read { db in
            try SongFeatures
                .filter(SongFeatures.Columns.needsUpdate == true)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    // MARK: - Similarity Search
    
    /// Find similar tracks based on embedding cosine similarity
    /// - Parameters:
    ///   - trackId: Source track ID
    ///   - limit: Number of similar tracks to return
    ///   - threshold: Minimum similarity threshold (0.0 to 1.0)
    /// - Returns: Array of (Track, similarity score) tuples
    func findSimilarTracks(
        toTrackId trackId: Int64,
        limit: Int = 10,
        threshold: Double = 0.5
    ) async throws -> [(track: Track, similarity: Double)] {
        // Get source track features
        guard let sourceFeatures = try await getSongFeatures(forTrackId: trackId),
              let sourceEmbedding = sourceFeatures.embedding else {
            Logger.warning("No embedding found for track ID: \(trackId)")
            return []
        }
        
        // Get all tracks with embeddings
        let allFeatures = try await dbQueue.read { db in
            try SongFeatures
                .filter(SongFeatures.Columns.embedding != nil)
                .filter(SongFeatures.Columns.trackId != trackId) // Exclude source
                .fetchAll(db)
        }
        
        // Calculate similarities
        var similarities: [(trackId: Int64, similarity: Double)] = []
        
        for features in allFeatures {
            guard let embedding = features.embedding else { continue }
            
            if let similarity = SongFeatures.cosineSimilarity(sourceEmbedding, embedding),
               similarity >= threshold {
                similarities.append((trackId: features.trackId, similarity: similarity))
            }
        }
        
        // Sort by similarity and get top N
        similarities.sort { $0.similarity > $1.similarity }
        let topSimilar = Array(similarities.prefix(limit))
        
        // Fetch tracks
        let trackIds = topSimilar.map { $0.trackId }
        let tracks = try await dbQueue.read { db in
            try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
        
        // Map tracks with their similarity scores
        return topSimilar.compactMap { similar in
            guard let track = tracks.first(where: { $0.trackId == similar.trackId }) else {
                return nil
            }
            return (track: track, similarity: similar.similarity)
        }
    }
    
    /// Find tracks with similar audio features (not embeddings)
    func findTracksWithSimilarFeatures(
        toTrackId trackId: Int64,
        limit: Int = 10,
        threshold: Double = 0.7
    ) async throws -> [(track: Track, similarity: Double)] {
        // Get source track features
        guard let sourceFeatures = try await getSongFeatures(forTrackId: trackId) else {
            return []
        }
        
        // Get all other features
        let allFeatures = try await dbQueue.read { db in
            try SongFeatures
                .filter(SongFeatures.Columns.trackId != trackId)
                .fetchAll(db)
        }
        
        // Calculate feature similarities
        var similarities: [(trackId: Int64, similarity: Double)] = []
        
        for features in allFeatures {
            let similarity = sourceFeatures.featureSimilarity(to: features)
            if similarity >= threshold {
                similarities.append((trackId: features.trackId, similarity: similarity))
            }
        }
        
        // Sort and get top N
        similarities.sort { $0.similarity > $1.similarity }
        let topSimilar = Array(similarities.prefix(limit))
        
        // Fetch tracks
        let trackIds = topSimilar.map { $0.trackId }
        let tracks = try await dbQueue.read { db in
            try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
        
        return topSimilar.compactMap { similar in
            guard let track = tracks.first(where: { $0.trackId == similar.trackId }) else {
                return nil
            }
            return (track: track, similarity: similar.similarity)
        }
    }
    
    // MARK: - Feature-based Queries
    
    /// Find high-energy tracks
    func getHighEnergyTracks(threshold: Double = 0.7, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.energy >= threshold)
                .order(SongFeatures.Columns.energy.desc)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Find calm/chill tracks
    func getCalmTracks(energyThreshold: Double = 0.4, valenceThreshold: Double = 0.3, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.energy <= energyThreshold)
                .filter(SongFeatures.Columns.valence <= valenceThreshold)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Find happy/upbeat tracks
    func getHappyTracks(valenceThreshold: Double = 0.7, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.valence >= valenceThreshold)
                .order(SongFeatures.Columns.valence.desc)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Find danceable tracks
    func getDanceableTracks(threshold: Double = 0.7, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.danceability >= threshold)
                .order(SongFeatures.Columns.danceability.desc)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Find acoustic tracks
    func getAcousticTracks(threshold: Double = 0.7, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.acousticness >= threshold)
                .order(SongFeatures.Columns.acousticness.desc)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    // MARK: - Similarity Search by Key and BPM
    
    /// Find tracks with similar Camelot key (compatible for mixing)
    /// - Parameters:
    ///   - trackId: Source track ID
    ///   - limit: Maximum number of tracks to return
    ///   - includeCompatible: If true, includes adjacent and relative keys
    /// - Returns: Array of tracks with compatible keys
    func findTracksByCamelotKey(
        toTrackId trackId: Int64,
        limit: Int = 50,
        includeCompatible: Bool = true
    ) async throws -> [Track] {
        // Get source track features
        guard let sourceFeatures = try await getSongFeatures(forTrackId: trackId),
              let sourceCamelotKey = sourceFeatures.camelotKey,
              let sourceKey = CamelotKey(notation: sourceCamelotKey) else {
            Logger.warning("No Camelot key found for track ID: \(trackId)")
            return []
        }
        
        // Get compatible keys
        let searchKeys: [String]
        if includeCompatible {
            searchKeys = sourceKey.compatibleKeys.map { $0.notation }
        } else {
            searchKeys = [sourceCamelotKey]
        }
        
        // Find tracks with matching keys
        let trackIds = try await dbQueue.read { db in
            try SongFeatures
                .filter(searchKeys.contains(SongFeatures.Columns.camelotKey))
                .filter(SongFeatures.Columns.trackId != trackId)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
        }
        
        // Fetch tracks
        let tracks = try await dbQueue.read { db in
            try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .limit(limit)
                .fetchAll(db)
        }
        
        return tracks
    }
    
    /// Find tracks with similar BPM (within a tolerance range)
    /// - Parameters:
    ///   - trackId: Source track ID
    ///   - bpmTolerance: BPM difference tolerance (default ±5 BPM)
    ///   - limit: Maximum number of tracks to return
    /// - Returns: Array of tracks with similar BPM
    func findTracksByBPM(
        toTrackId trackId: Int64,
        bpmTolerance: Double = 5.0,
        limit: Int = 50
    ) async throws -> [Track] {
        // Get source track features or BPM from track metadata
        var sourceBPM: Double?
        
        // Try to get from song_features first
        if let sourceFeatures = try await getSongFeatures(forTrackId: trackId),
           let tempo = sourceFeatures.tempo {
            sourceBPM = tempo
        } else {
            // Fall back to track's bpm field
            let sourceTrack = try await dbQueue.read { db in
                try Track.filter(Track.Columns.trackId == trackId).fetchOne(db)
            }
            if let bpm = sourceTrack?.bpm {
                sourceBPM = Double(bpm)
            }
        }
        
        guard let bpm = sourceBPM else {
            Logger.warning("No BPM found for track ID: \(trackId)")
            return []
        }
        
        let minBPM = bpm - bpmTolerance
        let maxBPM = bpm + bpmTolerance
        
        // Find tracks with similar BPM
        let trackIds = try await dbQueue.read { db -> Set<Int64> in
            var ids: Set<Int64> = []
            
            // Check song_features tempo
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.tempo >= minBPM)
                .filter(SongFeatures.Columns.tempo <= maxBPM)
                .filter(SongFeatures.Columns.trackId != trackId)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            ids.formUnion(featureIds)
            
            // Also check tracks.bpm for tracks without features
            let trackBpmIds = try Track
                .filter(Track.Columns.bpm >= Int(minBPM))
                .filter(Track.Columns.bpm <= Int(maxBPM))
                .filter(Track.Columns.trackId != trackId)
                .select(Track.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            ids.formUnion(trackBpmIds)
            
            return ids
        }
        
        // Fetch tracks
        let tracks = try await dbQueue.read { db in
            try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .limit(limit)
                .fetchAll(db)
        }
        
        return tracks
    }
    
    /// Find tracks similar by both key and BPM
    /// - Parameters:
    ///   - trackId: Source track ID
    ///   - bpmTolerance: BPM difference tolerance (default ±5 BPM)
    ///   - limit: Maximum number of tracks to return
    ///   - includeCompatibleKeys: If true, includes adjacent and relative keys
    /// - Returns: Array of tracks matching both criteria
    func findSimilarTracksByKeyAndBPM(
        toTrackId trackId: Int64,
        bpmTolerance: Double = 5.0,
        limit: Int = 50,
        includeCompatibleKeys: Bool = true
    ) async throws -> [Track] {
        // Get source track features
        guard let sourceFeatures = try await getSongFeatures(forTrackId: trackId) else {
            Logger.warning("No features found for track ID: \(trackId), trying BPM-only search")
            return try await findTracksByBPM(toTrackId: trackId, bpmTolerance: bpmTolerance, limit: limit)
        }
        
        // Get source BPM
        var sourceBPM: Double?
        if let tempo = sourceFeatures.tempo {
            sourceBPM = tempo
        } else {
            let sourceTrack = try await dbQueue.read { db in
                try Track.filter(Track.Columns.trackId == trackId).fetchOne(db)
            }
            if let bpm = sourceTrack?.bpm {
                sourceBPM = Double(bpm)
            }
        }
        
        // Get source Camelot key
        let sourceCamelotKey: CamelotKey?
        if let camelotKey = sourceFeatures.camelotKey,
           let key = CamelotKey(notation: camelotKey) {
            sourceCamelotKey = key
        } else if let key = sourceFeatures.key, let mode = sourceFeatures.mode,
                  let camelot = CamelotKey(key: key, mode: mode) {
            sourceCamelotKey = camelot
        } else {
            sourceCamelotKey = nil
        }
        
        // Build search criteria
        let searchKeys: [String]?
        if let sourceKey = sourceCamelotKey {
            searchKeys = includeCompatibleKeys ? sourceKey.compatibleKeys.map { $0.notation } : [sourceKey.notation]
        } else {
            searchKeys = nil
        }
        
        let minBPM = sourceBPM.map { $0 - bpmTolerance }
        let maxBPM = sourceBPM.map { $0 + bpmTolerance }
        
        // Find matching tracks
        let trackIds = try await dbQueue.read { db -> Set<Int64> in
            var query = SongFeatures
                .filter(SongFeatures.Columns.trackId != trackId)
            
            // Apply key filter if available
            if let keys = searchKeys {
                query = query.filter(keys.contains(SongFeatures.Columns.camelotKey))
            }
            
            // Apply BPM filter if available
            if let min = minBPM, let max = maxBPM {
                query = query.filter(SongFeatures.Columns.tempo >= min)
                query = query.filter(SongFeatures.Columns.tempo <= max)
            }
            
            // If no filters, return empty
            if searchKeys == nil && minBPM == nil {
                return []
            }
            
            return try query
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
        }
        
        // Fetch tracks
        let tracks = try await dbQueue.read { db in
            try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .limit(limit)
                .fetchAll(db)
        }
        
        return tracks
    }
    
    // MARK: - Delete Features
    
    /// Delete song features for a track
    func deleteSongFeatures(forTrackId trackId: Int64) async throws {
        try await dbQueue.write { db in
            _ = try SongFeatures
                .filter(SongFeatures.Columns.trackId == trackId)
                .deleteAll(db)
        }
        Logger.debug("Deleted song features for track ID: \(trackId)")
    }
    
    /// Mark features as needing update
    func markFeaturesForUpdate(trackIds: [Int64]) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE song_features
                SET needs_update = 1
                WHERE track_id IN (\(trackIds.map { String($0) }.joined(separator: ",")))
                """
            )
        }
    }
    
    // MARK: - Statistics
    
    /// Get count of tracks with features
    func getFeaturesCount() async throws -> Int {
        try await dbQueue.read { db in
            try SongFeatures.fetchCount(db)
        }
    }
    
    /// Get extraction coverage percentage
    func getFeaturesCoverage() async throws -> Double {
        try await dbQueue.read { db in
            let totalTracks = try Track.fetchCount(db)
            let tracksWithFeatures = try SongFeatures.fetchCount(db)
            
            guard totalTracks > 0 else { return 0.0 }
            return Double(tracksWithFeatures) / Double(totalTracks) * 100.0
        }
    }
}

// MARK: - Track Extension for Features

extension Track {
    static let features = hasOne(SongFeatures.self, key: "features")
    
    var features: QueryInterfaceRequest<SongFeatures> {
        request(for: Track.features)
    }
}

