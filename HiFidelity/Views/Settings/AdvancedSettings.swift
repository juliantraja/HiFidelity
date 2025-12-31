//
//  AdvancedSettings.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

struct AdvancedSettings: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    @AppStorage("artworkCacheSize") private var cacheSize: Double = 500
    @State private var showResetConfirm = false
    @State private var isRebuildingFTS = false
    @State private var isOptimizing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Performance
            performanceSection
            
            Divider()
            
            // Database
            databaseSection
            
            Divider()
            
            // Danger Zone
            dangerZone
        }
    }
    
    private var performanceSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 16))
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Configure performance and caching settings")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Artwork Cache Size
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Artwork Cache Size")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Memory limit for caching album artwork. Larger cache = smoother scrolling.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(Int(cacheSize)) MB")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 24)
                    
                    Slider(value: $cacheSize, in: 100...1000, step: 100)
                        .onChange(of: cacheSize) { _, newValue in
                            applyCacheSize(Int(newValue))
                        }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private var databaseSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 16))
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Database")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Manage database size and search indexes")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Database size and optimize
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Database Size")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if let size = databaseManager.getDatabaseSize() {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        isOptimizing = true
                        Task {
                            try? await databaseManager.vacuumDatabase()
                            await MainActor.run {
                                isOptimizing = false
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isOptimizing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 12, height: 12)
                            }
                            Text(isOptimizing ? "Optimizing..." : "Optimize")
                                .font(.system(size: 12))
                        }
                    }
                    .disabled(isOptimizing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Divider()
                    .padding(.vertical, 4)
                
                // FTS rebuild
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Search Index")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Rebuild full-text search tables for better results")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        isRebuildingFTS = true
                        Task {
                            try? await databaseManager.rebuildFTS()
                            await MainActor.run {
                                isRebuildingFTS = false
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isRebuildingFTS {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 12, height: 12)
                            }
                            Text(isRebuildingFTS ? "Rebuilding..." : "Rebuild FTS")
                                .font(.system(size: 12))
                        }
                    }
                    .disabled(isRebuildingFTS)
                    .help("Rebuild full-text search indexes to apply enhanced search configuration")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private var dangerZone: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.red)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Danger Zone")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red)
                    
                    Text("Irreversible actions that affect your library")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Reset Database button
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Database")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("⚠️ This will permanently delete all your library data including folders, tracks, and playlists.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    Button {
                        showResetConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                            Text("Reset")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red)
                        )
                    }
                    .buttonStyle(.plain)
                    .alert("Reset Database?", isPresented: $showResetConfirm) {
                        Button("Cancel", role: .cancel) {}
                        Button("Reset", role: .destructive) {
                            Task {
                                try? databaseManager.resetDatabase()
                            }
                        }
                    } message: {
                        Text("This will delete all your music library data. This action cannot be undone.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    // MARK: - Helper Methods
    
    private func applyCacheSize(_ sizeMB: Int) {
        ArtworkCache.shared.updateCacheSize(sizeMB: sizeMB)
    }

} 

#Preview {
    AdvancedSettings()
        .environmentObject(DatabaseManager.shared)
        .frame(width: 600, height: 600)
}
