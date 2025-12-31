//
//  AudioAnalysisService.swift
//  HiFidelity
//
//  Service to analyze audio files and store BPM/key features in the database
//

import Foundation
import GRDB

/// Service for analyzing audio files and storing features
class AudioAnalysisService {
    static let shared = AudioAnalysisService()
    
    private let analyzer = AudioFeatureAnalyzer.shared
    private let databaseManager = DatabaseManager.shared
    
    private var isAnalyzing = false
    private var analysisQueue: [Int64] = []
    private var analyzedTracks: Set<Int64> = [] // Track which tracks we've already analyzed
    private let queueLock = NSLock()
    
    // Thread-safe queue operations
    private func withQueueLock<T>(_ operation: () -> T) -> T {
        queueLock.lock()
        defer { queueLock.unlock() }
        return operation()
    }
    
    private init() {}
    
    /// Analyze a track and store features in database
    /// - Parameters:
    ///   - trackId: Track ID to analyze
    ///   - url: URL to audio file
    /// - Returns: Analysis result
    func analyzeTrack(trackId: Int64, url: URL) async throws -> AudioAnalysisResult {
        let analysisStartTime = Date()
        Logger.info("⏱️ [ANALYSIS] Starting audio features analysis for track ID: \(trackId)")
        
        // Check if track already has BPM in metadata
        let metadataCheckStartTime = Date()
        let track = try await databaseManager.dbQueue.read { db in
            try Track.filter(Column("id") == trackId).fetchOne(db)
        }
        let metadataCheckDuration = Date().timeIntervalSince(metadataCheckStartTime)
        Logger.debug("⏱️ [ANALYSIS] [METADATA_CHECK] Took \(String(format: "%.3f", metadataCheckDuration))s")
        
        // Use metadata BPM if available (faster than analysis)
        let metadataBPM = track?.bpm.map { Double($0) }
        
        // Calculate timeout based on track duration
        // Analysis typically takes 10-20% of track duration, but we need buffer for longer tracks
        let trackDuration = track?.duration ?? 0
        let timeoutSeconds: TimeInterval
        if trackDuration > 0 {
            // Timeout: 90 seconds base + 30% of track duration, capped at 5 minutes
            // For a 7.5 minute (450s) track: 90 + (450 * 0.3) = 90 + 135 = 225 seconds (3.75 minutes)
            timeoutSeconds = min(90.0 + (trackDuration * 0.3), 300.0)
        } else {
            // Default to 3 minutes if duration unknown (should handle most tracks)
            timeoutSeconds = 180.0
        }
        
        Logger.debug("⏱️ [ANALYSIS] Analysis timeout set to \(Int(timeoutSeconds)) seconds for track duration: \(trackDuration)s")
        
        // Analyze with dynamic timeout
        let audioAnalysisStartTime = Date()
        let result = try await withTimeout(seconds: timeoutSeconds) {
            try await self.analyzer.analyzeAudioFile(at: url, metadataBPM: metadataBPM) { progress in
                Logger.debug("⏱️ [ANALYSIS] Progress: \(Int(progress * 100))%")
            }
        }
        let audioAnalysisDuration = Date().timeIntervalSince(audioAnalysisStartTime)
        Logger.debug("⏱️ [ANALYSIS] [AUDIO] Audio analysis took \(String(format: "%.3f", audioAnalysisDuration))s")
        
        // Create SongFeatures record
        let featuresCreateStartTime = Date()
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
        
        // Derive Camelot key from key/mode
        features.deriveCamelotKey()
        let featuresCreateDuration = Date().timeIntervalSince(featuresCreateStartTime)
        Logger.debug("⏱️ [ANALYSIS] [FEATURES] Features object creation took \(String(format: "%.3f", featuresCreateDuration))s")
        
        // Save to database
        let dbSaveStartTime = Date()
        try await databaseManager.saveSongFeatures(features)
        let dbSaveDuration = Date().timeIntervalSince(dbSaveStartTime)
        Logger.debug("⏱️ [ANALYSIS] [DATABASE] Features save took \(String(format: "%.3f", dbSaveDuration))s")
        
        let totalAnalysisDuration = Date().timeIntervalSince(analysisStartTime)
        Logger.info("⏱️ [ANALYSIS] Saved features for track ID: \(trackId) - BPM: \(result.bpm?.description ?? "N/A"), Key: \(result.key.map { "\($0)" } ?? "N/A") - Total: \(String(format: "%.3f", totalAnalysisDuration))s")
        
        // Notify UI to refresh
        NotificationCenter.default.post(
            name: .songFeaturesDidUpdate,
            object: trackId,
            userInfo: ["trackId": trackId]
        )
        
        return result
    }
    
    /// Queue a track for background analysis
    func queueForAnalysis(trackId: Int64) {
        queueForAnalysis(trackIds: [trackId])
    }
    
    /// Queue multiple tracks for background analysis (batch operation)
    func queueForAnalysis(trackIds: [Int64]) {
        guard !trackIds.isEmpty else { return }
        
        let shouldStart = withQueueLock { () -> Bool in
            // Add tracks that aren't already analyzed or in queue
            for trackId in trackIds {
                if !analyzedTracks.contains(trackId) && !analysisQueue.contains(trackId) {
                    analysisQueue.append(trackId)
                }
            }
            
            return !isAnalyzing && !analysisQueue.isEmpty
        }

        // Start processing if not already running and we have tracks to process
        if shouldStart {
            Task {
                await processQueue()
            }
        }
    }
    
