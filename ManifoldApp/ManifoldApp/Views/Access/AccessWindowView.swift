// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AccessView — the "who can see what" surface.
//
// Per design/html/access.html: router — Folders / Files / Session
// / History — plus an empty state when no sources exist. Each sub-view
// is a dense matrix or list with its own inspector on the right.

import SwiftUI
import ManifoldKit

struct AccessView: View {
    @Environment(ManifoldStore.self) private var store
    @Binding private var selectedSection: AccessSection
    @Binding private var searchText: String
    @Binding private var inspectorVisible: Bool

    init(
        selectedSection: Binding<AccessSection> = .constant(.folders),
        searchText: Binding<String> = .constant(""),
        inspectorVisible: Binding<Bool> = .constant(true)
    ) {
        _selectedSection = selectedSection
        _searchText = searchText
        _inspectorVisible = inspectorVisible
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.sources.isEmpty {
                EmptyFoldersView()
            } else {
                switch selectedSection {
                case .folders: FoldersMatrixView(searchText: $searchText, inspectorVisible: $inspectorVisible)
                case .files:   FilesFlatView(searchText: $searchText, inspectorVisible: $inspectorVisible)
                case .session: SessionDiffView(searchText: $searchText)
                case .history: AccessHistoryView(searchText: $searchText)
                }
            }
        }
        .task { await store.refreshAll(force: false) }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldCycleCurrentSubtab)) { notification in
            guard let delta = notification.object as? Int else { return }
            cycleTab(by: delta)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.surface.access")
    }

    private func cycleTab(by delta: Int) {
        let enabledSections = AccessSection.allCases.filter { $0 != .session || store.activeSession != nil }
        guard let currentIndex = enabledSections.firstIndex(of: selectedSection), !enabledSections.isEmpty else { return }
        let nextIndex = (currentIndex + delta + enabledSections.count) % enabledSections.count
        withAnimation(ManifoldMotion.micro) {
            selectedSection = enabledSections[nextIndex]
        }
    }
}
