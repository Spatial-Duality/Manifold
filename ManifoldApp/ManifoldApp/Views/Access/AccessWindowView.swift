// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AccessView — the "who can see what" surface.
//
// Per design/html/access.html: 4-tab router — Folders / Files / Session
// / History — plus an empty state when no sources exist. Each sub-view
// is a dense matrix or list with its own inspector on the right.

import SwiftUI
import ManifoldKit

struct AccessView: View {
    @Environment(ManifoldStore.self) private var store

    enum AccessSection: String, Hashable, CaseIterable {
        case folders
        case files
        case session
        case history

        var label: String {
            switch self {
            case .folders: return "Folders"
            case .files:   return "Files"
            case .session: return "Session"
            case .history: return "History"
            }
        }

        var systemImage: String {
            switch self {
            case .folders: return "folder.fill"
            case .files:   return "doc.on.doc"
            case .session: return "play.fill"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    @State private var selectedSection: AccessSection = .folders
    @AppStorage("access.inspector.visible") private var isInspectorVisible = true

    var body: some View {
        VStack(spacing: 0) {
            SegmentedTabBar(
                selection: $selectedSection,
                items: AccessSection.allCases.map { item in
                    SegmentedTabItem(
                        value: item,
                        title: item.label,
                        systemImage: item.systemImage,
                        isEnabled: item != .session || store.activeSession != nil,
                        accessibilityIdentifier: "access.tab.\(item.rawValue)"
                    )
                }
            )
            Divider()

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
