//
//  InteractiveFilterCurve.swift
//  HiFidelity
//
//  Interactive filter curve visualization with drag-to-adjust frequency
//

import SwiftUI

enum FilterCurveType {
    case lowPass
    case highPass
    case bandPass
}

struct InteractiveFilterCurve: View {
    let filterType: FilterCurveType
    @Binding var frequency: Float
    let minFrequency: Float
    let maxFrequency: Float
    let label: String
    let slope: Int  // 12 or 24 dB/octave

    @State private var isDragging = false
    @State private var dragStartX: CGFloat = 0
    @State private var dragStartFrequency: Float = 0

    private let curveWidth: CGFloat = 200
    private let curveHeight: CGFloat = 80

    // Slope steepness factor
    private var slopeFactor: Double {
        switch slope {
        case 48: return 6.0  // Very steep
        case 24: return 3.0  // Steep
        default: return 1.5  // Gentle (12dB)
        }
    }

    // Convert frequency to X position (0 to 1)
    private var normalizedPosition: Double {
        // Use logarithmic scale for frequency
        let logMin = log10(Double(minFrequency))
        let logMax = log10(Double(maxFrequency))
        let logFreq = log10(Double(frequency))
        return (logFreq - logMin) / (logMax - logMin)
    }

    // Convert X position (0 to 1) to frequency
    private func positionToFrequency(_ position: Double) -> Float {
        let logMin = log10(Double(minFrequency))
        let logMax = log10(Double(maxFrequency))
        let logFreq = logMin + position * (logMax - logMin)
        return Float(pow(10, logFreq))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: curveWidth, height: curveHeight)

                // Grid lines
                Canvas { context, size in
                    let path = Path { path in
                        // Horizontal center line
                        path.move(to: CGPoint(x: 0, y: size.height / 2))
                        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    }
                    context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                }
                .frame(width: curveWidth, height: curveHeight)

