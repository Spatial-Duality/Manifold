import FinderSync
import Foundation

/// Finder Sync Extension — adds "Add to Claude" / "Add to Codex" context menu
/// items when right-clicking folders in Finder.
///
/// Communication: sends DistributedNotification to the main app which opens
/// the Review & Update Access sheet pre-populated with the selected folder.
///
/// NOTE: This file requires a separate Finder Sync Extension target in Xcode.
/// It cannot run inside the main app target.
class ManifoldFinderSync: FIFinderSync {

    override init() {
        super.init()
        // Watch all volumes for context menus
        FIFinderSyncController.default().directoryURLs = Set([URL(fileURLWithPath: "/")])
    }

    // MARK: - Context Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "Manifold")

        let claudeItem = NSMenuItem(
            title: "Add to Claude\u{2026}",
            action: #selector(addToClaude(_:)),
            keyEquivalent: ""
        )
        claudeItem.image = NSImage(systemSymbolName: "shield.checkered", accessibilityDescription: "Manifold")
        menu.addItem(claudeItem)

        let codexItem = NSMenuItem(
            title: "Add to Codex\u{2026}",
            action: #selector(addToCodex(_:)),
            keyEquivalent: ""
        )
        menu.addItem(codexItem)

        return menu
    }

    @objc func addToClaude(_ sender: AnyObject?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        sendToManifold(items: items, agent: "cowork")
    }

    @objc func addToCodex(_ sender: AnyObject?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        sendToManifold(items: items, agent: "codex")
    }

    private func sendToManifold(items: [URL], agent: String) {
        let paths = items.map(\.path).joined(separator: "\n")
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.spatialduality.manifold.addSources"),
            object: nil,
            userInfo: [
                "action": "addSources",
                "agent": agent,
                "paths": paths
            ] as [AnyHashable: Any],
            deliverImmediately: true
        )
    }
}
