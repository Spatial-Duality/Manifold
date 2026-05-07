// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import AppKit
import FinderSync
import Foundation

@objc(ManifoldFinderSync)
class ManifoldFinderSync: FIFinderSync {
    private let appGroupID = "group.com.spatialduality.manifold"
    private let snapshotFileName = "finder-integration-snapshot.json"
    private let commandInboxName = "finder-command-inbox"

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = Set([URL(fileURLWithPath: "/")])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let root = NSMenu(title: "")
        let manifoldItem = NSMenuItem(title: "Manifold", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Manifold")
        root.addItem(manifoldItem)
        root.setSubmenu(submenu, for: manifoldItem)

        let selected = selectedItemURLs()
        let snapshot = readSnapshot()
        let allGoverned = !selected.isEmpty && selected.allSatisfy { snapshot?.covers($0.path) == true }

        let stateItem = NSMenuItem(title: "Added to Manifold", action: nil, keyEquivalent: "")
        stateItem.state = allGoverned ? .on : .off
        stateItem.isEnabled = false
        submenu.addItem(stateItem)
        submenu.addItem(.separator())

        let defaultItem = NSMenuItem(title: "Add to Default Focus", action: nil, keyEquivalent: "")
        let defaultMenu = NSMenu(title: "Add to Default Focus")
        defaultMenu.addItem(commandItem(title: "Claude", action: #selector(addToDefaultClaude(_:))))
        defaultMenu.addItem(commandItem(title: "Codex", action: #selector(addToDefaultCodex(_:))))
        defaultMenu.addItem(commandItem(title: "Both AIs", action: #selector(addToDefaultBoth(_:))))
        defaultItem.submenu = defaultMenu
        submenu.addItem(defaultItem)

        let focusItem = NSMenuItem(title: "Add to Focus", action: nil, keyEquivalent: "")
        let focusMenu = NSMenu(title: "Add to Focus")
        let customFocuses = (snapshot?.focuses ?? [])
            .filter { !$0.isBuiltIn }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if customFocuses.isEmpty {
            let empty = NSMenuItem(title: "No saved Focuses", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            focusMenu.addItem(empty)
        } else {
            for focus in customFocuses {
                let item = commandItem(title: focus.name, action: #selector(addToFocus(_:)))
                item.representedObject = focus.presetID as NSString
                focusMenu.addItem(item)
            }
        }
        focusItem.submenu = focusMenu
        submenu.addItem(focusItem)
        submenu.addItem(.separator())

        let removeItem = commandItem(title: "Remove from Manifold", action: #selector(removeFromManifold(_:)))
        removeItem.isEnabled = allGoverned
        submenu.addItem(removeItem)

        submenu.addItem(commandItem(title: "Open in Manifold", action: #selector(openInManifold(_:))))
        return root
    }

    @objc private func addToDefaultClaude(_ sender: AnyObject?) {
        sendCommand(kind: .addToDefault, agents: ["cowork"], presetID: nil)
    }

    @objc private func addToDefaultCodex(_ sender: AnyObject?) {
        sendCommand(kind: .addToDefault, agents: ["codex"], presetID: nil)
    }

    @objc private func addToDefaultBoth(_ sender: AnyObject?) {
        sendCommand(kind: .addToDefault, agents: ["cowork", "codex"], presetID: nil)
    }

    @objc private func addToFocus(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem,
              let presetID = item.representedObject as? String else { return }
        sendCommand(kind: .addToFocus, agents: nil, presetID: presetID)
    }

    @objc private func removeFromManifold(_ sender: AnyObject?) {
        sendCommand(kind: .removeFromManifold, agents: nil, presetID: nil)
    }

    @objc private func openInManifold(_ sender: AnyObject?) {
        sendCommand(kind: .openInManifold, agents: nil, presetID: nil)
    }

    private func commandItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: "shield.checkered", accessibilityDescription: "Manifold")
        }
        return item
    }

    private func sendCommand(kind: FinderCommandKind, agents: [String]?, presetID: String?) {
        let paths = selectedItemURLs().map(\.path)
        guard !paths.isEmpty || kind == .openInManifold else { return }
        let command = FinderCommand(
            commandID: UUID().uuidString,
            kind: kind,
            paths: paths,
            agents: agents,
            presetID: presetID
        )
        do {
            let inbox = commandInboxURL()
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(command)
            let url = inbox.appendingPathComponent("\(command.commandID).json")
            try data.write(to: url, options: [.atomic])
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.spatialduality.manifold.finderCommandQueued"),
                object: nil
            )
            launchManifold()
        } catch {
            NSLog("Manifold Finder Sync failed to hand off command: %@", error.localizedDescription)
        }
    }

    private func selectedItemURLs() -> [URL] {
        if let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty {
            return urls.map(\.standardizedFileURL)
        }
        if let targeted = FIFinderSyncController.default().targetedURL() {
            return [targeted.standardizedFileURL]
        }
        return []
    }

    private func readSnapshot() -> FinderSnapshot? {
        let url = containerURL().appendingPathComponent(snapshotFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FinderSnapshot.self, from: data)
    }

    private func commandInboxURL() -> URL {
        containerURL().appendingPathComponent(commandInboxName, isDirectory: true)
    }

    private func containerURL() -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Manifold/FinderIntegration", isDirectory: true)
    }

    private func launchManifold() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spatialduality.manifold") else {
            return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
    }
}

private enum FinderCommandKind: String, Codable {
    case addToDefault
    case addToFocus
    case removeFromManifold
    case openInManifold
}

private struct FinderCommand: Codable {
    let commandID: String
    let kind: FinderCommandKind
    let paths: [String]
    let agents: [String]?
    let presetID: String?
}

private struct FinderSnapshot: Codable {
    let sources: [FinderSourceSnapshot]
    let focuses: [FinderFocusSnapshot]

    func covers(_ path: String) -> Bool {
        let selectedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return sources.contains { source in
            let sourcePath = URL(fileURLWithPath: source.path).standardizedFileURL.path
            return selectedPath == sourcePath || selectedPath.hasPrefix(sourcePath + "/")
        }
    }
}

private struct FinderSourceSnapshot: Codable {
    let sourceID: String
    let path: String
    let kind: String
    let health: String
    let status: String
    let visibleAgents: [String]
}

private struct FinderFocusSnapshot: Codable {
    let presetID: String
    let name: String
    let targetAgent: String?
    let isDefaultAtLaunch: Bool
    let isBuiltIn: Bool
    let mirrorToBoth: Bool
}
