//
//  AudioFilterSettings.swift
//  HiFidelity
//
//  Audio filter and pitch control settings
//

import Foundation
import Combine

/// Filter type enumeration
enum AudioFilterType: String, Codable, CaseIterable {
    case none = "None"
    case lowPass = "Low-Pass"
    case highPass = "Hi-Pass"
    case bandPass = "Band-Pass"

    var displayName: String {
        return self.rawValue
    }
}

/// Settings for audio filters and pitch control
class AudioFilterSettings: ObservableObject {
    static let shared = AudioFilterSettings()

    private let defaults = UserDefaults.standard
    private var isLoadingSettings = false
    private var saveWorkItem: DispatchWorkItem?

    // MARK: - Filter Properties

    @Published var activeFilterType: AudioFilterType = .none {
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }

    // Separate frequency for each filter type (industry standard defaults)
    @Published var lowPassFrequency: Float = 20000.0 {  // 20 kHz - common for subtle high-end roll-off
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }

    @Published var highPassFrequency: Float = 100.0 {  // 100 Hz - common for removing low-end rumble
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }

    // Band-pass filter uses a frequency range
    @Published var bandPassLow: Float = 300.0 {  // 300 Hz - lower cutoff
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }

    @Published var bandPassHigh: Float = 3500.0 {  // 3.5 kHz - upper cutoff
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }

    // Filter slope (12dB or 24dB per octave)
    @Published var filterSlope: Int = 12 {  // 12 dB/octave (1-pole) or 24 dB/octave (2-pole)
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }

    // Helper to get current filter's frequency (for backward compatibility)
    var currentFilterFrequency: Float {
        switch activeFilterType {
        case .lowPass: return lowPassFrequency
        case .highPass: return highPassFrequency
        case .bandPass: return (bandPassLow + bandPassHigh) / 2.0  // Center frequency
        case .none: return 1000.0
        }
    }

    // Helper to get band-pass center frequency
    var bandPassCenter: Float {
        return (bandPassLow + bandPassHigh) / 2.0
    }

    // MARK: - Filter Gain Properties (for EQ-based filters)
    
    @Published var hpfGain: Float = 0.0 {
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }
    
    @Published var bpfGain: Float = 0.0 {
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }
    
    @Published var lpfGain: Float = 0.0 {
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }

    // MARK: - Pitch Properties

    @Published var pitchShift: Float = 0.0 {
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }

    @Published var pitchRange: Float = 8.0 {
        didSet { if !isLoadingSettings { saveSettingsDebounced() } }
    }

    // Settings keys
    enum SettingsKey: String {
        case activeFilterType = "audio.filter.type"
        case lowPassFrequency = "audio.filter.lowpass.frequency"
        case highPassFrequency = "audio.filter.highpass.frequency"
        case bandPassLow = "audio.filter.bandpass.low"
        case bandPassHigh = "audio.filter.bandpass.high"
        case filterSlope = "audio.filter.slope"
        case hpfGain = "audio.filter.hpf.gain"
        case bpfGain = "audio.filter.bpf.gain"
        case lpfGain = "audio.filter.lpf.gain"
        case pitchShift = "audio.pitch.shift"
        case pitchRange = "audio.pitch.range"
    }

    // MARK: - Initialization

    private init() {
        loadSettings()

        // CRITICAL: Always start with filters OFF on app launch
        // Filters should only be active when user explicitly enables them
        if activeFilterType != .none {
            Logger.warning("Filters were persisted as \(activeFilterType.rawValue) - resetting to .none on startup")
            isLoadingSettings = true
            activeFilterType = .none
            isLoadingSettings = false
            saveSettingsImmediate()
        }

        Logger.info("AudioFilterSettings initialized - filter: \(activeFilterType.rawValue)")
    }

    // MARK: - Persistence

