// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import ManifoldXPC

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

    /// Result of starting a session from a saved template. Carries the
    /// active grant alongside any stale references that were skipped, so
    /// the UI can render a "Started, skipped 2 missing folders" banner.
    struct StartSessionFromTemplateResult: Sendable {
        let grant: GrantRecord
        let sources: [GrantSourceRecord]
        let templateID: String
        let templateName: String
        let skippedSources: [SkippedSource]
        let missingEmailIDs: [String]

        struct SkippedSource: Sendable {
            let sourceID: String
            let displayName: String
        }
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
