import AppKit
import FinderSync
import Foundation

/// Finder Sync Extension — adds "Add to Claude" / "Add to Codex" context menu
/// items when right-clicking folders in Finder.
///
/// Communication: writes a small request file that the main app consumes on refresh.
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
        let payload: [String: Any] = [
            "agent": agent,
            "paths": items.map(\.path),
        ]
        let requestURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Manifold/finder-sync-request.json")
        do {
            try FileManager.default.createDirectory(
                at: requestURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: requestURL, options: .atomic)
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spatialduality.manifold") {
                NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            }
        } catch {
            NSLog("Manifold Finder Sync failed to hand off request: %@", error.localizedDescription)
        }
    }
}