                // Filter curve
                Canvas { context, size in
                    let path = createFilterPath(size: size)

                    // Fill under curve
                    var fillPath = path
                    fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                    fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                    fillPath.closeSubpath()

                    context.fill(fillPath, with: .color(Color.accentColor.opacity(isDragging ? 0.3 : 0.2)))
                    context.stroke(path, with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                .frame(width: curveWidth, height: curveHeight)

                // Draggable area indicator
                if isDragging {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: curveWidth, height: curveHeight)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            // Frequency display
            Text(formatFrequency(frequency))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func createFilterPath(size: CGSize) -> Path {
        var path = Path()
        let steps = 200

        switch filterType {
        case .lowPass:
            // Low-pass: flat until cutoff, then smooth S-curve drop
            let cutoffX = CGFloat(normalizedPosition) * size.width
            let transitionWidth = size.width * 0.4 / slopeFactor

            for i in 0...steps {
                let x = CGFloat(i) / CGFloat(steps) * size.width
                let distFromCutoff = x - cutoffX
                let y: CGFloat

                if distFromCutoff < 0 {
                    // Pass band - flat at top
                    y = size.height * 0.1
                } else if distFromCutoff < transitionWidth {
                    // Smooth S-curve transition
                    let t = distFromCutoff / transitionWidth
                    let smoothT = (1 - cos(t * .pi)) / 2
                    y = size.height * 0.1 + smoothT * size.height * 0.8
                } else {
                    // Stop band - flat at bottom
                    y = size.height * 0.9
                }

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

        case .highPass:
            // High-pass: smooth S-curve rise, then flat
            let cutoffX = CGFloat(normalizedPosition) * size.width
            let transitionWidth = size.width * 0.4 / slopeFactor

            for i in 0...steps {
                let x = CGFloat(i) / CGFloat(steps) * size.width
                let distFromCutoff = x - cutoffX
                let y: CGFloat

                if distFromCutoff > 0 {
                    // Pass band - flat at top
                    y = size.height * 0.1
                } else if distFromCutoff > -transitionWidth {
                    // Smooth S-curve transition
                    let t = (distFromCutoff + transitionWidth) / transitionWidth
                    let smoothT = (1 - cos(t * .pi)) / 2
                    y = size.height * 0.9 - smoothT * size.height * 0.8
                } else {
                    // Stop band - flat at bottom
                    y = size.height * 0.9
                }

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

        case .bandPass:
            // Band-pass: peak at center frequency
            let centerX = CGFloat(normalizedPosition) * size.width
            let bandwidth = size.width * 0.2 // Width of the pass band

            for i in 0...steps {
                let x = CGFloat(i) / CGFloat(steps) * size.width
                let distance = abs(x - centerX)

                // Gaussian-like curve
                let y = size.height * 0.15 + (size.height * 0.7) * exp(-pow(distance / bandwidth, 2))

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }

        return path
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartX = value.startLocation.x
                    dragStartFrequency = frequency
                    NSCursor.closedHand.push()
                }

                // Calculate new position based on drag
                let dragDistance = value.location.x - dragStartX
                let positionChange = Double(dragDistance / curveWidth)

                // Calculate starting position
                let logMin = log10(Double(minFrequency))
                let logMax = log10(Double(maxFrequency))
                let logStartFreq = log10(Double(dragStartFrequency))
                let startPosition = (logStartFreq - logMin) / (logMax - logMin)

                // New position
                let newPosition = max(0, min(1, startPosition + positionChange))
                let newFrequency = positionToFrequency(newPosition)

                frequency = max(minFrequency, min(maxFrequency, newFrequency))
            }
            .onEnded { _ in
                isDragging = false
                NSCursor.pop()
            }
    }

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1f kHz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }
}

// Dual-range band-pass filter curve
struct InteractiveBandPassCurve: View {
    @Binding var lowFrequency: Float
    @Binding var highFrequency: Float
    let minFrequency: Float
    let maxFrequency: Float
    let label: String
    let slope: Int  // 12 or 24 dB/octave

    @State private var isDraggingLow = false
    @State private var isDraggingHigh = false
    @State private var dragStartX: CGFloat = 0
    @State private var dragStartFrequency: Float = 0
    @State private var activeEdge: Edge? = nil

    private let curveWidth: CGFloat = 200
    private let curveHeight: CGFloat = 80

    enum Edge {
        case low, high
    }

    // Slope steepness factor
    private var slopeFactor: Double {
        switch slope {
        case 48: return 6.0  // Very steep
        case 24: return 3.0  // Steep
        default: return 1.5  // Gentle (12dB)
        }
    }

    // Convert frequency to X position (0 to 1)
    private func normalizedPosition(for frequency: Float) -> Double {
        let logMin = log10(Double(minFrequency))
        let logMax = log10(Double(maxFrequency))
        let logFreq = log10(Double(frequency))
        return (logFreq - logMin) / (logMax - logMin)
    }

    // Convert X position (0 to 1) to frequency
    private func positionToFrequency(_ position: Double) -> Float {
        let logMin = log10(Double(minFrequency))
        let logMax = log10(Double(maxFrequency))
        let logFreq = logMin + position * (logMax - logMin)
        return Float(pow(10, logFreq))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: curveWidth, height: curveHeight)

                // Grid lines
                Canvas { context, size in
                    let path = Path { path in
                        // Horizontal center line
                        path.move(to: CGPoint(x: 0, y: size.height / 2))
                        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    }
                    context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                }
                .frame(width: curveWidth, height: curveHeight)

                // Filter curve
                Canvas { context, size in
                    let path = createBandPassPath(size: size)

                    // Fill under curve
                    var fillPath = path
                    fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                    fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                    fillPath.closeSubpath()

                    context.fill(fillPath, with: .color(Color.accentColor.opacity((isDraggingLow || isDraggingHigh) ? 0.3 : 0.2)))
                    context.stroke(path, with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                .frame(width: curveWidth, height: curveHeight)


                // Draggable area indicator
                if isDraggingLow || isDraggingHigh {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: curveWidth, height: curveHeight)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            // Frequency display
            HStack(spacing: 12) {
                Text("Low: \(formatFrequency(lowFrequency))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isDraggingLow ? .accentColor : .secondary)

                Text("High: \(formatFrequency(highFrequency))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isDraggingHigh ? .accentColor : .secondary)
            }
        }
    }

    private func createBandPassPath(size: CGSize) -> Path {
        var path = Path()
        let steps = 200

        let lowX = CGFloat(normalizedPosition(for: lowFrequency)) * size.width
        let highX = CGFloat(normalizedPosition(for: highFrequency)) * size.width
        let transitionWidth = size.width * 0.4 / slopeFactor

        for i in 0...steps {
            let x = CGFloat(i) / CGFloat(steps) * size.width
            let y: CGFloat

            // Calculate distance from each cutoff
            let distFromLow = x - lowX
            let distFromHigh = x - highX

            if distFromLow < 0 {
                // Left side - before low cutoff
                if distFromLow < -transitionWidth {
                    // Stop band - flat at bottom
                    y = size.height * 0.9
                } else {
                    // Smooth S-curve rise to passband
                    let t = (distFromLow + transitionWidth) / transitionWidth
                    let smoothT = (1 - cos(t * .pi)) / 2
                    y = size.height * 0.9 - smoothT * size.height * 0.8
                }
            } else if distFromHigh < 0 {
                // Pass band - between low and high cutoffs, flat at top
                y = size.height * 0.1
            } else if distFromHigh < transitionWidth {
                // Smooth S-curve drop from passband
                let t = distFromHigh / transitionWidth
                let smoothT = (1 - cos(t * .pi)) / 2
                y = size.height * 0.1 + smoothT * size.height * 0.8
            } else {
                // Right side - after high cutoff, stop band flat at bottom
                y = size.height * 0.9
            }

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeEdge == nil {
                    // Determine which edge to drag based on start position
                    let normalizedX = value.startLocation.x / curveWidth
                    let lowPos = normalizedPosition(for: lowFrequency)
                    let highPos = normalizedPosition(for: highFrequency)

                    // Drag whichever edge is closer
                    let distanceToLow = abs(normalizedX - lowPos)
                    let distanceToHigh = abs(normalizedX - highPos)

                    activeEdge = distanceToLow < distanceToHigh ? .low : .high
                    dragStartX = value.startLocation.x
                    dragStartFrequency = activeEdge == .low ? lowFrequency : highFrequency

                    if activeEdge == .low {
                        isDraggingLow = true
                    } else {
                        isDraggingHigh = true
                    }
                    NSCursor.closedHand.push()
                }

                // Calculate new position based on drag
                let dragDistance = value.location.x - dragStartX
                let positionChange = Double(dragDistance / curveWidth)

                // Calculate starting position
                let logMin = log10(Double(minFrequency))
                let logMax = log10(Double(maxFrequency))
                let logStartFreq = log10(Double(dragStartFrequency))
                let startPosition = (logStartFreq - logMin) / (logMax - logMin)

                // New position
                let newPosition = max(0, min(1, startPosition + positionChange))
                let newFrequency = positionToFrequency(newPosition)

                if activeEdge == .low {
                    lowFrequency = max(minFrequency, min(highFrequency - 10, newFrequency))
                } else {
                    highFrequency = max(lowFrequency + 10, min(maxFrequency, newFrequency))
                }
            }
            .onEnded { _ in
                isDraggingLow = false
                isDraggingHigh = false
                activeEdge = nil
                NSCursor.pop()
            }
    }

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1f kHz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }
}
