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
    @AppStorage("access.inspector.visible") private var isInspectorVisible = true

    init(selectedSection: Binding<AccessSection> = .constant(.folders)) {
        _selectedSection = selectedSection
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.sources.isEmpty {
                EmptyFoldersView()
            } else {
                switch selectedSection {
                case .folders: FoldersMatrixView()
                case .files:   FilesFlatView()
                case .session: SessionDiffView()
                case .history: AccessHistoryView()
                }
            }
        }
        .background {
            Button("Toggle Inspector") { isInspectorVisible.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task { await store.refreshAll(force: false) }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldFocusCurrentSearch)) { _ in
            guard selectedSection != .files else { return }
            selectedSection = .files
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .manifoldFocusCurrentSearch, object: nil)
            }
        }
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