    private func loadSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }

        // Load filter settings
        if let filterTypeString = defaults.string(forKey: SettingsKey.activeFilterType.rawValue),
           let filterType = AudioFilterType(rawValue: filterTypeString) {
            activeFilterType = filterType
        }

        lowPassFrequency = defaults.object(forKey: SettingsKey.lowPassFrequency.rawValue) as? Float ?? 20000.0
        highPassFrequency = defaults.object(forKey: SettingsKey.highPassFrequency.rawValue) as? Float ?? 100.0
        bandPassLow = defaults.object(forKey: SettingsKey.bandPassLow.rawValue) as? Float ?? 300.0
        bandPassHigh = defaults.object(forKey: SettingsKey.bandPassHigh.rawValue) as? Float ?? 3500.0
        filterSlope = defaults.object(forKey: SettingsKey.filterSlope.rawValue) as? Int ?? 12

        // Load filter gain settings
        hpfGain = defaults.object(forKey: SettingsKey.hpfGain.rawValue) as? Float ?? 0.0
        bpfGain = defaults.object(forKey: SettingsKey.bpfGain.rawValue) as? Float ?? 0.0
        lpfGain = defaults.object(forKey: SettingsKey.lpfGain.rawValue) as? Float ?? 0.0

        // Load pitch settings
        pitchShift = defaults.object(forKey: SettingsKey.pitchShift.rawValue) as? Float ?? 0.0
        pitchRange = defaults.object(forKey: SettingsKey.pitchRange.rawValue) as? Float ?? 8.0

        Logger.info("Loaded audio filter settings from UserDefaults")
        Logger.debug("Filter Type: \(activeFilterType.rawValue)")
        Logger.debug("LPF: \(lowPassFrequency) Hz, HPF: \(highPassFrequency) Hz, BPF: \(bandPassLow)-\(bandPassHigh) Hz, Slope: \(filterSlope)dB")
        Logger.debug("Filter Gains: HPF=\(hpfGain)dB, BPF=\(bpfGain)dB, LPF=\(lpfGain)dB")
        Logger.debug("Pitch Shift: \(pitchShift)%, Range: ±\(pitchRange)%")
    }

    /// Debounced save - delays saves during rapid changes (e.g., dragging sliders)
    private func saveSettingsDebounced() {
        // Cancel any pending save
        saveWorkItem?.cancel()

        // Create new work item
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveSettingsImmediate()
        }

        saveWorkItem = workItem

        // Execute after 0.5 seconds of no changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    /// Immediate save without debouncing
    private func saveSettingsImmediate() {
        defaults.set(activeFilterType.rawValue, forKey: SettingsKey.activeFilterType.rawValue)
        defaults.set(lowPassFrequency, forKey: SettingsKey.lowPassFrequency.rawValue)
        defaults.set(highPassFrequency, forKey: SettingsKey.highPassFrequency.rawValue)
        defaults.set(bandPassLow, forKey: SettingsKey.bandPassLow.rawValue)
        defaults.set(bandPassHigh, forKey: SettingsKey.bandPassHigh.rawValue)
        defaults.set(filterSlope, forKey: SettingsKey.filterSlope.rawValue)
        defaults.set(hpfGain, forKey: SettingsKey.hpfGain.rawValue)
        defaults.set(bpfGain, forKey: SettingsKey.bpfGain.rawValue)
        defaults.set(lpfGain, forKey: SettingsKey.lpfGain.rawValue)
        defaults.set(pitchShift, forKey: SettingsKey.pitchShift.rawValue)
        defaults.set(pitchRange, forKey: SettingsKey.pitchRange.rawValue)

        Logger.debug("Saved filter settings: \(activeFilterType.rawValue)")
    }

    func resetToDefaults() {
        isLoadingSettings = true

        activeFilterType = .none
        lowPassFrequency = 20000.0
        highPassFrequency = 100.0
        bandPassLow = 300.0
        bandPassHigh = 3500.0
        filterSlope = 12
        hpfGain = 0.0
        bpfGain = 0.0
        lpfGain = 0.0
        pitchShift = 0.0
        pitchRange = 8.0

        isLoadingSettings = false
        saveSettingsImmediate()

        Logger.info("Reset audio filter settings to defaults")
    }
}
