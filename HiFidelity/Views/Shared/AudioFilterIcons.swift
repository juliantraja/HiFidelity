//
//  AudioFilterIcons.swift
//  HiFidelity
//
//  Minimalist icons for audio filters
//

import SwiftUI

/// Low-Pass Filter Icon (frequency decreases as it goes right)
struct LowPassFilterIcon: View {
    var isActive: Bool = false
    var color: Color = .secondary

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            var path = Path()

            // Start from top-left
            path.move(to: CGPoint(x: 0, y: height * 0.2))

            // Flat line until cutoff point
            path.addLine(to: CGPoint(x: width * 0.6, y: height * 0.2))

            // Smooth curve down (low-pass characteristic)
            path.addQuadCurve(
                to: CGPoint(x: width, y: height * 0.9),
                control: CGPoint(x: width * 0.7, y: height * 0.2)
            )

            context.stroke(
                path,
                with: .color(isActive ? color : color.opacity(0.5)),
                lineWidth: 2.0
            )
        }
        .frame(width: 24, height: 18)
    }
}

/// High-Pass Filter Icon (horizontally mirrored Low-Pass)
struct HighPassFilterIcon: View {
    var isActive: Bool = false
    var color: Color = .secondary

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            var path = Path()

            // Mirrored version of LPF:
            // LPF: starts top-left with flat line, then curves down
            // HPF: starts top-right with flat line, then curves down (reversed)

            // Start from top-right (mirrored from LPF's top-left)
            path.move(to: CGPoint(x: width, y: height * 0.2))

            // Flat line to curve start point
            path.addLine(to: CGPoint(x: width * 0.4, y: height * 0.2))

            // Smooth curve down (mirrored control point)
            path.addQuadCurve(
                to: CGPoint(x: 0, y: height * 0.9),
                control: CGPoint(x: width * 0.3, y: height * 0.2)
            )

            context.stroke(
                path,
                with: .color(isActive ? color : color.opacity(0.5)),
                lineWidth: 2.0
            )
        }
        .frame(width: 24, height: 18)
    }
}

/// Band-Pass Filter Icon (symmetric peak with rounded top)
struct BandPassFilterIcon: View {
    var isActive: Bool = false
    var color: Color = .secondary

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            var path = Path()

            // Start from bottom-left
            path.move(to: CGPoint(x: 0, y: height * 0.9))

            // Curve up to peak with smooth, symmetric control points
            path.addQuadCurve(
                to: CGPoint(x: width * 0.5, y: height * 0.15),
                control: CGPoint(x: width * 0.2, y: height * 0.15)
            )

            // Curve down from peak symmetrically
            path.addQuadCurve(
                to: CGPoint(x: width, y: height * 0.9),
                control: CGPoint(x: width * 0.8, y: height * 0.15)
            )

            context.stroke(
                path,
                with: .color(isActive ? color : color.opacity(0.5)),
                lineWidth: 2.0
            )
        }
        .frame(width: 24, height: 18)
    }
}

/// Filter Button combining icon, label, and toggle functionality
struct FilterButton: View {
    let filterType: AudioFilterType
    @Binding var activeFilterType: AudioFilterType
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var effectsManager = AudioEffectsManager.shared
    @ObservedObject var filterSettings = AudioFilterSettings.shared
    @State private var isHovered = false

    var isActive: Bool {
        activeFilterType == filterType
    }

    var filterLabel: String {
        switch filterType {
        case .lowPass: return "LPF"
        case .highPass: return "HPF"
        case .bandPass: return "BPF"
        case .none: return ""
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            // Label
            Text(filterLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isActive ? theme.currentTheme.primaryColor : .secondary)
                .frame(minWidth: 32)
                .fixedSize()

            // Button with icon
            Button {
                let clickTime = Date()

                // INSTANT filter application - bypass SwiftUI onChange chain
                let newFilterType: AudioFilterType = (activeFilterType == filterType) ? .none : filterType

                // Apply filter SYNCHRONOUSLY on MAIN thread for absolute minimum latency
                // Audio processing is <0.1ms so won't block UI
                if newFilterType == .bandPass {
                    effectsManager.applyBandPassFilter(
                        low: filterSettings.bandPassLow,
                        high: filterSettings.bandPassHigh,
                        slope: filterSettings.filterSlope
                    )
                } else {
                    effectsManager.applyFilter(
                        newFilterType,
                        frequency: filterSettings.currentFilterFrequency,
                        slope: filterSettings.filterSlope
                    )
                }

                let applyTime = Date().timeIntervalSince(clickTime) * 1000.0
                Logger.debug("Filter applied in \(String(format: "%.2f", applyTime))ms")

                // Update state LAST (triggers @Published propagation)
                activeFilterType = newFilterType
            } label: {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
                        .frame(width: 32, height: 32)

                    // Icon
                    filterIcon
                        .scaleEffect(isHovered ? 1.05 : 1.0)  // Smaller scale = faster animation
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                // No animation on hover to eliminate any UI delay
                isHovered = hovering
            }
        }
        .frame(minWidth: 36)
    }

    @ViewBuilder
    private var filterIcon: some View {
        let color = isActive ? theme.currentTheme.primaryColor : .secondary

        switch filterType {
        case .lowPass:
            LowPassFilterIcon(isActive: isActive, color: color)
        case .highPass:
            HighPassFilterIcon(isActive: isActive, color: color)
        case .bandPass:
            BandPassFilterIcon(isActive: isActive, color: color)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("Low-Pass Filter") {
    VStack(spacing: 20) {
        LowPassFilterIcon(isActive: false)
        LowPassFilterIcon(isActive: true, color: .blue)
    }
    .padding()
}

#Preview("High-Pass Filter") {
    VStack(spacing: 20) {
        HighPassFilterIcon(isActive: false)
        HighPassFilterIcon(isActive: true, color: .blue)
    }
    .padding()
}

#Preview("Band-Pass Filter") {
    VStack(spacing: 20) {
        BandPassFilterIcon(isActive: false)
        BandPassFilterIcon(isActive: true, color: .blue)
    }
    .padding()
}

#Preview("All Filters") {
    HStack(spacing: 16) {
        HighPassFilterIcon(isActive: true, color: .blue)
        BandPassFilterIcon(isActive: true, color: .blue)
        LowPassFilterIcon(isActive: true, color: .blue)
    }
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
