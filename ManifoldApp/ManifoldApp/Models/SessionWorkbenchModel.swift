// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

enum PreloadBaseMode: String, CaseIterable, Identifiable, Sendable {
    case buildOnDefault
    case blank

    var id: String { rawValue }

    var label: String {
        switch self {
        case .buildOnDefault: return "Build on default"
        case .blank: return "Start blank"
        }
    }

    var subtitle: String {
        switch self {
        case .buildOnDefault:
            return "Start with the default session's folders, then add or remove sources for this work."
        case .blank:
            return "Start with no folders and choose every source for this work."
        }
    }
}

struct SessionPreloadDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    var presetID: String?
    var name: String
    var agent: TargetApp
    var baseMode: PreloadBaseMode
    var includedSourceIDs: Set<String>
    var excludedSourceIDs: Set<String>
    var selectedEmailIDs: Set<String>
    /// Optional per-session request-detail override. When set, this is
    /// stored on the active grant and resolved at the MCP boundary. nil
    /// means "use the agent's default" — no override.
    var requestDetailOverride: AccessRecordingLevel?
    /// Lets the session's agent query prior file memory for the selected
    /// source scope. Memory is always saved; this controls read access.
    var allowFileMemory: Bool

    init(
        id: UUID = UUID(),
        presetID: String? = nil,
        name: String = "",
        agent: TargetApp = .codex,
        baseMode: PreloadBaseMode = .buildOnDefault,
        includedSourceIDs: Set<String> = [],
        excludedSourceIDs: Set<String> = [],
        selectedEmailIDs: Set<String> = [],
        requestDetailOverride: AccessRecordingLevel? = nil,
        allowFileMemory: Bool = false
    ) {
        self.id = id
        self.presetID = presetID
        self.name = name
        self.agent = agent
        self.baseMode = baseMode
        self.includedSourceIDs = includedSourceIDs
        self.excludedSourceIDs = excludedSourceIDs
        self.selectedEmailIDs = selectedEmailIDs
        self.requestDetailOverride = requestDetailOverride
        self.allowFileMemory = allowFileMemory
    }

    func effectiveSourceIDs(defaultSourceIDs: Set<String>) -> Set<String> {
        switch baseMode {
        case .buildOnDefault:
            return defaultSourceIDs.union(includedSourceIDs).subtracting(excludedSourceIDs)
        case .blank:
            return includedSourceIDs
        }
    }

    func includesSource(_ sourceID: String, defaultSourceIDs: Set<String>) -> Bool {
        effectiveSourceIDs(defaultSourceIDs: defaultSourceIDs).contains(sourceID)
    }

    var hasUnsavedName: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trimmedName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@Observable
@MainActor
final class SessionWorkbenchModel {
    var preload: SessionPreloadDraft?
    var templates: [AccessPresetRecord] = []
    var isLoadingTemplates = false
    var isSaving = false
    var isActivating = false
    var lastMessage: String?
    var lastError: String?

    func newPreload(agent: TargetApp, baseMode: PreloadBaseMode, defaultSourceIDs: Set<String>) {
        let included: Set<String>
        let excluded: Set<String>
        switch baseMode {
        case .buildOnDefault:
            included = []
            excluded = []
        case .blank:
            included = []
            excluded = []
        }
        preload = SessionPreloadDraft(
            name: "",
            agent: agent,
            baseMode: baseMode,
            includedSourceIDs: included,
            excludedSourceIDs: excluded
        )
        lastMessage = nil
        lastError = nil
    }

    func clearPreload() {
        preload = nil
        lastMessage = nil
        lastError = nil
    }

    func loadPreload(snapshot: AccessPresetSnapshot, fallbackAgent: TargetApp) {
        preload = SessionPreloadDraft(
            presetID: snapshot.preset.presetID,
            name: snapshot.preset.name,
            agent: snapshot.preset.targetApp ?? fallbackAgent,
            baseMode: .blank,
            includedSourceIDs: Set(snapshot.fileScopes.map(\.sourceID)),
            selectedEmailIDs: Set(snapshot.emailIDs)
        )
        lastMessage = "Loaded \(snapshot.preset.name)."
        lastError = nil
    }

    func setBaseMode(_ baseMode: PreloadBaseMode, defaultSourceIDs: Set<String>) {
        guard var draft = preload, draft.baseMode != baseMode else { return }
        let current = draft.effectiveSourceIDs(defaultSourceIDs: defaultSourceIDs)
        draft.baseMode = baseMode
        switch baseMode {
        case .buildOnDefault:
            draft.includedSourceIDs = current.subtracting(defaultSourceIDs)
            draft.excludedSourceIDs = defaultSourceIDs.subtracting(current)
        case .blank:
            draft.includedSourceIDs = current
            draft.excludedSourceIDs = []
        }
        preload = draft
    }

    func setAgent(_ agent: TargetApp, defaultSourceIDs: Set<String>) {
        guard var draft = preload, draft.agent != agent else { return }
        let current = draft.effectiveSourceIDs(defaultSourceIDs: defaultSourceIDs)
        draft.agent = agent
        switch draft.baseMode {
        case .buildOnDefault:
            draft.includedSourceIDs = current.subtracting(defaultSourceIDs)
            draft.excludedSourceIDs = defaultSourceIDs.subtracting(current)
        case .blank:
            draft.includedSourceIDs = current
            draft.excludedSourceIDs = []
        }
        preload = draft
    }

    func setSource(_ sourceID: String, included: Bool, defaultSourceIDs: Set<String>) {
        guard var draft = preload else { return }
        switch draft.baseMode {
        case .buildOnDefault:
            if defaultSourceIDs.contains(sourceID) {
                if included {
                    draft.excludedSourceIDs.remove(sourceID)
                } else {
                    draft.excludedSourceIDs.insert(sourceID)
                }
                draft.includedSourceIDs.remove(sourceID)
            } else {
                if included {
                    draft.includedSourceIDs.insert(sourceID)
                } else {
                    draft.includedSourceIDs.remove(sourceID)
                }
                draft.excludedSourceIDs.remove(sourceID)
            }
        case .blank:
            if included {
                draft.includedSourceIDs.insert(sourceID)
            } else {
                draft.includedSourceIDs.remove(sourceID)
            }
            draft.excludedSourceIDs.remove(sourceID)
        }
        preload = draft
    }

    func setEmail(_ emailID: String, included: Bool) {
        guard var draft = preload else { return }
        if included {
            draft.selectedEmailIDs.insert(emailID)
        } else {
            draft.selectedEmailIDs.remove(emailID)
        }
        preload = draft
    }

    func setEmails(_ emailIDs: Set<String>, included: Bool) {
        guard var draft = preload else { return }
        if included {
            draft.selectedEmailIDs.formUnion(emailIDs)
        } else {
            draft.selectedEmailIDs.subtract(emailIDs)
        }
        preload = draft
    }

    func clearEmails() {
        guard var draft = preload else { return }
        draft.selectedEmailIDs.removeAll()
        preload = draft
    }

    func effectiveSourceIDs(defaultSourceIDs: Set<String>) -> Set<String> {
        preload?.effectiveSourceIDs(defaultSourceIDs: defaultSourceIDs) ?? []
    }
}
