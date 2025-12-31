//
//  WaveformGenerator.swift
//  HiFidelity
//
//  Shared utility for generating audio waveforms
//

import Foundation
import AVFoundation

/// Shared utility for generating audio waveforms from audio files
class WaveformGenerator {

    // MARK: - Public API

    /// Generate waveform samples from an audio file
    /// - Parameters:
    ///   - url: URL of the audio file
    ///   - targetCount: Number of samples to generate (default: 400)
    /// - Returns: Array of normalized amplitude values (0.0 to 1.0)
    static func generateWaveform(from url: URL, targetCount: Int = 400) async throws -> [Float] {
        let asset = AVURLAsset(url: url)

        guard let assetTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: assetTrack, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.readerFailed
        }

        var audioSamples: [Float] = []

        while reader.status == .reading {
            if let sampleBuffer = output.copyNextSampleBuffer() {
                if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    var data = Data(count: length)

                    let copyResult = data.withUnsafeMutableBytes { bytes -> OSStatus in
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
                    }

                    guard copyResult == noErr else { continue }

                    let int16Samples = data.withUnsafeBytes { bytes in
                        Array(bytes.bindMemory(to: Int16.self))
                    }

                    let floatSamples = int16Samples.map { Float($0) / Float(Int16.max) }
                    audioSamples.append(contentsOf: floatSamples)
                }
            }
        }

        return downsampleToAmplitudes(samples: audioSamples, targetCount: targetCount)
    }

    /// Downsample an array of samples to a target count
    /// - Parameters:
    ///   - samples: Source samples to downsample
    ///   - targetCount: Target number of samples
    /// - Returns: Downsampled array of normalized amplitude values
    static func downsample(samples: [Float], to targetCount: Int) -> [Float] {
        return downsampleToAmplitudes(samples: samples, targetCount: targetCount)
    }

    // MARK: - Private Helpers

    private static func downsampleToAmplitudes(samples: [Float], targetCount: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard targetCount > 0 else { return [] }

        // If we have fewer samples than target, just return what we have
        guard samples.count >= targetCount else {
            // Pad with zeros if needed
            var result = samples
            result.append(contentsOf: Array(repeating: 0, count: targetCount - samples.count))
            return result
        }

        var amplitudes: [Float] = []
        amplitudes.reserveCapacity(targetCount)

        let step = Double(samples.count) / Double(targetCount)

        for i in 0..<targetCount {
            let startIndex = Int(Double(i) * step)
            let endIndex = Int(Double(i + 1) * step)

            // Ensure we don't go out of bounds
            let safeEndIndex = min(endIndex, samples.count)

            guard startIndex < safeEndIndex else {
                amplitudes.append(0)
                continue
            }

            let binSamples = samples[startIndex..<safeEndIndex]
            let sumOfSquares = binSamples.reduce(0) { $0 + ($1 * $1) }
            let rms = sqrt(sumOfSquares / Float(binSamples.count))

            amplitudes.append(rms)
        }

        // Normalize to 0-1 range
        if let maxAmplitude = amplitudes.max(), maxAmplitude > 0 {
            amplitudes = amplitudes.map { $0 / maxAmplitude }
        }

        return amplitudes
    }
}

// MARK: - Errors

enum WaveformError: Error {
    case noAudioTrack
    case readerFailed
}
