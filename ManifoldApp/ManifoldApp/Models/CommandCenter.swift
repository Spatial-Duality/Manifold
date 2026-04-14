// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct ManifoldCommand: Identifiable {
    let id: String
    let title: String
    let icon: String
    let shortcut: String?
    let action: @MainActor () async -> Void

    init(_ title: String, icon: String, shortcut: String? = nil, action: @escaping @MainActor () async -> Void) {
        self.id = title
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.action = action
    }
}

@Observable
@MainActor
final class CommandCenter {
    var isPresented = false
    var searchText = ""

    private var cachedCommands: [ManifoldCommand] = []
    private weak var boundStore: ManifoldStore?

    func bind(to store: ManifoldStore) {
        guard boundStore !== store else { return }
        boundStore = store
        cachedCommands = buildCommands(for: store)
    }

    func filteredCommands() -> [ManifoldCommand] {
        guard !searchText.isEmpty else { return cachedCommands }
        return cachedCommands.filter { $0.title.localizedStandardContains(searchText) }
    }

    private func buildCommands(for store: ManifoldStore) -> [ManifoldCommand] {
        [
            ManifoldCommand("New Session\u{2026}", icon: "play.fill") {
                NotificationCenter.default.post(name: .manifoldShowSessionStartSheet, object: nil)
            },
            ManifoldCommand("Add Folder\u{2026}", icon: "folder.badge.plus") {
                store.addSourceFromPicker()
            },
            ManifoldCommand("Refresh Runtime", icon: "arrow.clockwise") {
                await store.refreshAll(force: true)
            },
            ManifoldCommand("Open Settings", icon: "gearshape") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
        ]
    }
}
