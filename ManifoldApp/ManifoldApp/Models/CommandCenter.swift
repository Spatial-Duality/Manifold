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
            ManifoldCommand("Go to Overview", icon: "square.grid.2x2") {
                store.selectedTab = .overview
            },
            ManifoldCommand("Go to Files", icon: "doc.text.magnifyingglass") {
                store.selectedTab = .files
            },
            ManifoldCommand("Go to Emails", icon: "envelope.badge.shield.half.filled") {
                store.selectedTab = .emails
            },
            ManifoldCommand("Add Folder", icon: "folder.badge.plus") {
                store.addSourceFromPicker()
            },
            ManifoldCommand("Review Access", icon: "lock.shield") {
                // TODO: open Review Access sheet
            },
            ManifoldCommand("Track Changes", icon: "timeline.selection") {
                // TODO: start track changes flow
            },
            ManifoldCommand("Open Settings", icon: "gearshape") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
        ]
    }
}
