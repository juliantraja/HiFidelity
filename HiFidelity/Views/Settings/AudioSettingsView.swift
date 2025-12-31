//
//  AudioSettingsView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 15/11/25.
//

import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject var settings = AudioSettings.shared
    @ObservedObject var effectsManager = AudioEffectsManager.shared
    @ObservedObject var replayGainSettings = ReplayGainSettings.shared
    @ObservedObject var r128Scanner = R128LoudnessScanner.shared
    @ObservedObject private var filterSettings = AudioFilterSettings.shared
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Output Device
            outputDeviceSection
            
            Divider()

            // Audio Effects
            audioEffectsSection
            
            Divider()
            
            // ReplayGain
            replayGainSection
            
            Divider()
            
            // Audio Quality
            audioQualitySection
            
            Divider()

            // Analogue Pitch Range
            analoguePitchSection

            Divider()

            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                    replayGainSettings.resetToDefaults()
                    AudioFilterSettings.shared.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Settings Sections
    
    private var outputDeviceSection: some View {
        VStack(spacing: 0) {
            // Header row (no toggle, just info)
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "speaker.wave.3")
                    .font(.system(size: 16))
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .frame(width: 24)
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output Device")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Configure audio output settings")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Device settings content
            deviceSettings
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private var audioEffectsSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .frame(width: 24)
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Effects")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Configure audio effects and processing")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Effects settings content
            effectsSettings
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private var replayGainSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16))
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .frame(width: 24)
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text("ReplayGain")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Normalize volume across tracks")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // ReplayGain settings content
            replayGainSettingsView
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private var audioQualitySection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .frame(width: 24)
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Quality")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Configure audio buffer and quality settings")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Quality settings content
            qualitySettings
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private var analoguePitchSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "dial.medium")
                    .font(.system(size: 16))
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .frame(width: 24)
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analogue Pitch Range")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Configure pitch control range")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Pitch settings content
            analoguePitchSettings
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private var effectsSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reverb Toggle - align toggle with LibrarySettings pattern
            HStack(spacing: 12) {
                // No icon for sub-items, but maintain spacing
                Color.clear
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reverb")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Add spatial depth and ambience to audio")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { effectsManager.isReverbEnabled },
                    set: { effectsManager.setReverbEnabled($0) }
                ))
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Reverb Mix
            if effectsManager.isReverbEnabled {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    // Maintain icon spacing alignment
                    Color.clear
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reverb Mix")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Amount of reverb effect to apply")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(effectsManager.reverbMix) },
                            set: { effectsManager.setReverbMix(Float($0)) }
                        ), in: -96...0, step: 1)
                        .frame(width: 150)
                        
                        Text("\(Int(effectsManager.reverbMix)) dB")
                            .frame(width: 60, alignment: .trailing)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
    
    private var replayGainSettingsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ReplayGain Toggle - align toggle with LibrarySettings pattern
            HStack(spacing: 12) {
                // No icon for sub-items, but maintain spacing
                Color.clear
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable ReplayGain")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Automatically normalize volume across tracks")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $replayGainSettings.isEnabled)
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Mode & Source Pickers
            if replayGainSettings.isEnabled {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    // Maintain icon spacing alignment
                    Color.clear
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mode")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(replayGainSettings.mode.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $replayGainSettings.mode) {
                        ForEach(ReplayGainMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .frame(width: 150)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Divider()
                    .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    // Maintain icon spacing alignment
                    Color.clear
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Source")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(replayGainSettings.source.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $replayGainSettings.source) {
                        ForEach(LoudnessSource.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .frame(width: 220)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Divider()
                    .padding(.vertical, 4)
                
                Divider()
                    .padding(.vertical, 4)
                
                // R128 Loudness Analysis
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        // Maintain icon spacing alignment
                        Color.clear
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Loudness Analysis")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Scan your library to calculate EBU R128 loudness for accurate normalization")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if r128Scanner.isScanning {
                            Button("Cancel") {
                                r128Scanner.cancelScan()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Scan Library") {
                                r128Scanner.scanLibrary()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    // Progress indicator
                    if r128Scanner.isScanning {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ProgressView(value: r128Scanner.progress)
                                    .frame(maxWidth: .infinity)
                                
                                Text("\(r128Scanner.scannedCount)/\(r128Scanner.totalCount)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            
                            if let currentTrack = r128Scanner.currentTrack {
                                Text("Analyzing: \(currentTrack.title)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    private var qualitySettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Buffer Length - align with LibrarySettings pattern
            HStack(spacing: 12) {
                // No icon for sub-items, but maintain spacing
                Color.clear
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Buffer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Larger buffer = more stable, but higher latency")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    TickMarkSlider(
                        value: Binding(
                            get: { Double(settings.bufferLength) },
                            set: { settings.bufferLength = Int($0) }
                        ),
                        range: 50...2000,
                        step: 50
                    )
                    .frame(width: 150)

                    Text("\(settings.bufferLength) ms")
                        .frame(width: 70, alignment: .trailing)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    private var audioFilterSettings: some View {
        VStack(alignment: .leading, spacing: 20) {

            HStack(alignment: .top, spacing: 20) {
                // High-Pass Filter Curve
                InteractiveFilterCurve(
                    filterType: .highPass,
                    frequency: Binding(
                        get: { filterSettings.highPassFrequency },
                        set: { newValue in
                            filterSettings.highPassFrequency = newValue
                            // Real-time update if HPF is active
                            if filterSettings.activeFilterType == .highPass {
                                effectsManager.applyFilter(.highPass, frequency: newValue, slope: filterSettings.filterSlope)
                            }
                        }
                    ),
                    minFrequency: 20,
                    maxFrequency: 500,
                    label: "High-Pass Filter",
                    slope: filterSettings.filterSlope
                )

                // Low-Pass Filter Curve
                InteractiveFilterCurve(
                    filterType: .lowPass,
                    frequency: Binding(
                        get: { filterSettings.lowPassFrequency },
                        set: { newValue in
                            filterSettings.lowPassFrequency = newValue
                            // Real-time update if LPF is active
                            if filterSettings.activeFilterType == .lowPass {
                                effectsManager.applyFilter(.lowPass, frequency: newValue, slope: filterSettings.filterSlope)
                            }
                        }
                    ),
                    minFrequency: 20,
                    maxFrequency: 20000,
                    label: "Low-Pass Filter",
                    slope: filterSettings.filterSlope
                )
            }

            // Band-Pass Filter Curve
            InteractiveBandPassCurve(
                lowFrequency: Binding(
                    get: { filterSettings.bandPassLow },
                    set: { newValue in
                        filterSettings.bandPassLow = newValue
                        // Real-time update if BPF is active
                        if filterSettings.activeFilterType == .bandPass {
                            effectsManager.applyBandPassFilter(
                                low: newValue,
                                high: filterSettings.bandPassHigh,
                                slope: filterSettings.filterSlope
                            )
                        }
                    }
                ),
                highFrequency: Binding(
                    get: { filterSettings.bandPassHigh },
                    set: { newValue in
                        filterSettings.bandPassHigh = newValue
                        // Real-time update if BPF is active
                        if filterSettings.activeFilterType == .bandPass {
                            effectsManager.applyBandPassFilter(
                                low: filterSettings.bandPassLow,
                                high: newValue,
                                slope: filterSettings.filterSlope
                            )
                        }
                    }
                ),
                minFrequency: 100,
                maxFrequency: 10000,
                label: "Band-Pass Filter",
                slope: filterSettings.filterSlope
            )
            
            // Filter Slope
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Filter Slope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Steepness of filter roll-off (12dB, 24dB, or 48dB per octave)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("", selection: $filterSettings.filterSlope) {
                    Text("12 dB/octave").tag(12)
                    Text("24 dB/octave").tag(24)
                    Text("48 dB/octave").tag(48)
                }
                .frame(width: 150)
                .onChange(of: filterSettings.filterSlope) { _, newValue in
                    // Real-time update if any filter is active
                    if filterSettings.activeFilterType != .none {
                        if filterSettings.activeFilterType == .bandPass {
                            effectsManager.applyBandPassFilter(
                                low: filterSettings.bandPassLow,
                                high: filterSettings.bandPassHigh,
                                slope: newValue
                            )
                        } else {
                            effectsManager.applyFilter(
                                filterSettings.activeFilterType,
                                frequency: filterSettings.currentFilterFrequency,
                                slope: newValue
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                Text("Apply filters from the Queue panel. Each filter type has its own frequency setting for precise control.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var analoguePitchSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pitch Range - align with LibrarySettings pattern
            HStack(spacing: 12) {
                // No icon for sub-items, but maintain spacing
                Color.clear
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pitch Range")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Maximum pitch shift range (±percentage)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    TickMarkSlider(
                        value: Binding(
                            get: { Double(AudioFilterSettings.shared.pitchRange) },
                            set: { AudioFilterSettings.shared.pitchRange = Float($0) }
                        ),
                        range: 1...16,
                        step: 0.5
                    )
                    .frame(width: 150)

                    Text("±\(String(format: "%.1f", AudioFilterSettings.shared.pitchRange))%")
                        .frame(width: 70, alignment: .trailing)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                // Maintain icon spacing alignment
                Color.clear
                    .frame(width: 24)
                
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    Text("Analogue pitch control changes both speed and pitch like vinyl turntable. Adjust from the Queue panel using the pitch knob. Double-click to reset.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var deviceSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Synchronize Sample Rate - align toggle with LibrarySettings pattern
            HStack(spacing: 12) {
                // No icon for sub-items, but maintain spacing
                Color.clear
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synchronize Sample Rate with Music Player (Hog mode)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Enable exclusive audio access for bit-perfect playback")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $settings.synchronizeSampleRate)
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Info text when enabled
            if settings.synchronizeSampleRate {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    // Maintain icon spacing alignment
                    Color.clear
                        .frame(width: 24)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))

                        Text("When enabled, the app takes exclusive control (hog mode) of your audio device and automatically switches the device sample rate to match each track (44.1kHz, 48kHz, 96kHz, etc.) preventing BASS from resampling for true bit-perfect playback.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
    
}

#Preview {
    AudioSettingsView()
        .frame(width: 700, height: 600)
}

// MARK: - Tick Mark Slider

/// Custom slider with tick marks along the track
struct TickMarkSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                // All elements centered at y: 10 (center of 20pt frame)
                let centerY: CGFloat = geometry.size.height / 2 // 10.0
                
                // Track background (dark gray) - 4pt high, centered at y: 10
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor).opacity(0.3))
                    .frame(height: 4)
                    .position(x: geometry.size.width / 2, y: centerY)
                
                // Tick marks (light gray, evenly spaced) - 6pt high, centered at y: 10
                ForEach(0..<numberOfTicks, id: \.self) { index in
                    let tickPosition = CGFloat(index) / CGFloat(max(1, numberOfTicks - 1)) * geometry.size.width
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 1, height: 6)
                        .position(x: tickPosition, y: centerY)
                }
                
                // Custom oval thumb (light gray) - 20pt high, centered at y: 10
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: 12, height: 20)
                    .position(x: thumbPosition(for: geometry.size.width) + 6, y: centerY) // +6 to account for half thumb width
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                isDragging = true
                                let newValue = positionToValue(gesture.location.x, width: geometry.size.width)
                                value = newValue
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                
                // Invisible native slider for accessibility and step snapping
                Slider(value: $value, in: range, step: step)
                    .opacity(0.01)
            }
        }
        .frame(height: 20)
    }
    
    private var numberOfTicks: Int {
        // Create many evenly spaced ticks (approximately every 50ms)
        let rangeSize = range.upperBound - range.lowerBound
        let steps = Int(rangeSize / step)
        return min(steps + 1, 40) // Limit to 40 ticks max for visual clarity
    }
    
    private func thumbPosition(for width: CGFloat) -> CGFloat {
        let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let position = normalizedValue * width
        // Position thumb center on track
        return position - 6 // Half of thumb width (12/2)
    }
    
    private func positionToValue(_ x: CGFloat, width: CGFloat) -> Double {
        let clampedX = max(0, min(width, x))
        let normalized = clampedX / width
        let rawValue = range.lowerBound + (normalized * (range.upperBound - range.lowerBound))
        // Snap to step
        let steppedValue = round(rawValue / step) * step
        return max(range.lowerBound, min(range.upperBound, steppedValue))
    }
}