    /// Process queued tracks for analysis (parallel processing)
    private func processQueue() async {
        let queue = withQueueLock {
            isAnalyzing = true
            let queue = analysisQueue
            analysisQueue.removeAll()
            return queue
        }

        Logger.info("⏱️ [ANALYSIS] [QUEUE] Processing \(queue.count) tracks for audio analysis (parallel, max 4 concurrent)")

        // Process tracks in parallel using TaskGroup with concurrency limit
        // Limit to 4 concurrent analyses to avoid overwhelming the system
        let maxConcurrent = 4
        
        // Simple semaphore using an actor for thread-safe counting
        actor ConcurrencyLimiter {
            private var count = 0
            private let max: Int
            
            init(max: Int) {
                self.max = max
            }
            
            func waitForSlot() async {
                while count >= max {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                }
                count += 1
            }
            
            func release() async {
                count -= 1
            }
        }
        
        let limiter = ConcurrencyLimiter(max: maxConcurrent)
        
        try? await withThrowingTaskGroup(of: Void.self) { group in
            // Add all tasks to the group first (they'll start in parallel up to the concurrency limit)
            for trackId in queue {
                await limiter.waitForSlot()
                
                group.addTask {
                    // Release the slot when task completes (can't use defer with await)
                    let taskStartTime = Date()
                    let trackAnalysisStartTime = Date()
                    do {
                        // Get track URL
                        let dbReadStartTime = Date()
                        guard let track = try await self.databaseManager.dbQueue.read({ db in
                            try Track.filter(Column("id") == trackId).fetchOne(db)
                        }) else {
                            Logger.warning("Track not found for analysis: \(trackId)")
                            await limiter.release()
                            return
                        }
                        let dbReadDuration = Date().timeIntervalSince(dbReadStartTime)
                        let taskStartupDuration = Date().timeIntervalSince(taskStartTime)
                        Logger.debug("⏱️ [ANALYSIS] [PARALLEL] Task started in \(String(format: "%.3f", taskStartupDuration))s: \(track.title)")
                        Logger.debug("⏱️ [ANALYSIS] [DATABASE] Track lookup took \(String(format: "%.3f", dbReadDuration))s: \(track.title)")

                        // Analyze
                        Logger.debug("⏱️ [ANALYSIS] Starting analysis: \(track.title)")
                        _ = try await self.analyzeTrack(trackId: trackId, url: track.url)
                        let trackAnalysisDuration = Date().timeIntervalSince(trackAnalysisStartTime)
                        Logger.info("⏱️ [ANALYSIS] Completed in \(String(format: "%.3f", trackAnalysisDuration))s: \(track.title)")

                        // Mark as analyzed on success
                        _ = self.withQueueLock {
                            self.analyzedTracks.insert(trackId)
                        }
                        
                        await limiter.release()

                    } catch {
                        let trackAnalysisDuration = Date().timeIntervalSince(trackAnalysisStartTime)
                        Logger.error("⏱️ [ANALYSIS] Failed after \(String(format: "%.3f", trackAnalysisDuration))s - track \(trackId): \(error.localizedDescription)")
                        Logger.error("Error details: \(error)")
                        if let analysisError = error as? AudioFeatureAnalyzer.AnalysisError {
                            Logger.error("Analysis error type: \(analysisError)")
                        }
                        await limiter.release()
                    }
                }
            }
            
            Logger.debug("⏱️ [ANALYSIS] [PARALLEL] All \(queue.count) tasks added to group, waiting for completion...")
            
            // Wait for all tasks to complete
            for try await _ in group {}
            
            Logger.debug("⏱️ [ANALYSIS] [PARALLEL] All tasks completed")
        }

        let hasMore = withQueueLock {
            isAnalyzing = false
            return !analysisQueue.isEmpty
        }

        // Process any new items that were added while we were working
        if hasMore {
            await processQueue()
        }
    }
    
    /// Analyze all tracks without features (background task)
    /// Processes in batches to avoid overwhelming the system
    func analyzeAllTracksWithoutFeatures() async {
        let batchSize = 10 // Process 10 tracks at a time
        var processedCount = 0
        var totalCount = 0
        
        do {
            // Get all tracks without features (in batches)
            while true {
                let tracks = try await databaseManager.getTracksWithoutFeatures(limit: batchSize)
                
                if tracks.isEmpty {
                    break // No more tracks to process
                }
                
                totalCount += tracks.count
                Logger.info("Found \(tracks.count) tracks without features (batch), total: \(totalCount)")
                
                // Queue all tracks in this batch
                for track in tracks {
                    guard let trackId = track.trackId else { continue }
                    queueForAnalysis(trackId: trackId)
                }
                
                // Wait for current batch to complete before starting next
                // This prevents overwhelming the system
                while isAnalyzing {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                }
                
                processedCount += tracks.count
                
                // Small delay between batches
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            if totalCount > 0 {
                Logger.info("Queued \(totalCount) tracks for background analysis")
            } else {
                // Check if library is empty or all tracks have features
                let trackCount = try? await databaseManager.dbQueue.read { db in
                    try Track.fetchCount(db)
                }

                if let count = trackCount, count > 0 {
                    Logger.info("All \(count) tracks already have features - no analysis needed")
                } else {
                    Logger.debug("No tracks in library to analyze")
                }
            }
        } catch {
            Logger.error("Failed to get tracks without features: \(error)")
        }
    }
    
    // MARK: - Helper Functions
    
    /// Run async operation with timeout
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Start the operation
            group.addTask {
                try await operation()
            }
            
            // Start timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            // Return first completed task (operation or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private struct TimeoutError: Error {
        var localizedDescription: String {
            "Analysis timed out"
        }
    }
    
    private enum AnalysisServiceError: Error {
        case cancelled
        
        var localizedDescription: String {
            switch self {
            case .cancelled:
                return "Analysis was cancelled"
            }
        }
    }
}

