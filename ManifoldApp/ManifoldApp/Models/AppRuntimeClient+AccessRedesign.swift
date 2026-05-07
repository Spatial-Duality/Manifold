// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import ManifoldXPC

/// Result of starting a gateway session from a saved access template. Carries
/// the active grant alongside any stale references that were skipped, so
/// the UI can render a "Started, skipped 2 missing folders" banner.
public struct StartSessionFromTemplateResult: Sendable {
    public let grant: GrantRecord
    public let sources: [GrantSourceRecord]
    public let templateID: String
    public let templateName: String
    public let skippedSources: [SkippedSource]
    public let missingEmailIDs: [String]

    public struct SkippedSource: Sendable {
        public let sourceID: String
        public let displayName: String
        public init(sourceID: String, displayName: String) {
            self.sourceID = sourceID
            self.displayName = displayName
        }
    }

    public init(
        grant: GrantRecord,
        sources: [GrantSourceRecord],
        templateID: String,
        templateName: String,
        skippedSources: [SkippedSource],
        missingEmailIDs: [String]
    ) {
        self.grant = grant
        self.sources = sources
        self.templateID = templateID
        self.templateName = templateName
        self.skippedSources = skippedSources
        self.missingEmailIDs = missingEmailIDs
    }
}

/// XPC client wrappers for the Access redesign data plumbing — bulk override
/// writes, named session templates, filter mode preferences, and per-grant
/// override-and-share approvals.
///
/// These ride on top of the XPC commands added in Lanes B-rest and C. They
/// don't extend `RuntimeClientProtocol` because the existing protocol is
/// frozen at a feature surface; new functionality lives as concrete-class
/// extensions and migrates into the protocol once the UI proves it out.
extension AppRuntimeClient {

    // MARK: - Bulk file visibility overrides (Lane B-rest)

    /// Apply many override decisions in a single XPC round-trip. Used by
    /// the unified Access surface multi-select bulk-action bar.
    func setManyFileVisibilityOverrides(_ overrides: [FileVisibilityOverrideRecord]) async throws {
        guard !overrides.isEmpty else { return }
        let payload: [String: Any] = [
            "overrides": try XPCJSON.object(from: overrides),
        ]
        _ = try await xpc.command(name: "setManyFileVisibilityOverrides", payload: payload)
    }

    // MARK: - Named session templates (Lane B-rest)

