// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import ManifoldKit
import os

private let finderIntegrationLogger = Logger(subsystem: "com.spatialduality.manifold", category: "finder-integration")

enum FinderIntegrationBridge {
    static let appGroupID = "group.com.spatialduality.manifold"

    private static var fallbackURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Manifold/FinderIntegration", isDirectory: true)
    }

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) ?? fallbackURL
    }

    static var snapshotURL: URL {
        containerURL.appendingPathComponent("finder-integration-snapshot.json")
    }

    static var commandInboxURL: URL {
        containerURL.appendingPathComponent("finder-command-inbox", isDirectory: true)
    }

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: commandInboxURL, withIntermediateDirectories: true)
    }

    static func commandURLs() -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: commandInboxURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

struct FinderIntegrationSnapshot: Codable {
    var version: Int
    var updatedAt: String
    var sources: [FinderIntegrationSourceSnapshot]
    var focuses: [FinderIntegrationFocusSnapshot]
    var settings: FinderIntegrationSettingsSnapshot
}

struct FinderIntegrationSourceSnapshot: Codable {
    var sourceID: String
    var path: String
    var kind: String
    var health: String
    var status: String
    var visibleAgents: [String]
}

struct FinderIntegrationFocusSnapshot: Codable {
    var presetID: String
    var name: String
    var targetAgent: String?
    var isDefaultAtLaunch: Bool
    var isBuiltIn: Bool
    var mirrorToBoth: Bool
}

struct FinderIntegrationSettingsSnapshot: Codable {
    var tagsEnabled: Bool
    var tagName: String
}

enum FinderIntegrationCommandKind: String, Codable {
    case addToDefault
    case addToFocus
    case removeFromManifold
    case openInManifold
}

struct FinderIntegrationCommand: Codable {
    var commandID: String
    var kind: FinderIntegrationCommandKind
    var paths: [String]
    var agents: [TargetApp]?
    var presetID: String?
}

extension ManifoldStore {
    var finderIntegrationTagDisplayName: String {
        let trimmed = FinderTagService.normalizedTagName(finderIntegrationTagName)
        return trimmed.isEmpty ? "Manifold" : trimmed
    }

    var finderExtensionStatusText: String {
        let extensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("ManifoldFinderSync.appex")
        if let extensionURL, FileManager.default.fileExists(atPath: extensionURL.path) {
            return "Installed. Enable it in System Settings."
        }
        return "Not embedded in this build."
    }

