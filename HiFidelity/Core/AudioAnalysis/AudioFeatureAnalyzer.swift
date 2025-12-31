//
//  AudioFeatureAnalyzer.swift
//  HiFidelity
//
//  Audio analysis service for extracting BPM and musical key from audio files
//  Uses Accelerate framework for FFT and signal processing
//

import Foundation
import Accelerate
import AVFoundation

/// Audio feature analysis results
struct AudioAnalysisResult {
    let bpm: Double?
    let key: Int?  // 0-11: C, C#, D, etc.
    let mode: Int?  // 0 = minor, 1 = major
    let confidence: Double  // 0.0 to 1.0
    let analysisDuration: TimeInterval
}

/// Audio feature analyzer using Accelerate framework
class AudioFeatureAnalyzer {
    static let shared = AudioFeatureAnalyzer()
    
    private init() {}
    
    /// Analyze audio file to extract BPM and key
    /// - Parameters:
    ///   - url: URL to audio file
    ///   - metadataBPM: Optional BPM from metadata tags (to skip analysis if available)
    ///   - progress: Optional progress callback (0.0 to 1.0)
    /// - Returns: Analysis result with BPM and key
    func analyzeAudioFile(at url: URL, metadataBPM: Double? = nil, progress: ((Double) -> Void)? = nil) async throws -> AudioAnalysisResult {
        let startTime = Date()
        Logger.debug("⏱️ [ANALYSIS] [AUDIO] Starting analyzeAudioFile: \(url.lastPathComponent)")
        
        // Load audio file
        progress?(0.1)
        let loadStartTime = Date()
        let audioData = try await loadAudioData(from: url)
        let loadDuration = Date().timeIntervalSince(loadStartTime)
        Logger.debug("⏱️ [ANALYSIS] [AUDIO] [LOAD] Audio loading took \(String(format: "%.3f", loadDuration))s")
        
        guard !audioData.samples.isEmpty else {
            throw AnalysisError.noAudioData
        }
        
        progress?(0.3)
        
        // Check if BPM detection is enabled
        let enableBPMDetection = UserDefaults.standard.bool(forKey: "enableBPMDetection")
        // Default to true if not set (backward compatibility)
        let shouldAnalyzeBPM = UserDefaults.standard.object(forKey: "enableBPMDetection") == nil ? true : enableBPMDetection
        Logger.debug("⏱️ [ANALYSIS] [BPM] Settings check - enableBPMDetection: \(enableBPMDetection), shouldAnalyzeBPM: \(shouldAnalyzeBPM)")
        
        // Analyze BPM (use metadata if available, otherwise analyze)
        let bpmStartTime = Date()
        let bpm: Double?
        if !shouldAnalyzeBPM {
            Logger.info("⏱️ [ANALYSIS] [BPM] BPM detection stopped in settings, skipping analysis")
            bpm = nil
            progress?(0.5) // Skip BPM analysis
        } else if let metadataBPM = metadataBPM, metadataBPM >= 60 && metadataBPM <= 200 {
            Logger.info("⏱️ [ANALYSIS] [BPM] Using BPM from metadata: \(metadataBPM)")
            bpm = metadataBPM
            progress?(0.5) // Skip BPM analysis
        } else {
            Logger.debug("⏱️ [ANALYSIS] [BPM] Starting BPM analysis")
            bpm = try await analyzeBPM(audioData: audioData, sampleRate: audioData.sampleRate)
            let bpmDuration = Date().timeIntervalSince(bpmStartTime)
            Logger.debug("⏱️ [ANALYSIS] [BPM] BPM analysis took \(String(format: "%.3f", bpmDuration))s")
        }
        progress?(0.6)
        
        // Check if key detection is enabled
        let enableKeyDetection = UserDefaults.standard.bool(forKey: "enableKeyDetection")
        // Default to true if not set (backward compatibility)
        let shouldAnalyzeKey = UserDefaults.standard.object(forKey: "enableKeyDetection") == nil ? true : enableKeyDetection
        Logger.debug("⏱️ [ANALYSIS] [KEY] Settings check - enableKeyDetection: \(enableKeyDetection), shouldAnalyzeKey: \(shouldAnalyzeKey)")
        
        // Analyze key
        let keyStartTime = Date()
        let key: Int?
        let mode: Int?
        let confidence: Double
        
        if !shouldAnalyzeKey {
            Logger.info("⏱️ [ANALYSIS] [KEY] Key detection disabled in settings, skipping analysis")
            key = nil
            mode = nil
            confidence = 0.0
            progress?(0.9)
        } else {
            Logger.debug("⏱️ [ANALYSIS] [KEY] Starting key analysis")
            let result = try await analyzeKey(audioData: audioData, sampleRate: audioData.sampleRate)
            key = result.key
            mode = result.mode
            confidence = result.confidence
            let keyDuration = Date().timeIntervalSince(keyStartTime)
            Logger.debug("⏱️ [ANALYSIS] [KEY] Key analysis took \(String(format: "%.3f", keyDuration))s")
            progress?(0.9)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        Logger.debug("⏱️ [ANALYSIS] [AUDIO] Total analyzeAudioFile took \(String(format: "%.3f", duration))s")
        progress?(1.0)
        
        return AudioAnalysisResult(
            bpm: bpm,
            key: key,
            mode: mode,
            confidence: confidence,
            analysisDuration: duration
        )
    }
    
    // MARK: - Audio Loading
    
    private struct AudioData {
        let samples: [Float]
        let sampleRate: Double
        let channels: Int
    }
    
    private func loadAudioData(from url: URL) async throws -> AudioData {
        Logger.debug("Loading audio data from: \(url.lastPathComponent)")
        
        // Use AVAudioFile for reliable seeking to middle section
        let audioFile = try AVAudioFile(forReading: url)
        let fileFormat = audioFile.processingFormat
        let sampleRate = fileFormat.sampleRate
        let channelCount = Int(fileFormat.channelCount)
        let totalFrameCount = audioFile.length
        let totalDurationSeconds = Double(totalFrameCount) / sampleRate
        
        Logger.debug("Audio file format: \(sampleRate)Hz, \(channelCount) channels, \(totalFrameCount) frames (\(String(format: "%.1f", totalDurationSeconds))s)")
        
        guard totalFrameCount > 0 else {
            Logger.error("Audio file has zero frames")
            throw AnalysisError.noAudioData
        }
        
        // Analyze middle section: skip first 2 minutes and last 2 minutes
        // For a 7-minute track: analyze minutes 3-5 (middle section)
        let skipStart = 120.0 // Skip first 2 minutes
        let skipEnd = 120.0   // Skip last 2 minutes
        let analysisDuration = 120.0 // Analyze 2 minutes
        
        // Calculate middle section start time
        let middleStartTime: Double
        if totalDurationSeconds >= 420.0 {
            // For tracks >= 7 minutes: start at 3 minutes (180s)
            middleStartTime = 180.0
        } else if totalDurationSeconds >= (skipStart + analysisDuration + skipEnd) {
            // For shorter tracks: use middle section, ensuring we skip first and last 2 minutes
            middleStartTime = skipStart
        } else {
            // For very short tracks: start after first 30 seconds, analyze what we can
            middleStartTime = min(30.0, totalDurationSeconds * 0.1)
        }
        
        // Calculate actual duration to analyze (ensure we don't go past end)
        let availableDuration = totalDurationSeconds - middleStartTime - skipEnd
        let actualAnalysisDuration = min(analysisDuration, availableDuration)
        
        guard actualAnalysisDuration > 10.0 else {
            Logger.error("Track too short for middle section analysis: \(totalDurationSeconds)s")
            throw AnalysisError.noAudioData
        }
        
        let analysisFrameCount = AVAudioFrameCount(sampleRate * actualAnalysisDuration)
        let startFrame = AVAudioFramePosition(middleStartTime * sampleRate)
        
        Logger.debug("Analyzing middle section: \(String(format: "%.1f", middleStartTime))s to \(String(format: "%.1f", middleStartTime + actualAnalysisDuration))s (skipping first \(String(format: "%.1f", skipStart))s and last \(String(format: "%.1f", skipEnd))s)")
        Logger.debug("⏱️ [ANALYSIS] [AUDIO] [LOAD] Seeking to frame \(startFrame), reading \(analysisFrameCount) frames")
        
        // Seek to middle section
        audioFile.framePosition = startFrame
        
        // Read the middle section
        guard let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: analysisFrameCount) else {
            Logger.error("Failed to create audio buffer")
            throw AnalysisError.noAudioData
        }
        
        do {
            try audioFile.read(into: buffer, frameCount: analysisFrameCount)
        } catch {
            Logger.error("Failed to read audio file: \(error)")
            throw AnalysisError.loadFailed(error as NSError)
        }
        
        guard buffer.frameLength > 0 else {
            Logger.error("No audio data read from file")
            throw AnalysisError.noAudioData
        }
        
        Logger.debug("⏱️ [ANALYSIS] [AUDIO] [LOAD] Read \(buffer.frameLength) frames from middle section")
        
        // Convert to mono Float array
        let monoSamples = convertToMonoFloat(buffer: buffer)
        
        guard !monoSamples.isEmpty else {
            Logger.error("No audio samples after conversion")
            throw AnalysisError.noAudioData
        }
        
        Logger.debug("⏱️ [ANALYSIS] [AUDIO] [LOAD] Converted to \(monoSamples.count) mono samples")
        
        return AudioData(
            samples: monoSamples,
            sampleRate: sampleRate,
            channels: channelCount
        )
    }
    
    
    private func convertToMonoFloat(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var mono: [Float] = Array(repeating: 0, count: frameLength)
        
        // Average all channels to mono
        for frame in 0..<frameLength {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += channelData[channel][frame]
            }
            mono[frame] = sum / Float(channelCount)
        }
        