    func accessTemplates(for agent: TargetApp) async throws -> [AccessPresetRecord] {
        let response = try await xpc.command(
            name: "listAccessTemplatesForAgent",
            payload: ["agent": agent.rawValue]
        )
        guard let object = response["templates"], !(object is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        return try XPCJSON.decode([AccessPresetRecord].self, from: object)
    }

    func loadAccessTemplate(presetID: String) async throws -> AccessPresetSnapshot {
        let response = try await xpc.command(
            name: "loadAccessTemplate",
            payload: ["presetID": presetID]
        )
        guard let presetObject = response["template"],
              let scopesObject = response["fileScopes"],
              let emailsObject = response["emailIDs"],
              !(presetObject is NSNull),
              !(scopesObject is NSNull),
              !(emailsObject is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        return AccessPresetSnapshot(
            preset: try XPCJSON.decode(AccessPresetRecord.self, from: presetObject),
            fileScopes: try XPCJSON.decode([FileSelectionScope].self, from: scopesObject),
            emailIDs: try XPCJSON.decode([String].self, from: emailsObject)
        )
    }

    @discardableResult
    func saveAccessTemplate(
        presetID: String? = nil,
        name: String,
        targetApp: TargetApp?,
        fileScopes: [FileSelectionScope],
        emailIDs: [String]
    ) async throws -> AccessPresetRecord {
        var payload: [String: Any] = [
            "name": name,
            "fileScopes": try XPCJSON.object(from: fileScopes),
            "emailIDs": emailIDs,
        ]
        if let presetID { payload["presetID"] = presetID }
        if let targetApp { payload["targetApp"] = targetApp.rawValue }

        let response = try await xpc.command(name: "saveAccessTemplate", payload: payload)
        guard let object = response["template"], !(object is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        return try XPCJSON.decode(AccessPresetRecord.self, from: object)
    }

    func deleteAccessTemplate(presetID: String) async throws {
        _ = try await xpc.command(
            name: "deleteAccessTemplate",
            payload: ["presetID": presetID]
        )
    }

    /// Atomic Focus activation. Ends the agent's current grant, swaps
    /// scope + overrides to match the Focus, and starts a new grant in
    /// one round trip. Idempotent.
    @discardableResult
    func setActiveFocus(
        presetID: String,
        targetApp: TargetApp? = nil
    ) async throws -> StartSessionFromTemplateResult {
        var payload: [String: Any] = ["presetID": presetID]
        if let targetApp { payload["targetApp"] = targetApp.rawValue }
        let response = try await xpc.command(name: "setActiveFocus", payload: payload)
        return try Self.decodeStartSessionFromTemplateResult(presetID: presetID, response: response)
    }

    /// Set or clear the default-at-launch Focus for an agent.
    func setDefaultAtLaunch(presetID: String?, agent: TargetApp) async throws {
        var payload: [String: Any] = ["agent": agent.rawValue]
        if let presetID { payload["presetID"] = presetID }
        _ = try await xpc.command(name: "setDefaultAtLaunch", payload: payload)
    }

    /// Look up the preset (if any) flagged default-at-launch for an agent.
    func defaultPresetForLaunch(agent: TargetApp) async throws -> AccessPresetRecord? {
        let response = try await xpc.command(
            name: "defaultPresetForLaunch",
            payload: ["agent": agent.rawValue]
        )
        guard let object = response["preset"], !(object is NSNull) else { return nil }
        return try XPCJSON.decode(AccessPresetRecord.self, from: object)
    }

    // MARK: - Focus auto-save / per-preset settings + overrides

    /// Patch mirror_to_both flag on a Focus. Used by the
    /// "Separate sharing" toggle.
    @discardableResult
    func updatePresetMirror(presetID: String, mirrorToBoth: Bool) async throws -> AccessPresetRecord {
        let response = try await xpc.command(
            name: "updatePresetMirror",
            payload: ["presetID": presetID, "mirrorToBoth": mirrorToBoth]
        )
        guard let object = response["preset"], !(object is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        return try XPCJSON.decode(AccessPresetRecord.self, from: object)
    }

    /// Patch target_app on a Focus. Pass nil to clear (= both AIs).
    @discardableResult
    func updatePresetTargetApp(presetID: String, targetApp: TargetApp?) async throws -> AccessPresetRecord {
        var payload: [String: Any] = ["presetID": presetID]
        if let targetApp { payload["targetApp"] = targetApp.rawValue }
        let response = try await xpc.command(name: "updatePresetTargetApp", payload: payload)
        guard let object = response["preset"], !(object is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        return try XPCJSON.decode(AccessPresetRecord.self, from: object)
    }

    /// Settings-only patch on an existing preset. Cheap path for the
    /// auto-save fan-out — leaves scope and email lists untouched.
    @discardableResult
    func updatePresetSettings(
        presetID: String,
        requestDetailLevel: AccessRecordingLevel?,
        noteCaptureMode: SessionNoteCaptureMode?,
        allowFileMemory: Bool,
        summaryFraming: String?,
        emailSensitivity: EmailSensitivityLevel?
    ) async throws -> AccessPresetRecord {
        var payload: [String: Any] = [
            "presetID": presetID,
            "allowFileMemory": allowFileMemory,
        ]
        if let requestDetailLevel { payload["requestDetailLevel"] = requestDetailLevel.rawValue }
        if let noteCaptureMode { payload["noteCaptureMode"] = noteCaptureMode.rawValue }
        if let summaryFraming { payload["summaryFraming"] = summaryFraming }
        if let emailSensitivity { payload["emailSensitivity"] = emailSensitivity.rawValue }
        let response = try await xpc.command(name: "updatePresetSettings", payload: payload)
        guard let object = response["preset"], !(object is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        return try XPCJSON.decode(AccessPresetRecord.self, from: object)
    }

    /// Replace a preset's file scopes in one transaction.
    func updatePresetFileScopes(
        presetID: String,
        fileScopes: [FileSelectionScope],
        agent: TargetApp? = nil
    ) async throws {
        var payload: [String: Any] = [
            "presetID": presetID,
            "fileScopes": try XPCJSON.object(from: fileScopes),
        ]
        if let agent { payload["agent"] = agent.rawValue }
        _ = try await xpc.command(
            name: "updatePresetFileScopes",
            payload: payload
        )
    }

    /// Patch one override into a preset's saved override set.
    func setPresetOverride(
        presetID: String,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        decision: FileVisibilityOverrideDecision,
        agent: TargetApp? = nil
    ) async throws {
        var payload: [String: Any] = [
            "presetID": presetID,
            "sourceID": sourceID,
            "relativePath": relativePath,
            "isDirectory": isDirectory,
            "decision": decision.rawValue,
        ]
        if let agent { payload["agent"] = agent.rawValue }
        _ = try await xpc.command(
            name: "setPresetOverride",
            payload: payload
        )
    }

    /// Remove one override from a preset's saved set.
    func clearPresetOverride(
        presetID: String,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        agent: TargetApp? = nil
    ) async throws {
        var payload: [String: Any] = [
            "presetID": presetID,
            "sourceID": sourceID,
            "relativePath": relativePath,
            "isDirectory": isDirectory,
        ]
        if let agent { payload["agent"] = agent.rawValue }
        _ = try await xpc.command(
            name: "clearPresetOverride",
            payload: payload
        )
    }

    func recordFinderTags(_ records: [FinderTaggedItemRecord]) async throws {
        guard !records.isEmpty else { return }
        _ = try await xpc.command(
            name: "recordFinderTags",
            payload: ["records": try XPCJSON.object(from: records)]
        )
    }

    func finderTagRecords(sourceID: String) async throws -> [FinderTaggedItemRecord] {
        let response = try await xpc.command(
            name: "finderTagRecordsForSource",
            payload: ["sourceID": sourceID]
        )
        guard let object = response["records"], !(object is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        return try XPCJSON.decode([FinderTaggedItemRecord].self, from: object)
    }

    func hasOtherFinderTagOwner(
        fileIdentity: String?,
        path: String,
        tagName: String,
        excluding sourceID: String
    ) async throws -> Bool {
        var payload: [String: Any] = [
            "path": path,
            "tagName": tagName,
            "excludingSourceID": sourceID,
        ]
        if let fileIdentity { payload["fileIdentity"] = fileIdentity }
        let response = try await xpc.command(
            name: "hasOtherFinderTagOwner",
            payload: payload
        )
        return response["hasOtherOwner"] as? Bool ?? false
    }

    func removeFinderTagRecords(sourceID: String) async throws {
        _ = try await xpc.command(
            name: "removeFinderTagRecordsForSource",
            payload: ["sourceID": sourceID]
        )
    }

    func setFinderIntegrationSettings(tagsEnabled: Bool, tagName: String) async throws {
        _ = try await xpc.command(
            name: "setFinderIntegrationSettings",
            payload: [
                "tagsEnabled": tagsEnabled,
                "tagName": tagName,
            ]
        )
    }

    /// Full-replace a preset's override set in one transaction.
    func savePresetOverrides(
        presetID: String,
        overrides: [FileVisibilityOverrideRecord]
    ) async throws {
        _ = try await xpc.command(
            name: "savePresetOverrides",
            payload: [
                "presetID": presetID,
                "overrides": try XPCJSON.object(from: overrides),
            ]
        )
    }

    /// Read a preset's saved override list. The records carry the
    /// preset's `target_app` as their `agent` field.
    func presetOverrides(presetID: String, agent: TargetApp) async throws -> [FileVisibilityOverrideRecord] {
        let response = try await xpc.command(
            name: "presetOverrides",
            payload: [
                "presetID": presetID,
                "agent": agent.rawValue,
            ]
        )
        guard let object = response["overrides"], !(object is NSNull) else { return [] }
        return try XPCJSON.decode([FileVisibilityOverrideRecord].self, from: object)
    }

    func startSessionFromTemplate(
        presetID: String,
        targetApp: TargetApp? = nil,
        summaryFraming: String? = nil,
        noteCaptureMode: SessionNoteCaptureMode = .off,
        emailSensitivity: String? = nil
    ) async throws -> StartSessionFromTemplateResult {
        var payload: [String: Any] = [
            "presetID": presetID,
            "noteCaptureMode": noteCaptureMode.rawValue,
        ]
        if let targetApp { payload["targetApp"] = targetApp.rawValue }
        if let summaryFraming { payload["summaryFraming"] = summaryFraming }
        if let emailSensitivity { payload["emailSensitivity"] = emailSensitivity }

        let response = try await xpc.command(name: "startSessionFromTemplate", payload: payload)
        return try Self.decodeStartSessionFromTemplateResult(presetID: presetID, response: response)
    }

    /// Shared decoder for `startSessionFromTemplate` and `setActiveFocus`
    /// — both XPC commands return the same activeGrant + sources +
    /// skipped/missing payload shape.
    static func decodeStartSessionFromTemplateResult(
        presetID: String,
        response: [String: Any]
    ) throws -> StartSessionFromTemplateResult {
        guard let grantObject = response["activeGrant"], !(grantObject is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        let grant = try XPCJSON.decode(GrantRecord.self, from: grantObject)
        let sources: [GrantSourceRecord]
        if let sourcesObject = response["activeGrantSources"], !(sourcesObject is NSNull) {
            sources = try XPCJSON.decode([GrantSourceRecord].self, from: sourcesObject)
        } else {
            sources = []
        }
        let templateID = response["templateID"] as? String ?? presetID
        let templateName = response["templateName"] as? String ?? ""
        let skipped = (response["skippedSources"] as? [[String: Any]]) ?? []
        let skippedSources: [StartSessionFromTemplateResult.SkippedSource] = skipped.compactMap { row in
            guard let sourceID = row["sourceID"] as? String,
                  let displayName = row["displayName"] as? String else { return nil }
            return .init(sourceID: sourceID, displayName: displayName)
        }
        let missingEmailIDs = response["missingEmailIDs"] as? [String] ?? []
        return StartSessionFromTemplateResult(
            grant: grant,
            sources: sources,
            templateID: templateID,
            templateName: templateName,
            skippedSources: skippedSources,
            missingEmailIDs: missingEmailIDs
        )
    }

    // MARK: - Filter mode preferences (Lane C)

    /// Effective filter mode for an agent: per-agent override > global > .off.
    func filterMode(for agent: TargetApp) async throws -> FilterMode {
        let response = try await xpc.command(
            name: "getFilterMode",
            payload: ["agent": agent.rawValue]
        )
        let raw = response["mode"] as? String ?? FilterMode.off.rawValue
        return FilterMode(rawValue: raw) ?? .off
    }

    /// Global default filter mode (applied when an agent has no per-agent override).
    func globalFilterMode() async throws -> FilterMode {
        let response = try await xpc.command(name: "getFilterMode", payload: [:])
        let raw = response["mode"] as? String ?? FilterMode.off.rawValue
        return FilterMode(rawValue: raw) ?? .off
    }

    func setFilterMode(_ mode: FilterMode, for agent: TargetApp) async throws {
        _ = try await xpc.command(
            name: "setFilterMode",
            payload: ["agent": agent.rawValue, "mode": mode.rawValue]
        )
    }

    func setGlobalFilterMode(_ mode: FilterMode) async throws {
        _ = try await xpc.command(
            name: "setFilterMode",
            payload: ["mode": mode.rawValue]
        )
    }

    /// Drop a per-agent filter-mode override. The agent falls back to the
    /// global default.
    func clearAgentFilterMode(_ agent: TargetApp) async throws {
        _ = try await xpc.command(
            name: "clearAgentFilterMode",
            payload: ["agent": agent.rawValue]
        )
    }

    func addFilterModeOverrides(_ overrides: [FilterModeOverrideRecord]) async throws {
        guard !overrides.isEmpty else { return }
        _ = try await xpc.command(
            name: "addFilterModeOverrides",
            payload: ["overrides": try XPCJSON.object(from: overrides)]
        )
    }

    // MARK: - Scope mirror (per-AI scope copy)

    /// Compute the diff that would bring `to` into alignment with `from`.
    /// No side effects — used by the mirror confirmation sheet to show the
    /// user exactly what will change before they apply.
    func previewScopeMirror(from sourceAgent: TargetApp, to targetAgent: TargetApp) async throws -> ScopeMirrorPlan {
        let response = try await xpc.command(
            name: "previewScopeMirror",
            payload: ["from": sourceAgent.rawValue, "to": targetAgent.rawValue]
        )
        guard let object = response["plan"], !(object is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        return try XPCJSON.decode(ScopeMirrorPlan.self, from: object)
    }

    /// Apply a previously-computed plan. Idempotent — safe to retry.
    func applyScopeMirror(_ plan: ScopeMirrorPlan) async throws {
        _ = try await xpc.command(
            name: "applyScopeMirror",
            payload: ["plan": try XPCJSON.object(from: plan)]
        )
    }

    // MARK: - Inspector gem fetchers

    /// Per-file exposure timeline. Used by the file inspector to render the
    /// per-agent read/write counts beneath the Sharing selector.
    func fileExposures(resourcePath: String, limit: Int = 100) async throws -> [ExposureRecord] {
        let response = try await xpc.command(
            name: "fileExposures",
            payload: ["resourcePath": resourcePath, "limit": limit]
        )
        guard let object = response["exposures"], !(object is NSNull) else {
            return []
        }
        return try XPCJSON.decode([ExposureRecord].self, from: object)
    }

    /// File paths whose snapshot timeline contains at least one agent-
    /// authored entry. Used by the Files table for the per-row sparkle.
    func aiTouchedFilePaths() async throws -> Set<String> {
        let response = try await xpc.command(name: "aiTouchedFilePaths", payload: [:])
        let paths = response["paths"] as? [String] ?? []
        return Set(paths)
    }

    /// Per-source drift counts since the named agent's most recently
    /// ended grant. Only sources with > 0 changes are present in the
    /// returned dictionary.
    func sourceDriftCounts(agent: TargetApp) async throws -> [String: Int] {
        let response = try await xpc.command(
            name: "sourceDriftCounts",
            payload: ["agent": agent.rawValue]
        )
        // XPC marshals number values as NSNumber across the boundary;
        // accept both Int and number-backed casts.
        if let direct = response["counts"] as? [String: Int] {
            return direct
        }
        if let nsBacked = response["counts"] as? [String: NSNumber] {
            return nsBacked.mapValues { $0.intValue }
        }
        return [:]
    }

    func filterModeOverrides(grantID: String) async throws -> [FilterModeOverrideRecord] {
        let response = try await xpc.command(
            name: "listFilterModeOverrides",
            payload: ["grantID": grantID]
        )
        guard let object = response["overrides"], !(object is NSNull) else {
            throw ManifoldXPCError.malformedReply
        }
        return try XPCJSON.decode([FilterModeOverrideRecord].self, from: object)
    }
}
