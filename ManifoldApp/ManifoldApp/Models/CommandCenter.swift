// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

enum ManifoldCommandID: String, Hashable {
    case openActivity
    case openAccess
    case openMail
    case openRequests
    case openRules
    case protectNextSession
    case openSessionRecap
    case addFolder
    case refreshRuntime
    case settings
    case openManifold
    case finishTrackedEdit
}

struct ManifoldShortcut {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let label: String
}

struct ManifoldCommand: Identifiable {
    let id: ManifoldCommandID
    let title: String
    let icon: String
    let shortcut: ManifoldShortcut?
    let isAvailable: @MainActor (ManifoldStore) -> Bool
    let action: @MainActor (ManifoldStore) async -> Void

    init(
        id: ManifoldCommandID,
        title: String,
        icon: String,
        shortcut: ManifoldShortcut? = nil,
        isAvailable: @escaping @MainActor (ManifoldStore) -> Bool = { _ in true },
        action: @escaping @MainActor (ManifoldStore) async -> Void
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.isAvailable = isAvailable
        self.action = action
    }

    var shortcutLabel: String? { shortcut?.label }
}

@Observable
@MainActor
final class CommandPaletteModel {
    var isPresented = false
    var searchText = ""

    private weak var boundStore: ManifoldStore?

    func bind(to store: ManifoldStore) {
        boundStore = store
    }

    func filteredCommands(for store: ManifoldStore? = nil) -> [ManifoldCommand] {
        let resolvedStore = store ?? boundStore
        guard let resolvedStore else { return [] }
        let commands = availableCommands(for: resolvedStore)
        guard !searchText.isEmpty else { return commands }
        return commands.filter { $0.title.localizedStandardContains(searchText) }
    }

    func availableCommands(for store: ManifoldStore) -> [ManifoldCommand] {
        Self.commandCatalog.filter { $0.isAvailable(store) }
    }

    func command(_ id: ManifoldCommandID, for store: ManifoldStore) -> ManifoldCommand? {
        availableCommands(for: store).first(where: { $0.id == id })
    }

    private static let commandCatalog: [ManifoldCommand] = [
        ManifoldCommand(
            id: .openActivity,
            title: "Open Activity",
            icon: "list.bullet.rectangle",
            shortcut: ManifoldShortcut(key: "1", modifiers: .command, label: "⌘1")
        ) { _ in
            presentMainLedger(destination: .activity)
        },
        ManifoldCommand(
            id: .openAccess,
            title: "Open Access",
            icon: "folder.badge.gearshape",
            shortcut: ManifoldShortcut(key: "2", modifiers: .command, label: "⌘2")
        ) { _ in
            presentMainLedger(destination: .access)
        },
        ManifoldCommand(
            id: .openMail,
            title: "Open Mail",
            icon: "envelope",
            shortcut: ManifoldShortcut(key: "3", modifiers: .command, label: "⌘3")
        ) { _ in
            presentMainLedger(destination: .mail)
        },
        ManifoldCommand(
            id: .openRequests,
            title: "Open Requests",
            icon: "hand.raised",
            shortcut: ManifoldShortcut(key: "4", modifiers: .command, label: "⌘4")
        ) { _ in
            presentMainLedger(destination: .requests)
        },
        ManifoldCommand(
            id: .openRules,
            title: "Open Rules",
            icon: "checklist",
            shortcut: ManifoldShortcut(key: "5", modifiers: .command, label: "⌘5")
        ) { _ in
            presentMainLedger(destination: .rules)
        },
        ManifoldCommand(
            id: .protectNextSession,
            title: "Protect Next Session\u{2026}",
            icon: "play.fill",
            shortcut: ManifoldShortcut(key: "n", modifiers: .command, label: "⌘N")
        ) { _ in
            presentMainLedger()
            NotificationCenter.default.post(name: .manifoldShowSessionStartSheet, object: nil)
        },
        ManifoldCommand(
            id: .openSessionRecap,
            title: "Open Session Recap",
            icon: "list.bullet.rectangle",
            shortcut: nil
        ) { _ in
            presentMainLedger(destination: .activity)
        },
        ManifoldCommand(
            id: .addFolder,
            title: "Add Folder\u{2026}",
            icon: "folder.badge.plus",
            shortcut: ManifoldShortcut(key: "o", modifiers: [.command, .shift], label: "⇧⌘O")
        ) { store in
            store.addSourceFromPicker()
        },
        ManifoldCommand(
            id: .refreshRuntime,
            title: "Refresh Runtime",
            icon: "arrow.clockwise",
            shortcut: ManifoldShortcut(key: "r", modifiers: .command, label: "⌘R")
        ) { store in
            await store.refreshAll(force: true)
        },
        ManifoldCommand(
            id: .settings,
            title: "Settings\u{2026}",
            icon: "gearshape",
            shortcut: ManifoldShortcut(key: ",", modifiers: .command, label: "⌘,")
        ) { _ in
            presentMainLedger()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        },
        ManifoldCommand(
            id: .openManifold,
            title: "Open Manifold",
            icon: "macwindow"
        ) { _ in
            presentMainLedger()
        },
        ManifoldCommand(
            id: .finishTrackedEdit,
            title: "Finish Tracked Edit",
            icon: "checkmark.seal",
            shortcut: ManifoldShortcut(key: "f", modifiers: [.command, .shift], label: "⇧⌘F"),
            isAvailable: { $0.activeSession?.isTrackedEdit == true }
        ) { store in
            try? await store.finishActiveSession()
        },
    ]
}
