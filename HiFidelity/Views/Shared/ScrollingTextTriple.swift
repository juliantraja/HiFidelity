//
//  ScrollingTextTriple.swift
//  HiFidelity
//
//  Synchronized scrolling for title, artist, and album
//

import SwiftUI

/// A triple of scrolling text views that animate together synchronously
struct ScrollingTextTriple: View {
    let title: String
    let subtitle: String
    let tertiary: String
    let titleFont: Font
    let subtitleFont: Font
    let tertiaryFont: Font
    let titleColor: Color
    let subtitleColor: Color
    let tertiaryColor: Color
    let spacing: CGFloat

    @State private var titleWidth: CGFloat = 0
    @State private var subtitleWidth: CGFloat = 0
    @State private var tertiaryWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var titleOffset: CGFloat = 0
    @State private var subtitleOffset: CGFloat = 0
    @State private var tertiaryOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var isAnimating = false
    @State private var animationTask: Task<Void, Never>?

    private var titleNeedsScroll: Bool {
        titleWidth > containerWidth && containerWidth > 0 && titleWidth > 0
    }

    private var subtitleNeedsScroll: Bool {
        subtitleWidth > containerWidth && containerWidth > 0 && subtitleWidth > 0
    }

    private var tertiaryNeedsScroll: Bool {
        tertiaryWidth > containerWidth && containerWidth > 0 && tertiaryWidth > 0
    }

    private var shouldAnimate: Bool {
        titleNeedsScroll || subtitleNeedsScroll || tertiaryNeedsScroll
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // Title
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Text(title).font(titleFont).lineLimit(1).fixedSize().opacity(0)
                        .background(GeometryReader { textGeometry in
                            Color.clear.preference(key: TitleWidthPreferenceKey.self, value: textGeometry.size.width)
                        })

                    Text(title).font(titleFont).foregroundColor(titleColor).lineLimit(1).fixedSize()
                        .offset(x: titleOffset).opacity(opacity)
                        .frame(width: geometry.size.width, alignment: .leading).clipped()
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
                    Text(subtitle).font(subtitleFont).lineLimit(1).fixedSize().opacity(0)
                        .background(GeometryReader { textGeometry in
                            Color.clear.preference(key: SubtitleWidthPreferenceKey.self, value: textGeometry.size.width)
                        })

                    Text(subtitle).font(subtitleFont).foregroundColor(subtitleColor).lineLimit(1).fixedSize()
                        .offset(x: subtitleOffset).opacity(opacity)
                        .frame(width: geometry.size.width, alignment: .leading).clipped()
                }
            }

            // Tertiary (Album)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Text(tertiary).font(tertiaryFont).lineLimit(1).fixedSize().opacity(0)
                        .background(GeometryReader { textGeometry in
                            Color.clear.preference(key: TertiaryWidthPreferenceKey.self, value: textGeometry.size.width)
                        })

                    Text(tertiary).font(tertiaryFont).foregroundColor(tertiaryColor).lineLimit(1).fixedSize()
                        .offset(x: tertiaryOffset).opacity(opacity)
                        .frame(width: geometry.size.width, alignment: .leading).clipped()
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
        .onPreferenceChange(TertiaryWidthPreferenceKey.self) { width in
            guard abs(width - tertiaryWidth) > 0.5 else { return }
            tertiaryWidth = width
            scheduleAnimation()
        }
        .onChange(of: title) { _, _ in
            restartAnimation()
        }
        .onChange(of: subtitle) { _, _ in
            restartAnimation()
        }
        .onChange(of: tertiary) { _, _ in
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
        guard shouldAnimate, !isAnimating else { return }

        isAnimating = true
        titleOffset = 0
        subtitleOffset = 0
        tertiaryOffset = 0
        opacity = 1.0

        animationTask?.cancel()

        animationTask = Task {
            try? await Task.sleep(for: .seconds(1.5))

            guard !Task.isCancelled, shouldAnimate else {
                isAnimating = false
                return
            }

            let titleScrollDistance = titleNeedsScroll ? titleWidth - containerWidth : 0
            let subtitleScrollDistance = subtitleNeedsScroll ? subtitleWidth - containerWidth : 0
            let tertiaryScrollDistance = tertiaryNeedsScroll ? tertiaryWidth - containerWidth : 0

            let maxDistance = max(titleScrollDistance, subtitleScrollDistance, tertiaryScrollDistance)
            let duration = maxDistance / 30.0

            await MainActor.run {
                withAnimation(.linear(duration: duration)) {
                    if titleNeedsScroll {
                        titleOffset = -titleScrollDistance
                    }
                    if subtitleNeedsScroll {
                        subtitleOffset = -subtitleScrollDistance
                    }
                    if tertiaryNeedsScroll {
                        tertiaryOffset = -tertiaryScrollDistance
                    }
                }
            }

            try? await Task.sleep(for: .seconds(duration + 0.5))

            guard !Task.isCancelled else {
                isAnimating = false
                return
            }

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

            await MainActor.run {
                titleOffset = 0
                subtitleOffset = 0
                tertiaryOffset = 0

                withAnimation(.easeIn(duration: 0.3)) {
                    opacity = 1.0
                }

                isAnimating = false
            }

            try? await Task.sleep(for: .seconds(1.0))

            guard !Task.isCancelled else { return }

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
        tertiaryOffset = 0
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

private struct TertiaryWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
