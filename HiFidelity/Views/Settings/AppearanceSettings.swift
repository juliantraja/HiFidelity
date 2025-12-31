//
//  AppearanceSettings.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Advanced appearance settings including theme customization
struct AppearanceSettings: View {
    @ObservedObject var theme: AppTheme
    @AppStorage("accentOpacity") private var accentOpacity: Double = 1.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Theme Selection
            themeSection
            
            Divider()
            
            // Accent Color Intensity
            accentIntensitySection
            
            Divider()
            
            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Theme Section
    
    private var themeSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 16))
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Theme")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Choose your preferred color theme")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Theme cards
            VStack(spacing: 0) {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 16)
                ], spacing: 16) {
                    ForEach(Theme.allCases) { themeOption in
                        ThemeCard(
                            theme: theme,
                            themeOption: themeOption,
                            opacity: accentOpacity
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    // MARK: - Accent Intensity Section
    
    private var accentIntensitySection: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accent Color Intensity")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Adjust the intensity of accent colors")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(accentOpacity * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Slider
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 24)
                    
                    Slider(value: $accentOpacity, in: 0.5...1.0, step: 0.1)
                        .accentColor(theme.currentTheme.primaryColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    
    // MARK: - Helpers

    
    private func resetToDefaults() {
        accentOpacity = 1.0
        theme.setTheme(.blue)
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    @ObservedObject var theme: AppTheme
    let themeOption: Theme
    let opacity: Double
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                theme.setTheme(themeOption)
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: themeOption.gradientColors.map { $0.opacity(opacity) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    theme.currentTheme == themeOption ? themeOption.primaryColor : Color.clear,
                                    lineWidth: 3
                                )
                        )
                        .shadow(
                            color: isHovered ? themeOption.primaryColor.opacity(0.3) : Color.clear,
                            radius: 8
                        )
                    
                    if theme.currentTheme == themeOption {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
                
                Text(themeOption.name)
                    .font(.subheadline)
                    .fontWeight(theme.currentTheme == themeOption ? .semibold : .regular)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        AppearanceSettings(theme: AppTheme.shared)
            .padding()
    }
    .frame(width: 600, height: 800)
}

