//
//  WaveformSeekBar.swift
//  HiFidelity
//
//  Interactive waveform visualization with seek control
//

import SwiftUI
import AVFoundation

/// Waveform seek bar that shows audio waveform and allows seeking
struct WaveformSeekBar: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared

    @State private var isDragging = false
    @State private var tempProgress: Double = 0
    @State private var waveformSamples: [Float] = []
    @State private var isLoadingWaveform = false
    @State private var displayProgress: Double = 0

    var isCompact: Bool = false
    var targetSampleCount: Int = 400

    var body: some View {
        Group {
            if playback.currentTrack != nil {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background (only for main player)
                        if !isCompact {
                            Rectangle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.1))
                                        .frame(height: 1),
                                    alignment: .top
                                )
                        }

                        // Waveform bars - stretch to fill full width
                        if !waveformSamples.isEmpty {
                            WaveformBars(
                                samples: waveformSamples,
                                progress: displayProgress,
                                width: geometry.size.width,
                                height: geometry.size.height,
                                primaryColor: theme.currentTheme.primaryColor
                            )
                        }

                        // Progress line (vertical white line)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: geometry.size.height)
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 0)
                            .offset(x: (geometry.size.width * displayProgress) - 1)
                            .opacity(0.9)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                tempProgress = progress
                                displayProgress = progress
                            }
                            .onEnded { value in
                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                playback.setProgress(progress)
                                displayProgress = progress
                                isDragging = false
                            }
                    )
                }
                .frame(height: isCompact ? 36 : 48)
            }
        }
        .onChange(of: playback.currentTrack) { _, newTrack in
            if let track = newTrack {
                loadWaveform(for: track)
            } else {
                waveformSamples = []
            }
        }
        .onAppear {
            if let track = playback.currentTrack {
                loadWaveform(for: track)
            }
            displayProgress = playback.progress
        }
        .task {
            while !Task.isCancelled {
                // Update at 60 FPS for ultra-smooth animation
                try? await Task.sleep(for: .milliseconds(16))
                if !isDragging {
                    let newProgress = playback.progress
                    // Always update for smooth seeking
                    if newProgress != displayProgress {
                        displayProgress = newProgress
                    }
                }
            }
        }
    }

    // MARK: - Waveform Loading

    private func loadWaveform(for track: Track) {
        guard !isLoadingWaveform else { return }
        guard let trackId = track.trackId else {
            Logger.error("Track has no database ID, cannot load waveform")
            isLoadingWaveform = false
            return
        }

        isLoadingWaveform = true

        // Use trackId (database ID) instead of id (ephemeral UUID) for cache key
        let cacheKey = String(trackId)

        // Try to load from cache first (always 400 samples)
        if let cached = WaveformCache.shared.getCachedWaveform(trackId: cacheKey) {
            // Downsample for mini player if needed
            let finalSamples = isCompact
                ? WaveformGenerator.downsample(samples: cached, to: targetSampleCount)
                : cached
            self.waveformSamples = finalSamples
            self.isLoadingWaveform = false
            return
        }

        // Cache miss - generate on demand (fallback for tracks not yet imported)
        Task(priority: .userInitiated) {
            let url = track.url

            do {
                // Always generate 400 samples for cache
                let samples = try await WaveformGenerator.generateWaveform(from: url, targetCount: 400)

                // Cache the generated waveform using trackId (database ID)
                WaveformCache.shared.cacheWaveform(trackId: cacheKey, samples: samples)

                await MainActor.run {
                    // Downsample for mini player if needed
                    let finalSamples = self.isCompact
                        ? WaveformGenerator.downsample(samples: samples, to: self.targetSampleCount)
                        : samples
                    self.waveformSamples = finalSamples
                    self.isLoadingWaveform = false
                }
            } catch {
                Logger.error("Failed to generate waveform: \(error.localizedDescription)")

                await MainActor.run {
                    self.waveformSamples = []
                    self.isLoadingWaveform = false
                }
            }
        }
    }

}

// MARK: - Waveform Bars Component

struct WaveformBars: View {
    let samples: [Float]
    let progress: Double
    let width: CGFloat
    let height: CGFloat
    let primaryColor: Color

    var body: some View {
        let barWidth = (width / CGFloat(samples.count)) - 1
        let progressBarIndex = Int(CGFloat(samples.count) * progress)

        HStack(alignment: .center, spacing: 1) {
            ForEach(0..<samples.count, id: \.self) { index in
                let amplitude = samples[index]
                let isPlayed = index < progressBarIndex

                RoundedRectangle(cornerRadius: 1)
                    .fill(isPlayed ? primaryColor.opacity(0.8) : Color.secondary.opacity(0.3))
                    .frame(width: max(1, barWidth))
                    .frame(height: max(2, CGFloat(amplitude) * height * 0.7))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        WaveformSeekBar()
            .frame(height: 48)
            .padding()
    }
    .frame(width: 600, height: 100)
}
