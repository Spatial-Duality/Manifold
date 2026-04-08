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
            ManifoldCommand("Start Session", icon: "play.fill") {
                await store.startSession()
            },
            ManifoldCommand("End Session", icon: "stop.fill") {
                await store.endSession()
            },
            ManifoldCommand("Add Folder", icon: "folder.badge.plus") {
                store.addSourceFromPicker()
            },
            ManifoldCommand("Search Files", icon: "magnifyingglass") {
                store.selectedSidebarItem = .files
            },
            ManifoldCommand("Review Changes", icon: "doc.text.magnifyingglass") {
                store.selectedSidebarItem = .history
            },
            ManifoldCommand("Go to Home", icon: "house") {
                store.selectedSidebarItem = .home
            },
            ManifoldCommand("Go to Files", icon: "doc.text.magnifyingglass") {
                store.selectedSidebarItem = .files
            },
            ManifoldCommand("Go to Emails", icon: "envelope.badge.shield.half.filled") {
                store.selectedSidebarItem = .emails
            },
            ManifoldCommand("Go to History", icon: "clock.arrow.circlepath") {
                store.selectedSidebarItem = .history
            },
            ManifoldCommand("Go to Sources", icon: "folder.badge.gearshape") {
                store.selectedSidebarItem = .sources
            },
            ManifoldCommand("Open Settings", icon: "gearshape") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
        ]
    }
}
