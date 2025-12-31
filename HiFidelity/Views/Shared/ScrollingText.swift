//
//  ScrollingText.swift
//  HiFidelity
//
//  Reusable scrolling text component with fade in/out effect
//

import SwiftUI

/// Scrolling text view with automatic marquee effect for long text
struct ScrollingText: View {
    let text: String
    var font: Font = .body
    var foregroundColor: Color = .primary
    var syncId: String? = nil  // Optional: use same ID to sync animations

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating = false
    @State private var opacity: Double = 1.0
    @State private var animationWorkItem: DispatchWorkItem?

    private var needsScrolling: Bool {
        textWidth > containerWidth && containerWidth > 0 && textWidth > 0
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
                                key: TextWidthPreferenceKey.self,
                                value: textGeometry.size.width
                            )
                        }
                    )

                // Visible scrolling text
                if needsScrolling {
                    Text(text)
                        .font(font)
                        .foregroundColor(foregroundColor)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(x: offset)
                        .opacity(opacity)
                        .frame(width: geometry.size.width, alignment: .leading)
                        .clipped()
                } else {
                    // If text fits, just show it
                    Text(text)
                        .font(font)
                        .foregroundColor(foregroundColor)
                        .lineLimit(1)
                }
            }
            .onAppear {
                containerWidth = geometry.size.width
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                // Only process significant width changes
                guard abs(newWidth - containerWidth) > 1 else { return }
                containerWidth = newWidth
                restartAnimation()
            }
            .onPreferenceChange(TextWidthPreferenceKey.self) { width in
                // Only update if width actually changed
                guard abs(width - textWidth) > 0.5 else { return }
                textWidth = width

                // Wait a moment for layout to stabilize, then start animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startScrollAnimation()
                }
            }
            .onChange(of: text) { oldText, newText in
                // Only reset if text actually changed
                guard newText != oldText else { return }
                restartAnimation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncScrollAnimation)) { notification in
                // Listen for sync signals from other ScrollingText views
                if let notificationSyncId = notification.object as? String,
                   let syncId = syncId,
                   notificationSyncId == syncId {
                    // Another view in our sync group finished, restart our animation
                    restartAnimation()
                }
            }
        }
    }

    private func startScrollAnimation() {
        guard needsScrolling, !isAnimating else { return }

        isAnimating = true
        offset = 0
        opacity = 1.0

        // Cancel any existing animation
        animationWorkItem?.cancel()

        let workItem = DispatchWorkItem { [self] in
            guard needsScrolling else {
                isAnimating = false
                return
            }

            // Calculate scroll distance to show just the hidden portion of text
            let scrollDistance = textWidth - containerWidth

            // Scroll to the end (speed: ~30 pixels per second for slower animation)
            let duration = Double(scrollDistance) / 30.0

            withAnimation(.linear(duration: duration)) {
                offset = -scrollDistance
            }

            // After scrolling completes, fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
                guard needsScrolling else {
                    isAnimating = false
                    return
                }

                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0.0
                }

                // After fade out, reset position and fade back in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    offset = 0

                    withAnimation(.easeIn(duration: 0.3)) {
                        opacity = 1.0
                    }

                    isAnimating = false

                    // If we're part of a sync group, notify others
                    if let syncId = syncId {
                        NotificationCenter.default.post(
                            name: .syncScrollAnimation,
                            object: syncId
                        )
                    }

                    // Start the cycle again after fade in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        startScrollAnimation()
                    }
                }
            }
        }

        animationWorkItem = workItem
        // Pause at the beginning
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func restartAnimation() {
        // Cancel any existing animation
        animationWorkItem?.cancel()
        animationWorkItem = nil

        isAnimating = false
        offset = 0
        opacity = 1.0

        // Small delay to allow layout to stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            startScrollAnimation()
        }
    }
}

// MARK: - Text Width Preference Key

private struct TextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let syncScrollAnimation = Notification.Name("syncScrollAnimation")
}