    func openFinderExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    func syncFinderIntegrationSettingsToRuntime() {
        guard let client = focusClient else { return }
        let tagsEnabled = finderIntegrationTagsEnabled
        let tagName = finderIntegrationTagDisplayName
        Task {
            do {
                try await client.setFinderIntegrationSettings(tagsEnabled: tagsEnabled, tagName: tagName)
            } catch {
                finderIntegrationLogger.warning("Failed to sync Finder integration settings: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func writeFinderIntegrationSnapshot() {
        do {
            try FinderIntegrationBridge.ensureDirectories()
            let snapshot = FinderIntegrationSnapshot(
                version: 1,
                updatedAt: ISO8601DateFormatter.shared.string(from: Date()),
                sources: sources.map { source in
                    FinderIntegrationSourceSnapshot(
                        sourceID: source.sourceID,
                        path: source.effectiveRootPath,
                        kind: source.sourceKind.rawValue,
                        health: source.sourceHealth.rawValue,
                        status: source.status,
                        visibleAgents: TargetApp.allCases
                            .filter { governance.policy(for: $0)?.allowedSourceIDs.contains(source.sourceID) == true }
                            .map(\.rawValue)
                    )
                },
                focuses: availableFocuses.map { focus in
                    FinderIntegrationFocusSnapshot(
                        presetID: focus.presetID,
                        name: focus.name,
                        targetAgent: focus.targetApp?.rawValue,
                        isDefaultAtLaunch: focus.isDefaultAtLaunch,
                        isBuiltIn: focus.isBuiltIn,
                        mirrorToBoth: focus.mirrorToBoth
                    )
                },
                settings: FinderIntegrationSettingsSnapshot(
                    tagsEnabled: finderIntegrationTagsEnabled,
                    tagName: finderIntegrationTagDisplayName
                )
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: FinderIntegrationBridge.snapshotURL, options: [.atomic])
        } catch {
            finderIntegrationLogger.warning("Failed to write Finder integration snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    func consumePendingFinderCommands() async {
        do {
            try FinderIntegrationBridge.ensureDirectories()
        } catch {
            finderIntegrationLogger.warning("Failed to prepare Finder command inbox: \(error.localizedDescription, privacy: .public)")
            return
        }

        for url in FinderIntegrationBridge.commandURLs() {
            do {
                let data = try Data(contentsOf: url)
                let command = try JSONDecoder().decode(FinderIntegrationCommand.self, from: data)
                await processFinderCommand(command)
                try? FileManager.default.removeItem(at: url)
            } catch {
                finderIntegrationLogger.warning("Failed to consume Finder command \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: url)
            }
        }

        await consumeLegacyFinderRequest()
        await loadSources()
        writeFinderIntegrationSnapshot()
    }

    private func consumeLegacyFinderRequest() async {
        let requestURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Manifold/finder-sync-request.json")
        guard let data = try? Data(contentsOf: requestURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = payload["paths"] as? [String] else {
            return
        }
        let rawAgent = payload["agent"] as? String
        let agents = rawAgent.flatMap(TargetApp.init(rawValue:)).map { [$0] } ?? [.cowork]
        await processFinderCommand(
            FinderIntegrationCommand(
                commandID: UUID().uuidString,
                kind: .addToDefault,
                paths: paths,
                agents: agents,
                presetID: nil
            )
        )
        try? FileManager.default.removeItem(at: requestURL)
    }

    private func processFinderCommand(_ command: FinderIntegrationCommand) async {
        switch command.kind {
        case .addToDefault:
            await addFinderPathsToDefault(command.paths, agents: command.agents ?? [])
        case .addToFocus:
            guard let presetID = command.presetID else { return }
            await addFinderPaths(command.paths, toFocus: presetID)
        case .removeFromManifold:
            await removeFinderPathsFromManifold(command.paths)
        case .openInManifold:
            NotificationCenter.default.post(name: .manifoldShowWork, object: nil)
        }
    }

    private func addFinderPathsToDefault(_ paths: [String], agents: [TargetApp]) async {
        let selectedAgents = agents.isEmpty ? TargetApp.allCases : agents
        for path in paths {
            guard let item = await ensureFinderSource(for: URL(fileURLWithPath: path)) else { continue }
            await applyFinderTagIfNeeded(for: item)
            for agent in selectedAgents {
                if let presetID = defaultFinderPresetID(for: agent) {
                    await addFinderItem(item, toPresetID: presetID, presetAgent: agent)
                }
                if defaultScopeIsActive(for: agent) {
                    await addFinderItemToLiveScope(item, agent: agent)
                }
            }
        }
    }

    private func addFinderPaths(_ paths: [String], toFocus presetID: String) async {
        guard let focus = availableFocuses.first(where: { $0.presetID == presetID }) else { return }
        for path in paths {
            guard let item = await ensureFinderSource(for: URL(fileURLWithPath: path)) else { continue }
            await applyFinderTagIfNeeded(for: item)
            await addFinderItem(item, toPresetID: presetID, presetAgent: focus.mirrorToBoth ? nil : focus.targetApp)
            for agent in affectedAgents(for: focus) where activeFocusID[agent] == presetID {
                await addFinderItemToLiveScope(item, agent: agent)
            }
        }
    }

    private func removeFinderPathsFromManifold(_ paths: [String]) async {
        let matchedSources = Set(paths.compactMap { sourceForFinderPath($0)?.sourceID })
        for sourceID in matchedSources {
            guard let source = sources.first(where: { $0.sourceID == sourceID }) else { continue }
            await removeFinderTags(for: source)
            do {
                try await runtime.removeSource(sourceID: sourceID)
            } catch {
                lastError = "Failed to remove source from Finder: \(error.localizedDescription)"
                finderIntegrationLogger.error("Finder source removal failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private struct FinderItem {
        let requestedURL: URL
        let source: SourceRecord
        let isDirectory: Bool
        let relativeFilePath: String?
    }

    private func ensureFinderSource(for url: URL) async -> FinderItem? {
        let standardized = url.standardizedFileURL
        let isDirectory = FinderTagService.isDirectory(standardized)
        let sourceURL = isDirectory ? standardized : standardized.deletingLastPathComponent()
        guard let source = await addSourceFromURL(sourceURL) else { return nil }
        return FinderItem(
            requestedURL: standardized,
            source: source,
            isDirectory: isDirectory,
            relativeFilePath: isDirectory ? nil : standardized.lastPathComponent
        )
    }

    private func applyFinderTagIfNeeded(for item: FinderItem) async {
        guard finderIntegrationTagsEnabled else { return }
        let tagName = finderIntegrationTagDisplayName
        let records = FinderTagService.tagItems(
            at: item.requestedURL,
            sourceID: item.source.sourceID,
            tagName: tagName,
            recursive: item.isDirectory
        )
        guard let client = focusClient else { return }
        do {
            try await client.recordFinderTags(records)
        } catch {
            finderIntegrationLogger.warning("Failed to record Finder tag ledger entries: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeFinderTags(for source: SourceRecord) async {
        let tagName = finderIntegrationTagDisplayName
        guard let client = focusClient else {
            FinderTagService.removeTag(tagName, from: URL(fileURLWithPath: source.effectiveRootPath))
            return
        }
        do {
            let records = try await client.finderTagRecords(sourceID: source.sourceID)
            for record in records {
                let hasOtherOwner = try await client.hasOtherFinderTagOwner(
                    fileIdentity: record.fileIdentity,
                    path: record.originalPath,
                    tagName: record.tagName,
                    excluding: source.sourceID
                )
                guard !hasOtherOwner else { continue }
                let url = URL(fileURLWithPath: record.originalPath)
                FinderTagService.removeTag(record.tagName, from: url)
            }
            try await client.removeFinderTagRecords(sourceID: source.sourceID)
        } catch {
            finderIntegrationLogger.warning("Finder tag removal used path fallback: \(error.localizedDescription, privacy: .public)")
            FinderTagService.removeTag(tagName, from: URL(fileURLWithPath: source.effectiveRootPath))
        }
    }

    private func addFinderItem(
        _ item: FinderItem,
        toPresetID presetID: String,
        presetAgent: TargetApp?
    ) async {
        guard let client = focusClient else { return }
        do {
            let snapshot = try await client.loadAccessTemplate(presetID: presetID)
            var scopes = Set(snapshot.fileScopes)
            scopes.insert(FileSelectionScope(sourceID: item.source.sourceID, relativePath: "", isDirectory: true))
            try await client.updatePresetFileScopes(
                presetID: presetID,
                fileScopes: Array(scopes).sorted { $0.id < $1.id },
                agent: presetAgent
            )
            if let relativeFilePath = item.relativeFilePath {
                try await client.setPresetOverride(
                    presetID: presetID,
                    sourceID: item.source.sourceID,
                    relativePath: "",
                    isDirectory: true,
                    decision: .deny,
                    agent: presetAgent
                )
                try await client.setPresetOverride(
                    presetID: presetID,
                    sourceID: item.source.sourceID,
                    relativePath: relativeFilePath,
                    isDirectory: false,
                    decision: .allow,
                    agent: presetAgent
                )
            }
        } catch {
            lastError = "Could not update Focus from Finder: \(error.localizedDescription)"
            finderIntegrationLogger.error("Finder Focus update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func addFinderItemToLiveScope(_ item: FinderItem, agent: TargetApp) async {
        do {
            try await runtime.addSource(item.source.sourceID, to: agent)
            if let relativeFilePath = item.relativeFilePath {
                try await runtime.setFileVisibilityOverride(
                    agent: agent,
                    sourceID: item.source.sourceID,
                    relativePath: "",
                    isDirectory: true,
                    decision: .deny
                )
                try await runtime.setFileVisibilityOverride(
                    agent: agent,
                    sourceID: item.source.sourceID,
                    relativePath: relativeFilePath,
                    isDirectory: false,
                    decision: .allow
                )
            }
        } catch {
            lastError = "Could not update live scope from Finder: \(error.localizedDescription)"
            finderIntegrationLogger.error("Finder live scope update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func defaultFinderPresetID(for agent: TargetApp) -> String? {
        if let id = defaultLaunchFocusID[agent] ?? nil {
            return id
        }
        return availableFocuses.first {
            $0.isBuiltIn && $0.name == "Default" && $0.targetApp == agent
        }?.presetID
    }

    private func defaultScopeIsActive(for agent: TargetApp) -> Bool {
        guard let active = activeFocusID[agent], !active.isEmpty else { return true }
        return active == defaultFinderPresetID(for: agent)
    }

    private func affectedAgents(for focus: AccessPresetRecord) -> [TargetApp] {
        if let agent = focus.targetApp { return [agent] }
        return TargetApp.allCases
    }

    private func sourceForFinderPath(_ path: String) -> SourceRecord? {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return sources.first { source in
            let sourcePath = URL(fileURLWithPath: source.effectiveRootPath).standardizedFileURL.path
            return standardizedPath == sourcePath || standardizedPath.hasPrefix(sourcePath + "/")
        }
    }
}