        return mono
    }
    
    // MARK: - BPM Analysis
    
    private func analyzeBPM(audioData: AudioData, sampleRate: Double) async throws -> Double? {
        Logger.debug("Analyzing BPM for \(audioData.samples.count) samples at \(sampleRate)Hz")

        let samples = audioData.samples
        let sampleRate = audioData.sampleRate

        // Downsample for faster processing (target ~22050 Hz for good resolution)
        let downsampleFactor = max(1, Int(sampleRate / 22050))
        let downsampled = downsample(samples, factor: downsampleFactor)
        let effectiveSampleRate = sampleRate / Double(downsampleFactor)

        Logger.debug("Downsampled to \(downsampled.count) samples at \(effectiveSampleRate)Hz")

        // Multi-window analysis with overlapping windows
        let windowDuration = 10.0 // 10 seconds per window
        let hopDuration = 5.0 // 5 second hop (50% overlap)
        let windowSamples = Int(effectiveSampleRate * windowDuration)
        let hopSamples = Int(effectiveSampleRate * hopDuration)

        var bpmEstimates: [Double] = []

        // Analyze overlapping windows across the track
        let maxAnalysisDuration = 60.0 // Analyze first 60 seconds
        let maxSamples = min(downsampled.count, Int(effectiveSampleRate * maxAnalysisDuration))

        Logger.debug("Using energy-based onset detection with overlapping windows")

        var startSample = 0
        while startSample + windowSamples <= maxSamples {
            let endSample = min(startSample + windowSamples, maxSamples)
            let windowData = Array(downsampled[startSample..<endSample])

            // Calculate energy to skip low-energy sections
            var energy: Float = 0
            vDSP_rmsqv(windowData, 1, &energy, vDSP_Length(windowData.count))

            if energy > 0.015 { // Skip very quiet sections
                if let bpm = analyzeBPMEnhanced(signal: windowData, sampleRate: effectiveSampleRate) {
                    bpmEstimates.append(bpm)
                    Logger.debug("Window at \(String(format: "%.1f", Double(startSample) / effectiveSampleRate))s: BPM=\(bpm), energy=\(energy)")
                }
            } else {
                Logger.debug("Window at \(String(format: "%.1f", Double(startSample) / effectiveSampleRate))s: Skipped (low energy=\(energy))")
            }

            startSample += hopSamples
        }

        guard !bpmEstimates.isEmpty else {
            Logger.warning("No valid BPM estimates from any window")
            return nil
        }

        // Use median voting to eliminate outliers
        let sortedBPMs = bpmEstimates.sorted()
        let medianBPM: Double
        if sortedBPMs.count % 2 == 0 {
            medianBPM = (sortedBPMs[sortedBPMs.count / 2 - 1] + sortedBPMs[sortedBPMs.count / 2]) / 2.0
        } else {
            medianBPM = sortedBPMs[sortedBPMs.count / 2]
        }

        let finalBPM = round(medianBPM)

        Logger.info("Final BPM: \(finalBPM) (median of \(bpmEstimates.count) estimates: \(bpmEstimates.map { Int($0) }))")

        return finalBPM
    }

    /// Enhanced BPM analysis using autocorrelation with proper peak detection
    private func analyzeBPMEnhanced(signal: [Float], sampleRate: Double) -> Double? {
        let minBPM = 80.0
        let maxBPM = 160.0

        // Apply band-pass filter to emphasize beat frequencies (80-200 Hz for kicks)
        let filtered = bandPassFilter(signal, sampleRate: sampleRate, lowCutoff: 80.0, highCutoff: 200.0)

        // Calculate BPM range in samples
        let minPeriod = 60.0 / maxBPM
        let maxPeriod = 60.0 / minBPM

        let minLag = Int(sampleRate * minPeriod)
        let maxLag = Int(sampleRate * maxPeriod)

        guard minLag < maxLag && maxLag < filtered.count / 2 else {
            return nil
        }

        // Autocorrelation on filtered signal
        let autocorr = autocorrelation(signal: filtered, maxLag: maxLag + 1000)

        guard minLag < autocorr.count else { return nil }

        // Calculate adaptive threshold based on signal energy
        var maxCorr: Float = 0
        vDSP_maxv(Array(autocorr[minLag..<min(maxLag, autocorr.count)]), 1, &maxCorr, vDSP_Length(min(maxLag, autocorr.count) - minLag))
        let threshold = max(0.10, maxCorr * 0.3) // Adaptive threshold: at least 30% of max peak

        // Find all significant peaks in the autocorrelation
        var peaks: [(lag: Int, value: Float, refinedLag: Double)] = []
        let searchEnd = min(maxLag, autocorr.count - 1)

        for lag in minLag..<searchEnd {
            if lag > 5 && lag < autocorr.count - 5 {
                // Check if this is a local maximum
                let isMax = autocorr[lag] > autocorr[lag-1] &&
                           autocorr[lag] > autocorr[lag+1] &&
                           autocorr[lag] > autocorr[lag-2] &&
                           autocorr[lag] > autocorr[lag+2]

                if isMax && autocorr[lag] > threshold {
                    // Parabolic interpolation for sub-sample accuracy
                    let refinedLag = parabolicInterpolation(
                        y1: autocorr[lag-1],
                        y2: autocorr[lag],
                        y3: autocorr[lag+1],
                        x: Double(lag)
                    )
                    peaks.append((lag, autocorr[lag], refinedLag))
                }
            }
        }

        guard !peaks.isEmpty else {
            Logger.debug("No peaks found in autocorrelation")
            return nil
        }

        // Score peaks based on strength and harmonic content
        var scoredPeaks: [(lag: Int, value: Float, refinedLag: Double, score: Double)] = []

        for peak in peaks {
            // Base score from peak strength
            var score = Double(peak.value)

            // Boost score if harmonics (2x, 3x) are also present
            let harmonic2Lag = peak.lag / 2
            let harmonic3Lag = peak.lag / 3

            if harmonic2Lag >= minLag && harmonic2Lag < autocorr.count {
                let harmonic2Strength = autocorr[harmonic2Lag]
                score += Double(harmonic2Strength) * 0.5 // Boost for 2x harmonic
            }

            if harmonic3Lag >= minLag && harmonic3Lag < autocorr.count {
                let harmonic3Strength = autocorr[harmonic3Lag]
                score += Double(harmonic3Strength) * 0.3 // Boost for 3x harmonic
            }

            scoredPeaks.append((peak.lag, peak.value, peak.refinedLag, score))
        }

        // Sort by harmonic-aware score
        scoredPeaks.sort { $0.score > $1.score }

        // Take the best scored peak
        let bestPeak = scoredPeaks[0]
        let period = bestPeak.refinedLag / sampleRate
        var bpm = 60.0 / period

        Logger.debug("Found \(peaks.count) peaks, best scored at lag=\(bestPeak.lag) (refined: \(String(format: "%.2f", bestPeak.refinedLag)), BPM=\(String(format: "%.1f", bpm)), strength=\(String(format: "%.3f", bestPeak.value)), score=\(String(format: "%.3f", bestPeak.score)))")

        // Harmonic correction for 2x/0.5x errors
        if bpm > maxBPM {
            let half = bpm / 2.0
            if half >= minBPM && half <= maxBPM {
                Logger.debug("Correcting 2x: \(String(format: "%.1f", bpm)) → \(String(format: "%.1f", half))")
                bpm = half
            }
        } else if bpm < minBPM {
            let double = bpm * 2.0
            if double >= minBPM && double <= maxBPM {
                Logger.debug("Correcting 0.5x: \(String(format: "%.1f", bpm)) → \(String(format: "%.1f", double))")
                bpm = double
            }
        }

        return round(bpm)
    }

    /// Parabolic interpolation for sub-sample peak refinement
    /// Given three points around a peak, finds the true peak location
    private func parabolicInterpolation(y1: Float, y2: Float, y3: Float, x: Double) -> Double {
        let denom = 2.0 * (2.0 * Double(y2) - Double(y1) - Double(y3))

        // Avoid division by zero
        guard abs(denom) > 1e-10 else {
            return x
        }

        let delta = Double(y1 - y3) / denom
        return x + delta
    }

    /// Calculate enhanced onset envelope using spectral flux
    private func calculateOnsetEnvelopeEnhanced(samples: [Float], sampleRate: Double) -> [Float] {
        let frameSize = 512
        let hopSize = 256
        var envelope: [Float] = []

        var previousMagnitudes = [Float](repeating: 0, count: frameSize / 2)

        for i in stride(from: 0, to: samples.count - frameSize, by: hopSize) {
            let frame = Array(samples[i..<min(i + frameSize, samples.count)])

            // Calculate FFT magnitudes
            let fft = calculateFFT(frame)
            let magnitudes = fft.prefix(frameSize / 2).map { abs($0) }

            // Spectral flux: sum of positive differences
            var flux: Float = 0
            for j in 0..<magnitudes.count {
                let diff = magnitudes[j] - previousMagnitudes[j]
                if diff > 0 {
                    flux += diff
                }
            }

            envelope.append(flux)
            previousMagnitudes = magnitudes
        }

        // Smooth the envelope
        return smoothSignal(envelope)
    }

    /// Simple moving average smoothing
    private func smoothSignal(_ signal: [Float], windowSize: Int = 3) -> [Float] {
        guard signal.count > windowSize else { return signal }

        var smoothed = [Float](repeating: 0, count: signal.count)

        for i in 0..<signal.count {
            let start = max(0, i - windowSize / 2)
            let end = min(signal.count, i + windowSize / 2 + 1)
            let sum = signal[start..<end].reduce(0, +)
            smoothed[i] = sum / Float(end - start)
        }

        return smoothed
    }

    /// Find consensus BPM from multiple window estimates
    private func consensusBPM(from estimates: [(bpm: Double, confidence: Float)]) -> Double {
        guard !estimates.isEmpty else { return 120.0 }

        // Group BPMs within 3 BPM tolerance (accounts for slight variations)
        let tolerance = 3.0
        var clusters: [Double: [(bpm: Double, confidence: Float)]] = [:]

        for estimate in estimates {
            var foundCluster = false

            for clusterBPM in clusters.keys {
                if abs(estimate.bpm - clusterBPM) <= tolerance {
                    clusters[clusterBPM]!.append(estimate)
                    foundCluster = true
                    break
                }
            }

            if !foundCluster {
                clusters[estimate.bpm] = [estimate]
            }
        }

        // Find the cluster with highest total confidence
        var bestCluster: (bpm: Double, totalConfidence: Float, count: Int) = (0, 0, 0)

        for (clusterBPM, estimates) in clusters {
            let totalConfidence = estimates.reduce(0) { $0 + $1.confidence }
            let count = estimates.count

            // Prefer clusters with both high confidence and multiple votes
            let score = totalConfidence * Float(count)

            if score > bestCluster.totalConfidence * Float(bestCluster.count) {
                bestCluster = (clusterBPM, totalConfidence, count)
            }
        }

        // Calculate weighted average within the best cluster
        let bestEstimates = clusters[bestCluster.bpm]!
        let weightedSum = bestEstimates.reduce(0.0) { $0 + ($1.bpm * Double($1.confidence)) }
        let totalWeight = bestEstimates.reduce(0.0) { $0 + Double($1.confidence) }

        let finalBPM = round(weightedSum / totalWeight)

        Logger.debug("Consensus: \(bestCluster.count) votes for ~\(Int(bestCluster.bpm)) BPM, final=\(finalBPM)")

        return finalBPM
    }

    /// Calculate onset envelope (energy variations that indicate beats)
    private func calculateOnsetEnvelope(samples: [Float], sampleRate: Double) -> [Float] {
        // Use spectral flux or energy envelope
        let hopSize = 512
        let frameSize = 2048
        var envelope: [Float] = []

        // Calculate energy in overlapping frames
        for i in stride(from: 0, to: samples.count - frameSize, by: hopSize) {
            let frame = Array(samples[i..<min(i + frameSize, samples.count)])

            // Calculate RMS energy
            var energy: Float = 0
            vDSP_rmsqv(frame, 1, &energy, vDSP_Length(frame.count))

            envelope.append(energy)
        }

        // Differentiate to get onset strength
        var onsetStrength = [Float](repeating: 0, count: envelope.count)
        for i in 1..<envelope.count {
            onsetStrength[i] = max(0, envelope[i] - envelope[i-1])
        }

        return onsetStrength
    }

    /// Band-pass filter to isolate beat frequencies
    private func bandPassFilter(_ samples: [Float], sampleRate: Double, lowCutoff: Double, highCutoff: Double) -> [Float] {
        // Apply high-pass then low-pass
        let highPassed = highPassFilter(samples, sampleRate: sampleRate, cutoff: lowCutoff)

        // Simple low-pass filter
        let rc = 1.0 / (2.0 * Double.pi * highCutoff)
        let dt = 1.0 / sampleRate
        let alpha = Float(dt / (rc + dt))

        var lowPassed = highPassed
        for i in 1..<lowPassed.count {
            lowPassed[i] = alpha * highPassed[i] + (1 - alpha) * lowPassed[i-1]
        }

        return lowPassed
    }
    
    // MARK: - Key Analysis
    
    private func analyzeKey(audioData: AudioData, sampleRate: Double) async throws -> (key: Int?, mode: Int?, confidence: Double) {
        Logger.debug("Analyzing key for \(audioData.samples.count) samples at \(sampleRate)Hz")

        let samples = audioData.samples
        let sampleRate = audioData.sampleRate

        // Downsample for faster processing
        let downsampleFactor = max(1, Int(sampleRate / 22050))
        let downsampled = downsample(samples, factor: downsampleFactor)
        let effectiveSampleRate = sampleRate / Double(downsampleFactor)

        // Multi-window analysis with voting (improves accuracy)
        let windowDuration = 20.0  // 20-second windows
        let hopDuration = 10.0     // 10-second hop (50% overlap)
        let windowSamples = Int(effectiveSampleRate * windowDuration)
        let hopSamples = Int(effectiveSampleRate * hopDuration)

        var keyVotes: [(key: Int, mode: Int, confidence: Double)] = []

        Logger.debug("Analyzing key using multi-window voting (window=\(windowDuration)s, hop=\(hopDuration)s)")

        // Analyze overlapping windows across the entire track
        var startSample = 0
        var windowCount = 0

        while startSample + windowSamples <= downsampled.count {
            let endSample = min(startSample + windowSamples, downsampled.count)
            let windowData = Array(downsampled[startSample..<endSample])

            // Calculate energy to skip low-energy sections
            var energy: Float = 0
            vDSP_rmsqv(windowData, 1, &energy, vDSP_Length(windowData.count))

            if energy > 0.01 {  // Skip very quiet sections
                let chromagram = calculateChromagram(samples: windowData, sampleRate: effectiveSampleRate)
                let (key, mode, conf) = matchKeyProfile(chromagram: chromagram)

                if let k = key, let m = mode, conf > 0.3 {  // Only accept confident detections
                    keyVotes.append((k, m, conf))
                    Logger.debug("Window \(windowCount) at \(String(format: "%.1f", Double(startSample) / effectiveSampleRate))s: key=\(k), mode=\(m == 0 ? "minor" : "major"), conf=\(String(format: "%.2f", conf)), energy=\(String(format: "%.3f", energy))")
                }
            } else {
                Logger.debug("Window \(windowCount) at \(String(format: "%.1f", Double(startSample) / effectiveSampleRate))s: Skipped (low energy=\(String(format: "%.3f", energy)))")
            }

            startSample += hopSamples
            windowCount += 1
        }

        // If we didn't get enough votes, analyze the whole track as one window
        if keyVotes.isEmpty {
            Logger.debug("No confident key votes from windows, analyzing entire track")
            let chromagram = calculateChromagram(samples: downsampled, sampleRate: effectiveSampleRate)
            let (key, mode, confidence) = matchKeyProfile(chromagram: chromagram)

            if let key = key, let mode = mode {
                Logger.info("Detected key (full track): \(key), mode: \(mode == 0 ? "minor" : "major"), confidence: \(String(format: "%.2f", confidence))")
            } else {
                Logger.warning("Could not detect key")
            }

            return (key, mode, confidence)
        }

        // Vote on most common key (weighted by confidence)
        let (finalKey, finalMode, finalConfidence) = consensusKey(from: keyVotes)

        if let key = finalKey, let mode = finalMode {
            Logger.info("Detected key (consensus of \(keyVotes.count) windows): \(key), mode: \(mode == 0 ? "minor" : "major"), confidence: \(String(format: "%.2f", finalConfidence))")
        } else {
            Logger.warning("Could not detect key from \(keyVotes.count) windows")
        }

        return (finalKey, finalMode, finalConfidence)
    }

    /// Calculate consensus key from multiple window votes (weighted by confidence and position)
    private func consensusKey(from votes: [(key: Int, mode: Int, confidence: Double)]) -> (Int?, Int?, Double) {
        guard !votes.isEmpty else { return (nil, nil, 0) }

        // Group by (key, mode) pair with position weighting
        var scores: [String: (key: Int, mode: Int, totalWeightedConfidence: Double, count: Int, rawConfidence: Double)] = [:]

        for (index, vote) in votes.enumerated() {
            let keyPair = "\(vote.key)-\(vote.mode)"

            // Position weighting: boost middle 60% of track (0.2 to 0.8)
            // Intro/outro often have different keys or build-ups
            let position = Double(index) / Double(votes.count)
            let positionWeight: Double
            if position < 0.15 {
                // First 15%: intro (reduced weight)
                positionWeight = 0.6
            } else if position < 0.85 {
                // Middle 70%: main section (full weight)
                positionWeight = 1.5
            } else {
                // Last 15%: outro (reduced weight)
                positionWeight = 0.6
            }

            let weightedConfidence = vote.confidence * positionWeight

            if var existing = scores[keyPair] {
                existing.totalWeightedConfidence += weightedConfidence
                existing.rawConfidence += vote.confidence
                existing.count += 1
                scores[keyPair] = existing
            } else {
                scores[keyPair] = (vote.key, vote.mode, weightedConfidence, 1, vote.confidence)
            }
        }

        // Find highest scoring key (weighted confidence × vote count)
        var bestScore: Double = 0
        var bestKey: Int?
        var bestMode: Int?
        var bestConfidence: Double = 0

        for (_, data) in scores {
            // Score combines weighted confidence and vote count
            let score = data.totalWeightedConfidence * Double(data.count)

            if score > bestScore {
                bestScore = score
                bestKey = data.key
                bestMode = data.mode
                // Average raw confidence (unweighted for reporting)
                bestConfidence = data.rawConfidence / Double(data.count)
            }
        }

        // Log vote distribution
        let voteSummary = scores.values
            .sorted { ($0.totalWeightedConfidence * Double($0.count)) > ($1.totalWeightedConfidence * Double($1.count)) }
            .prefix(3)
            .map { "\($0.key)\($0.mode == 0 ? "m" : "")(\($0.count) votes, weighted score=\(String(format: "%.1f", $0.totalWeightedConfidence * Double($0.count))))" }
            .joined(separator: ", ")

        Logger.debug("Key vote distribution (top 3): \(voteSummary)")

        return (bestKey, bestMode, bestConfidence)
    }
    
    // MARK: - Signal Processing Helpers
    
    private func downsample(_ samples: [Float], factor: Int) -> [Float] {
        guard factor > 1 else { return samples }
        
        var downsampled: [Float] = []
        downsampled.reserveCapacity(samples.count / factor)
        
        for i in stride(from: 0, to: samples.count, by: factor) {
            downsampled.append(samples[i])
        }
        
        return downsampled
    }
    
    private func highPassFilter(_ samples: [Float], sampleRate: Double, cutoff: Double) -> [Float] {
        // Simple high-pass filter using difference equation
        let rc = 1.0 / (2.0 * Double.pi * cutoff)
        let dt = 1.0 / sampleRate
        let alpha = Float(rc / (rc + dt))
        
        var filtered = samples
        var prev = samples[0]
        
        for i in 1..<samples.count {
            filtered[i] = alpha * (filtered[i-1] + samples[i] - prev)
            prev = samples[i]
        }
        
        return filtered
    }
    
    private func autocorrelation(signal: [Float], maxLag: Int) -> [Float] {
        let n = signal.count
        let maxLag = min(maxLag, n / 2)
        var autocorr = [Float](repeating: 0, count: maxLag)

        // Remove DC component
        var signalArray = signal
        var mean: Float = 0
        vDSP_meanv(signalArray, 1, &mean, vDSP_Length(n))
        var negMean = -mean
        vDSP_vsadd(signalArray, 1, &negMean, &signalArray, 1, vDSP_Length(n))

        // Calculate standard deviation for normalization
        var stdDev: Float = 0
        vDSP_measqv(signalArray, 1, &stdDev, vDSP_Length(n))
        stdDev = sqrtf(stdDev / Float(n))

        guard stdDev > 0 else { return autocorr }

        // Use FFT-based autocorrelation for efficiency (O(n log n) instead of O(n²))
        // Pad to next power of 2 for FFT
        let paddedLength = nextPowerOf2(n * 2)
        var padded = signalArray
        padded.append(contentsOf: [Float](repeating: 0, count: paddedLength - n))

        let log2n = vDSP_Length(log2(Float(paddedLength)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            // Fallback to simple method for small signals
            return autocorrelationSimple(signal: signalArray, maxLag: maxLag, stdDev: stdDev)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Prepare split complex buffers
        let halfLength = paddedLength / 2
        var realp = [Float](repeating: 0, count: halfLength)
        var imagp = [Float](repeating: 0, count: halfLength)

        // Convert to split complex format and perform FFT
        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                // Convert padded signal to split complex
                padded.withUnsafeBytes { ptr in
                    ptr.bindMemory(to: DSPComplex.self).baseAddress.map {
                        vDSP_ctoz($0, 2, &splitComplex, 1, vDSP_Length(halfLength))
                    }
                }

                // Forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Calculate power spectrum (magnitude squared)
                var magnitudes = [Float](repeating: 0, count: halfLength)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfLength))

                // Put magnitudes back into split complex for inverse FFT
                magnitudes.withUnsafeBufferPointer { magPtr in
                    realPtr.baseAddress!.update(from: magPtr.baseAddress!, count: halfLength)
                }
                vDSP_vclr(imagPtr.baseAddress!, 1, vDSP_Length(halfLength))

                // Inverse FFT to get autocorrelation
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_INVERSE))
            }
        }

        // Extract and normalize autocorrelation values
        var result = [Float](repeating: 0, count: paddedLength)
        result.withUnsafeMutableBytes { resultPtr in
            realp.withUnsafeBufferPointer { realPtr in
                imagp.withUnsafeBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!), imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!))
                    if let complexPtr = resultPtr.bindMemory(to: DSPComplex.self).baseAddress {
                        vDSP_ztoc(&splitComplex, 1, UnsafeMutablePointer(mutating: complexPtr), 2, vDSP_Length(halfLength))
                    }
                }
            }
        }

        // Scale by FFT length and normalize
        var scale = Float(1.0) / Float(paddedLength)
        vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(paddedLength))

        // Extract and normalize the lags we need
        for lag in 0..<maxLag {
            autocorr[lag] = result[lag] / Float(n - lag) / (stdDev * stdDev)
        }

        return autocorr
    }

    // Fallback simple autocorrelation for small signals
    private func autocorrelationSimple(signal: [Float], maxLag: Int, stdDev: Float) -> [Float] {
        let n = signal.count
        var autocorr = [Float](repeating: 0, count: maxLag)

        for lag in 0..<maxLag {
            var sum: Float = 0
            for i in 0..<(n - lag) {
                sum += signal[i] * signal[i + lag]
            }
            autocorr[lag] = sum / Float(n - lag) / (stdDev * stdDev)
        }

        return autocorr
    }

    private func nextPowerOf2(_ n: Int) -> Int {
        var power = 1
        while power < n {
            power *= 2
        }
        return power
    }
    
    private func findPeaks(in signal: [Float], minDistance: Int) -> [Int] {
        var peaks: [Int] = []
        
        for i in minDistance..<(signal.count - minDistance) {
            let isPeak = signal[i] > signal[i-1] && signal[i] > signal[i+1]
            let isLocalMax = (i-minDistance..<i).allSatisfy { signal[$0] < signal[i] } &&
                            (i+1...i+minDistance).allSatisfy { signal[$0] < signal[i] }
            
            if isPeak && isLocalMax && signal[i] > 0.1 {
                peaks.append(i)
            }
        }
        
        // Sort by magnitude
        peaks.sort { signal[$0] > signal[$1] }
        
        return peaks
    }
    
    private func calculateChromagram(samples: [Float], sampleRate: Double) -> [Float] {
        // Optimized chromagram calculation with reused FFT setup for better performance
        // Use larger FFT size for better frequency resolution in lower frequencies
        
        let fftSize = 8192  // Increased from 4096 for better low-frequency resolution
        let hopSize = 4096  // 50% overlap
        let numChromaBins = 12
        
        var chromagram = [Float](repeating: 0, count: numChromaBins)
        var frameCount = 0
        
        // Apply windowing to reduce spectral leakage
        let windowedSamples = applyWindow(samples)
        
        // Pre-calculate FFT setup once and reuse for all frames (major performance improvement)
        let log2n = Int(ceil(log2(Double(fftSize))))
        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else {
            Logger.warning("Failed to create FFT setup, using fallback")
            return calculateChromagramFallback(samples: samples, sampleRate: sampleRate)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // Pre-allocate buffers for FFT operations
        let fftOutputSize = fftSize / 2
        var realp = [Float](repeating: 0, count: fftOutputSize)
        var imagp = [Float](repeating: 0, count: fftOutputSize)
        
        // Process in frames with reused FFT setup
        for start in stride(from: 0, to: windowedSamples.count - fftSize, by: hopSize) {
            let end = min(start + fftSize, windowedSamples.count)
            let frame = Array(windowedSamples[start..<end])
            
            // Pad frame to fftSize if needed
            var paddedFrame = frame
            if paddedFrame.count < fftSize {
                paddedFrame.append(contentsOf: Array(repeating: 0, count: fftSize - paddedFrame.count))
            }
            
            // Calculate FFT using reused setup (much faster)
            let fft = calculateFFTWithSetup(
                samples: paddedFrame,
                fftSetup: fftSetup,
                log2n: log2n,
                realp: &realp,
                imagp: &imagp
            )
            
            // Map FFT bins to chroma bins
            let chroma = mapToChroma(fft: fft, sampleRate: sampleRate, fftSize: fftSize)
            
            // Accumulate
            for i in 0..<numChromaBins {
                chromagram[i] += chroma[i]
            }
            
            frameCount += 1
        }
        
        // Normalize by frame count
        if frameCount > 0 {
            for i in 0..<numChromaBins {
                chromagram[i] /= Float(frameCount)
            }
        }
        
        // L2 normalization for better key profile matching
        var sumSquares: Float = 0
        for i in 0..<numChromaBins {
            sumSquares += chromagram[i] * chromagram[i]
        }
        let norm = sqrt(sumSquares)
        if norm > 0 {
            for i in 0..<numChromaBins {
                chromagram[i] /= norm
            }
        }
        
        return chromagram
    }
    
    /// Optimized FFT calculation that reuses pre-created FFT setup
    private func calculateFFTWithSetup(
        samples: [Float],
        fftSetup: FFTSetup,
        log2n: Int,
        realp: inout [Float],
        imagp: inout [Float]
    ) -> [Float] {
        let fftSize = samples.count
        let fftOutputSize = fftSize / 2
        
        // Reset buffers
        realp = [Float](repeating: 0, count: fftOutputSize)
        imagp = [Float](repeating: 0, count: fftOutputSize)
        
        // Convert real input to split complex format
        var tempComplex = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftOutputSize)
        for i in 0..<fftOutputSize {
            let idx1 = i * 2
            let idx2 = i * 2 + 1
            if idx1 < samples.count {
                tempComplex[i].real = samples[idx1]
            }
            if idx2 < samples.count {
                tempComplex[i].imag = samples[idx2]
            }
        }
        
        // Perform FFT with reused setup
        let magnitudes: [Float] = realp.withUnsafeMutableBufferPointer { realBuffer -> [Float] in
            return imagp.withUnsafeMutableBufferPointer { imagBuffer -> [Float] in
                guard let realBase = realBuffer.baseAddress,
                      let imagBase = imagBuffer.baseAddress else {
                    return [Float](repeating: 0, count: fftOutputSize)
                }
                
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                
                tempComplex.withUnsafeBufferPointer { complexBuffer in
                    guard let complexBase = complexBuffer.baseAddress else { return }
                    vDSP_ctoz(complexBase, 2, &split, 1, vDSP_Length(fftOutputSize))
                }
                
                // Perform forward FFT (reusing setup)
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
                
                // Calculate magnitude spectrum
                var mags = [Float](repeating: 0, count: fftOutputSize)
                mags.withUnsafeMutableBufferPointer { magsBuffer in
                    guard let magsBase = magsBuffer.baseAddress else { return }
                    vDSP_zvmags(&split, 1, magsBase, 1, vDSP_Length(fftOutputSize))
                }
                
                return mags
            }
        }
        
        // Take square root to get magnitude (vDSP_zvmags returns squared magnitude)
        var magnitudesSqrt = [Float](repeating: 0, count: fftOutputSize)
        var count = Int32(fftOutputSize)
        
        magnitudesSqrt.withUnsafeMutableBufferPointer { sqrtBuffer in
            magnitudes.withUnsafeBufferPointer { magsBuffer in
                guard let sqrtBase = sqrtBuffer.baseAddress,
                      let magsBase = magsBuffer.baseAddress else { return }
                vvsqrtf(sqrtBase, magsBase, &count)
            }
        }
        
        return magnitudesSqrt
    }
    
    /// Fallback chromagram calculation if FFT setup fails
    private func calculateChromagramFallback(samples: [Float], sampleRate: Double) -> [Float] {
        Logger.warning("Using fallback chromagram calculation")
        let numChromaBins = 12
        var chromagram = [Float](repeating: 0, count: numChromaBins)
        
        // Simple energy-based approximation
        let windowSize = 4096
        for start in stride(from: 0, to: samples.count - windowSize, by: windowSize / 2) {
            let window = Array(samples[start..<min(start + windowSize, samples.count)])
            var energy: Float = 0
            for sample in window {
                energy += abs(sample)
            }
            // Distribute energy evenly (not accurate but prevents crashes)
            let avgEnergy = energy / Float(windowSize) / Float(numChromaBins)
            for i in 0..<numChromaBins {
                chromagram[i] += avgEnergy
            }
        }
        
        return chromagram
    }
    
    private func calculateFFT(_ samples: [Float]) -> [Float] {
        // Calculate FFT using Accelerate framework's vDSP
        let n = samples.count
        guard n > 0 else { return [] }
        
        // Find next power of 2 for FFT
        let log2n = Int(ceil(log2(Double(n))))
        let fftSize = 1 << log2n
        
        // Pad samples to power of 2
        var padded = samples
        if padded.count < fftSize {
            padded.append(contentsOf: Array(repeating: 0, count: fftSize - padded.count))
        }
        
        // Setup FFT
        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else {
            Logger.warning("Failed to create FFT setup, using fallback")
            return calculateFFTFallback(samples)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // Prepare split complex format for real FFT
        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)

        // Convert real input to split complex format
        // For real FFT, we pack pairs of real samples as complex
        var tempComplex = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize / 2)
        for i in 0..<(fftSize / 2) {
            let idx1 = i * 2
            let idx2 = i * 2 + 1
            if idx1 < padded.count {
                tempComplex[i].real = padded[idx1]
            }
            if idx2 < padded.count {
                tempComplex[i].imag = padded[idx2]
            }
        }

        // Perform all operations with buffer pointers in a single scope
        let magnitudes: [Float] = realp.withUnsafeMutableBufferPointer { realBuffer -> [Float] in
            return imagp.withUnsafeMutableBufferPointer { imagBuffer -> [Float] in
                // Convert to split complex format
                guard let realBase = realBuffer.baseAddress,
                      let imagBase = imagBuffer.baseAddress else {
                    return [Float](repeating: 0, count: fftSize / 2)
                }

                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)

                tempComplex.withUnsafeBufferPointer { complexBuffer in
                    guard let complexBase = complexBuffer.baseAddress else { return }
                    vDSP_ctoz(complexBase, 2, &split, 1, vDSP_Length(fftSize / 2))
                }

                // Perform forward FFT
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))

                // Calculate magnitude spectrum
                var mags = [Float](repeating: 0, count: fftSize / 2)
                mags.withUnsafeMutableBufferPointer { magsBuffer in
                    guard let magsBase = magsBuffer.baseAddress else { return }
                    vDSP_zvmags(&split, 1, magsBase, 1, vDSP_Length(fftSize / 2))
                }

                return mags
            }
        }
        
        // Take square root to get magnitude (vDSP_zvmags returns squared magnitude)
        var magnitudesSqrt = [Float](repeating: 0, count: fftSize / 2)
        var count = Int32(fftSize / 2)

        magnitudesSqrt.withUnsafeMutableBufferPointer { sqrtBuffer in
            magnitudes.withUnsafeBufferPointer { magsBuffer in
                guard let sqrtBase = sqrtBuffer.baseAddress,
                      let magsBase = magsBuffer.baseAddress else { return }
                vvsqrtf(sqrtBase, magsBase, &count)
            }
        }

        return magnitudesSqrt
    }
    
    /// Fallback FFT calculation if vDSP fails
    private func calculateFFTFallback(_ samples: [Float]) -> [Float] {
        // Simple energy-based approximation as fallback
        // This won't give accurate key detection but will prevent crashes
        Logger.warning("Using fallback FFT - key detection may be inaccurate")
        
        let windowSize = 4096
        var magnitudes: [Float] = []
        
        for start in stride(from: 0, to: samples.count - windowSize, by: windowSize / 2) {
            let window = Array(samples[start..<min(start + windowSize, samples.count)])
            let windowed = applyWindow(window)
            
            var energy: Float = 0
            for sample in windowed {
                energy += abs(sample)
            }
            magnitudes.append(energy / Float(windowSize))
        }
        
        // Pad to expected size
        while magnitudes.count < 2048 {
            magnitudes.append(0)
        }
        
        return Array(magnitudes.prefix(2048))
    }
    
    private func applyWindow(_ samples: [Float]) -> [Float] {
        // Apply Hann window to reduce spectral leakage
        var windowed = samples
        let n = samples.count
        guard n > 0 else { return windowed }
        
        for i in 0..<n {
            let windowValue = Float(0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(n - 1))))
            windowed[i] = samples[i] * windowValue
        }
        return windowed
    }
    
    private func mapToChroma(fft: [Float], sampleRate: Double, fftSize: Int) -> [Float] {
        let numChromaBins = 12
        var chroma = [Float](repeating: 0, count: numChromaBins)

        // FFT returns magnitude spectrum with fftSize/2 bins (Nyquist limit)
        // So the actual FFT size is fftSize (the input size, which is power of 2)
        let binFreq = sampleRate / Double(fftSize)

        // Map frequency bins to chroma bins (C, C#, D, D#, E, F, F#, G, G#, A, A#, B)
        for (bin, magnitude) in fft.enumerated() {
            let freq = Double(bin) * binFreq

            // Only consider frequencies in musical range (100 Hz to 4000 Hz)
            // Narrowed range to focus on fundamental frequencies and lower harmonics
            guard freq >= 100 && freq <= 4000 else { continue }

            // Frequency weighting to emphasize most important range for key detection
            let weight: Float
            if freq < 200 {
                // Reduce bass weight (often ambiguous in harmony)
                weight = 0.2
            } else if freq < 1500 {
                // Full weight for fundamental and lower harmonics (most important for key detection)
                weight = 1.0
            } else if freq < 2500 {
                // Medium weight for mid-range harmonics
                weight = 0.7
            } else {
                // Reduce treble weight (higher harmonics, less important for key)
                weight = 0.3
            }

            // Convert frequency to MIDI note number
            // Formula: MIDI note = 12 * log2(freq / 440.0) + 69
            // A4 (440 Hz) = MIDI note 69
            let midiNote = 12.0 * log2(freq / 440.0) + 69.0

            // Get chroma bin (0-11) representing pitch class
            // 0 = C, 1 = C#, 2 = D, 3 = D#, 4 = E, 5 = F, 6 = F#, 7 = G, 8 = G#, 9 = A, 10 = A#, 11 = B
            // Handle negative values and ensure we get the correct pitch class
            let midiNoteRounded = Int(round(midiNote))
            let chromaBin = ((midiNoteRounded % 12) + 12) % 12

            // Add weighted magnitude to chroma bin (fold all octaves into same bin)
            chroma[chromaBin] += magnitude * weight
        }

        return chroma
    }
    
    private func matchKeyProfile(chromagram: [Float]) -> (key: Int?, mode: Int?, confidence: Double) {
        // Krumhansl-Schmuckler key profiles (normalized)
        // These represent the typical distribution of pitch classes in major/minor keys
        let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        
        // Normalize profiles
        func normalizeProfile(_ profile: [Float]) -> [Float] {
            var sumSquares: Float = 0
            for val in profile {
                sumSquares += val * val
            }
            let norm = sqrt(sumSquares)
            guard norm > 0 else { return profile }
            return profile.map { $0 / norm }
        }
        
        let normalizedMajor = normalizeProfile(majorProfile)
        let normalizedMinor = normalizeProfile(minorProfile)
        
        var bestKey: Int?
        var bestMode: Int?
        var bestScore: Float = -Float.infinity
        
        // Try all 24 keys (12 keys × 2 modes)
        for mode in 0...1 {
            let profile = mode == 0 ? normalizedMinor : normalizedMajor
            
            for key in 0..<12 {
                // Calculate correlation (dot product) between rotated chromagram and profile
                var score: Float = 0
                
                // Rotate chromagram to match key
                // Key 0 = C, Key 1 = C#, etc.
                for i in 0..<12 {
                    let rotatedIndex = (i + key) % 12
                    score += chromagram[rotatedIndex] * profile[i]
                }
                
                if score > bestScore {
                    bestScore = score
                    bestKey = key
                    bestMode = mode
                }
            }
        }
        
        // Normalize confidence (0.0 to 1.0)
        // Best score should be between -1 and 1 (correlation), map to 0-1
        let confidence = min(1.0, max(0.0, Double(bestScore + 1.0) / 2.0))
        
        return (bestKey, bestMode, confidence)
    }
    
    // MARK: - Errors
    
    enum AnalysisError: LocalizedError {
        case noAudioTrack
        case noAudioData
        case bufferCreationFailed
        case loadFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .noAudioTrack:
                return "No audio track found in file"
            case .noAudioData:
                return "No audio data could be extracted"
            case .bufferCreationFailed:
                return "Failed to create audio buffer"
            case .loadFailed(let error):
                return "Failed to load audio: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Helper Extensions

extension AudioFeatureAnalyzer {
    /// Batch analyze multiple files
    func analyzeAudioFiles(
        urls: [URL],
        maxConcurrent: Int = 2,
        progress: ((Int, Int, URL) -> Void)? = nil
    ) async -> [URL: AudioAnalysisResult] {
        var results: [URL: AudioAnalysisResult] = [:]
        var processed = 0
        
        await withTaskGroup(of: (URL, Result<AudioAnalysisResult, Error>).self) { group in
            var urlIndex = 0
            var activeTasks = 0
            
            while urlIndex < urls.count || activeTasks > 0 {
                // Start new tasks up to maxConcurrent
                while activeTasks < maxConcurrent && urlIndex < urls.count {
                    let url = urls[urlIndex]
                    urlIndex += 1
                    activeTasks += 1
                    
                    group.addTask {
                        do {
                            let result = try await self.analyzeAudioFile(at: url)
                            return (url, .success(result))
                        } catch {
                            return (url, .failure(error))
                        }
                    }
                }
                
                // Wait for one task to complete
                if let (url, result) = await group.next() {
                    activeTasks -= 1
                    processed += 1
                    
                    if case .success(let analysisResult) = result {
                        results[url] = analysisResult
                    }
                    
                    progress?(processed, urls.count, url)
                }
            }
        }
        
        return results
    }
}

