//
//  ScrollingTextPair.swift
//  HiFidelity
//
//  Synchronized scrolling text pair (e.g., title + artist)
//

import SwiftUI

/// A pair of scrolling text views that animate together synchronously
struct ScrollingTextPair: View {
    let title: String
    let subtitle: String
    let titleFont: Font
    let subtitleFont: Font
    let titleColor: Color
    let subtitleColor: Color
    let spacing: CGFloat

    @State private var titleWidth: CGFloat = 0
    @State private var subtitleWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var titleOffset: CGFloat = 0
    @State private var subtitleOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var isAnimating = false
    @State private var animationTask: Task<Void, Never>?

    private var titleNeedsScroll: Bool {
        titleWidth > containerWidth && containerWidth > 0 && titleWidth > 0
    }

    private var subtitleNeedsScroll: Bool {
        subtitleWidth > containerWidth && containerWidth > 0 && subtitleWidth > 0
    }

    private var shouldAnimate: Bool {
        titleNeedsScroll || subtitleNeedsScroll
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // Title
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Invisible text to measure width
                    Text(title)
                        .font(titleFont)
                        .lineLimit(1)
                        .fixedSize()
                        .opacity(0)
                        .background(
                            GeometryReader { textGeometry in
                                Color.clear.preference(
                                    key: TitleWidthPreferenceKey.self,
                                    value: textGeometry.size.width
                                )
                            }
                        )

                    // Visible text
                    Text(title)
                        .font(titleFont)
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(x: titleOffset)
                        .opacity(opacity)
                        .frame(width: geometry.size.width, alignment: .leading)
                        .clipped()
                }
                .onAppear {
                    if containerWidth == 0 {
                        containerWidth = geometry.size.width
                    }
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    guard abs(newWidth - containerWidth) > 1 else { return }
                    containerWidth = newWidth
                    restartAnimation()
                }
            }

            // Subtitle
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Invisible text to measure width
                    Text(subtitle)
                        .font(subtitleFont)
                        .lineLimit(1)
                        .fixedSize()
                        .opacity(0)
                        .background(
                            GeometryReader { textGeometry in
                                Color.clear.preference(
                                    key: SubtitleWidthPreferenceKey.self,
                                    value: textGeometry.size.width
                                )
                            }
                        )

                    // Visible text
                    Text(subtitle)
                        .font(subtitleFont)
                        .foregroundColor(subtitleColor)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(x: subtitleOffset)
                        .opacity(opacity)
                        .frame(width: geometry.size.width, alignment: .leading)
                        .clipped()
                }
            }
        }
        .onPreferenceChange(TitleWidthPreferenceKey.self) { width in
            guard abs(width - titleWidth) > 0.5 else { return }
            titleWidth = width
            scheduleAnimation()
        }
        .onPreferenceChange(SubtitleWidthPreferenceKey.self) { width in
            guard abs(width - subtitleWidth) > 0.5 else { return }
            subtitleWidth = width
            scheduleAnimation()
        }
        .onChange(of: title) { _, _ in
            restartAnimation()
        }
        .onChange(of: subtitle) { _, _ in
            restartAnimation()
        }
    }

    private func scheduleAnimation() {
        guard !isAnimating else { return }

        // Wait a moment for layout to stabilize
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        guard shouldAnimate, !isAnimating else { return }

        isAnimating = true
        titleOffset = 0
        subtitleOffset = 0
        opacity = 1.0

        // Cancel any existing animation
        animationTask?.cancel()

        animationTask = Task {
            // Initial pause
            try? await Task.sleep(for: .seconds(1.5))

            guard !Task.isCancelled, shouldAnimate else {
                isAnimating = false
                return
            }

            // Calculate scroll distances
            let titleScrollDistance = titleNeedsScroll ? titleWidth - containerWidth : 0
            let subtitleScrollDistance = subtitleNeedsScroll ? subtitleWidth - containerWidth : 0

            // Use the longer distance to determine animation duration (30px/sec)
            let maxDistance = max(titleScrollDistance, subtitleScrollDistance)
            let duration = maxDistance / 30.0

            // Animate both together
            await MainActor.run {
                withAnimation(.linear(duration: duration)) {
                    if titleNeedsScroll {
                        titleOffset = -titleScrollDistance
                    }
                    if subtitleNeedsScroll {
                        subtitleOffset = -subtitleScrollDistance
                    }
                }
            }

            // Wait for animation to complete plus a pause
            try? await Task.sleep(for: .seconds(duration + 0.5))

            guard !Task.isCancelled else {
                isAnimating = false
                return
            }

            // Fade out
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0.0
                }
            }

            try? await Task.sleep(for: .seconds(0.3))

            guard !Task.isCancelled else {
                isAnimating = false
                return
            }

            // Reset position and fade in
            await MainActor.run {
                titleOffset = 0
                subtitleOffset = 0

                withAnimation(.easeIn(duration: 0.3)) {
                    opacity = 1.0
                }

                isAnimating = false
            }

            // Pause before next cycle
            try? await Task.sleep(for: .seconds(1.0))

            guard !Task.isCancelled else { return }

            // Start next cycle
            await MainActor.run {
                startAnimation()
            }
        }
    }

    private func restartAnimation() {
        animationTask?.cancel()
        animationTask = nil
        isAnimating = false
        titleOffset = 0
        subtitleOffset = 0
        opacity = 1.0

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                startAnimation()
            }
        }
    }
}

// MARK: - Preference Keys

private struct TitleWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SubtitleWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
