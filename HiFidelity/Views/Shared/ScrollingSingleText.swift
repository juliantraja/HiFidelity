//
//  ScrollingSingleText.swift
//  HiFidelity
//
//  Single scrolling text view with fade in/out
//

import SwiftUI

/// A single scrolling text view for individual lines
struct ScrollingSingleText: View {
    let text: String
    var font: Font = .body
    var foregroundColor: Color = .primary
    var alignment: Alignment = .leading

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var isAnimating = false
    @State private var animationTask: Task<Void, Never>?

    private var needsScroll: Bool {
        textWidth > containerWidth && containerWidth > 0 && textWidth > 0
    }

    private var initialOffset: CGFloat {
        // Calculate initial offset for centered alignment
        if alignment == .center && !needsScroll {
            return (containerWidth - textWidth) / 2
        }
        return 0
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Invisible text to measure width
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(0)
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear.preference(
                                key: TextWidthKey.self,
                                value: textGeometry.size.width
                            )
                        }
                    )

                // Visible text
                Text(text)
                    .font(font)
                    .foregroundColor(foregroundColor)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: needsScroll ? offset : initialOffset)
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
        .onPreferenceChange(TextWidthKey.self) { width in
            guard abs(width - textWidth) > 0.5 else { return }
            textWidth = width
            scheduleAnimation()
        }
        .onChange(of: text) { _, _ in
            restartAnimation()
        }
    }

    private func scheduleAnimation() {
        guard !isAnimating else { return }

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        guard needsScroll, !isAnimating else { return }

        isAnimating = true
        offset = 0
        opacity = 1.0

        animationTask?.cancel()

        animationTask = Task {
            // Initial pause
            try? await Task.sleep(for: .seconds(1.5))

            guard !Task.isCancelled, needsScroll else {
                isAnimating = false
                return
            }

            let scrollDistance = textWidth - containerWidth
            let duration = scrollDistance / 30.0

            // Scroll
            await MainActor.run {
                withAnimation(.linear(duration: duration)) {
                    offset = -scrollDistance
                }
            }

            // Wait for animation to complete
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

            // Reset and fade in
            await MainActor.run {
                offset = 0
                withAnimation(.easeIn(duration: 0.3)) {
                    opacity = 1.0
                }
                isAnimating = false
            }

            // Pause before next cycle
            try? await Task.sleep(for: .seconds(1.0))

            guard !Task.isCancelled else { return }

            // Restart
            await MainActor.run {
                startAnimation()
            }
        }
    }

    private func restartAnimation() {
        animationTask?.cancel()
        animationTask = nil
        isAnimating = false
        offset = 0
        opacity = 1.0

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                startAnimation()
            }
        }
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
