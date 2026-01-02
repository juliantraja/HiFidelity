//
//  MainContentRouter.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Centralized content router that handles navigation between different views
struct MainContentRouter: View {
    @Binding var selectedEntity: EntityType?
    @Binding var searchText: String
    @Binding var isSearchActive: Bool
    
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        ZStack {
            // Layer 1 — Home (only show when no entity is selected and not transitioning)
           if selectedEntity == nil {
               HomeView(selectedEntity: $selectedEntity)
                   .zIndex(0)
           }

           // Layer 2 — Entity Detail (album/artist/genre)
           if let entity = selectedEntity {
               if isSearchActive {
                   EntityDetailWithNavigation(entity: Binding(
                       get: { selectedEntity! },
                       set: { selectedEntity = $0 }
                   )) {
                       selectedEntity = nil
                   }
                   .id(entity.uniqueId)
                   .transition(
                        .opacity
                        .animation(.easeInOut(duration: 0.15))
                   )
                   .zIndex(3)
               } else {
                   EntityDetailWithNavigation(entity: Binding(
                       get: { selectedEntity! },
                       set: { selectedEntity = $0 }
                   )) {
                       selectedEntity = nil
                   }
                   .id(entity.uniqueId)
                   .transition(.identity)
                   .zIndex(1)
               }
               
           }
            
            // Layer 3 — Search
            if isSearchActive && !searchText.isEmpty {
                SearchResultsView(
                    searchQuery: searchText,
                    selectedEntity: $selectedEntity
                )
                .background(.regularMaterial)
                .transition(
                    .opacity
                    .animation(.easeInOut(duration: 0.4))
                )
                .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 145)
        .onChange(of: isSearchActive) { _, _ in
            if selectedEntity != nil && isSearchActive {
                selectedEntity = nil
            }
        }
    }
}

// MARK: - Entity Detail with Navigation

/// Wrapper for EntityDetailView with back navigation
private struct EntityDetailWithNavigation: View {
    @Binding var entity: EntityType
    let onBack: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Back button
            backButton
            
            Divider()
            
            // Entity detail - force recreation when entity changes
            EntityDetailView(entity: entity)
                .id(entity.uniqueId)
        }
        .background(.ultraThinMaterial)
            
    }
    
    private var backButton: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onBack()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(theme.currentTheme.primaryColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.currentTheme.primaryColor.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedEntity: EntityType?
        @State private var searchText = ""
        @State private var isSearchActive = false
        
        var body: some View {
            MainContentRouter(
                selectedEntity: $selectedEntity,
                searchText: $searchText,
                isSearchActive: $isSearchActive
            )
            .environmentObject(DatabaseManager.shared)
            .frame(width: 800, height: 600)
        }
    }
    
    return PreviewWrapper()
}

