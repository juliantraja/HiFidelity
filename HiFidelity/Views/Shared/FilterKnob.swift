//
//  FilterKnob.swift
//
//  Rotary knob for filter control (HPF, BPF, LPF)
//  Range: -12dB to +12dB
//  Visual range: 180° total (±90° from 12 o'clock)
//

import SwiftUI

/// Rotary knob for filter gain control
/// Range: -12dB to +12dB
/// Visual range: 180° total (±90° from 12 o'clock)
struct FilterKnob: View {
    @Binding var gainDB: Float
    let label: String
    @ObservedObject var theme = AppTheme.shared

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartY: CGFloat = 0
    @State private var dragStartValue: Float = 0

    private let knobSize: CGFloat = 35
    private let maxRange: Float = 12.0  // ±12dB

    // Convert gain dB to rotation angle (in degrees)
    private var rotationAngle: Double {
        // Map from -maxRange...+maxRange to -140...+140 degrees
        let normalized = Double(gainDB / maxRange)
        return normalized * 140.0
    }

    // Convert rotation angle to gain dB
    private func angleToGain(_ angle: Double) -> Float {
        let normalized = angle / 140.0
        return Float(normalized * Double(maxRange))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Outer circle (track/background)
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 2)
                    .frame(width: knobSize, height: knobSize)

                // Active arc (shows current position)
                if abs(gainDB) >= 0.05 {
                    Circle()
                        .trim(from: 0, to: activeArcEnd)
                        .rotation(.degrees(rotationAngle >= 0 ? -90 : -90 - abs(rotationAngle)))
                        .stroke(
                            theme.currentTheme.primaryColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: knobSize - 4, height: knobSize - 4)
                }

                // Inner circle (knob body)
                Circle()
                    .fill(
                        isDragging ? theme.currentTheme.primaryColor.opacity(0.15) :
                        isHovered ? Color(nsColor: .controlBackgroundColor) :
                        Color(nsColor: .windowBackgroundColor)
                    )
                    .frame(width: knobSize - 8, height: knobSize - 8)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                // Indicator line (from center to edge)
                Rectangle()
                    .fill(abs(gainDB) < 0.05 ? Color.secondary : theme.currentTheme.primaryColor)
                    .frame(width: 2, height: knobSize / 2 - 6)
                    .offset(y: -(knobSize / 4 - 3))
                    .rotationEffect(.degrees(rotationAngle))
            }
            .frame(width: knobSize, height: knobSize)
            .contentShape(Circle())
            .gesture(dragGesture)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .onTapGesture(count: 2) {
                // Double-click to reset to exactly 0
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    gainDB = 0.0
                }
            }
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            gainDB = 0.0
                        }
                    }
            )

            // Value display - fixed width to prevent layout shifts
            // Width: 50 points (accommodates "-12.0 dB" text)
            // Fixed size ensures text doesn't scale based on value length
            Text(gainValueString)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(gainDB == 0 ? .secondary : theme.currentTheme.primaryColor)
                .frame(width: 50, height: 14, alignment: .center)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
                .baselineOffset(0)
                .minimumScaleFactor(1.0)
        }
        .frame(width: 50)
    }

    // Active arc end position (0.0 to 1.0, representing 0° to 360°)
    private var activeArcEnd: Double {
        // Only show arc if gain is not at zero
        guard abs(gainDB) >= 0.05 else { return 0 }

        // Map from -140...+140 degrees to arc position
        let currentAngle = rotationAngle  // Current rotation

        // For positive values: arc goes clockwise from 12 o'clock
        // For negative values: arc goes counter-clockwise from 12 o'clock
        if currentAngle >= 0 {
            // Positive: 0° to currentAngle (clockwise)
            return abs(currentAngle) / 360.0
        } else {
            // Negative: we'll handle this with rotation in the arc itself
            return abs(currentAngle) / 360.0
        }
    }

    // Format gain value as string
    private var gainValueString: String {
        if abs(gainDB) < 0.05 {  // Treat very small values as 0
            return "0.0 dB"
        } else if gainDB > 0 {
            return "+\(String(format: "%.1f", gainDB)) dB"
        } else {
            return "\(String(format: "%.1f", gainDB)) dB"  // Negative values already include "-"
        }
    }

    // Drag gesture for rotation
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartY = value.startLocation.y
                    dragStartValue = gainDB
                }

                // Calculate vertical drag distance
                let dragDistance = dragStartY - value.location.y

                // Sensitivity: 100 points of drag = full range (280° total)
                let sensitivity: CGFloat = 280.0 / 100.0
                let angleChange = dragDistance * sensitivity

                // Calculate new angle
                let startAngle = Double(dragStartValue / maxRange) * 140.0
                let newAngle = startAngle + angleChange
                let clampedAngle = max(-140.0, min(140.0, newAngle))

                // Convert back to gain dB
                let newGain = angleToGain(clampedAngle)

                withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                    gainDB = newGain
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isDragging = false
                    // Snap to 0 if very close
                    if abs(gainDB) < 0.3 {
                        gainDB = 0.0
                    }
                }
            }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        FilterKnob(
            gainDB: .constant(0),
            label: "HPF"
        )

        FilterKnob(
            gainDB: .constant(6.0),
            label: "BPF"
        )

        FilterKnob(
            gainDB: .constant(-6.0),
            label: "LPF"
        )
    }
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

