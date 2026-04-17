// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import ManifoldXPC
import os

private let rulesLogger = Logger(subsystem: "com.spatialduality.manifold", category: "rules-model")

/// Observable model for the unified Rules surface. Loads `RuleRecord`s from the runtime
/// via `AppRuntimeClient`, applies sidebar filters, supports CRUD, reorder, and live
/// match previews for the inspector.
///
/// The model is deliberately thin — it owns selection + filter state and delegates all
/// persistence to the runtime client. Views read `rules` / `selectedRule` / `preview`
/// directly and call `addRule`, `toggleEnabled`, etc.
@Observable
@MainActor
final class RulesModel {

    // MARK: - Sidebar filters

    enum Filter: Hashable, Sendable, CaseIterable, Identifiable {
        case all
        case scope(ManifoldKit.RuleScope)
        case seeded
        case userAuthored
        case suggested

        var id: String {
            switch self {
            case .all: return "all"
            case .scope(let s): return "scope-\(s.rawValue)"
            case .seeded: return "seeded"
            case .userAuthored: return "user"
            case .suggested: return "suggested"
            }
        }

        static var allCases: [Filter] {
            [.all, .scope(.file), .scope(.email), .scope(.agent), .seeded, .userAuthored, .suggested]
        }

        var title: String {
            switch self {
            case .all: return "All Rules"
            case .scope(.file): return "Files"
            case .scope(.email): return "Emails"
            case .scope(.agent): return "Agents"
            case .seeded: return "Auto (seeded)"
            case .userAuthored: return "My Rules"
            case .suggested: return "Suggested"
            }
        }

        var symbol: String {
            switch self {
            case .all: return "list.bullet"
            case .scope(.file): return "folder"
            case .scope(.email): return "envelope"
            case .scope(.agent): return "sparkles"
            case .seeded: return "lock.shield"
            case .userAuthored: return "person.crop.circle"
            case .suggested: return "wand.and.stars"
            }
        }
    }

    // MARK: - Observable state

    var rules: [RuleRecord] = []
    var selectedRuleID: String?
    var filter: Filter = .all
    var searchText: String = ""
    var previewAgent: TargetApp = .cowork
    var preview: RuleMatchPreview?
    var loading = false
    var errorMessage: String?

    // MARK: - Dependencies

    private var client: (any RuntimeClientProtocol)?
    private var previewTask: Task<Void, Never>?

    func configure(client: any RuntimeClientProtocol) {
        self.client = client
    }

    // MARK: - Derived

    /// Rules filtered by the sidebar selection + search text. Stable order: by group
    /// priority (seeded first), then `orderIndex`, then `createdAt`.
    var filteredRules: [RuleRecord] {
        let base = rules.filter { rule in
            switch filter {
            case .all:
                return true
            case .scope(let s):
                return rule.scope == s
            case .seeded:
                return rule.source == .seeded
            case .userAuthored:
                return rule.source == .user || rule.source == .userOverride || rule.source == .imported
            case .suggested:
                return rule.source == .suggested
            }
        }
        let searched: [RuleRecord]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            searched = base
        } else {
            let needle = searchText.lowercased()
            searched = base.filter { rule in
                rule.name.lowercased().contains(needle)
                    || rule.explanation.lowercased().contains(needle)
            }
        }
        return searched.sorted { lhs, rhs in
            if lhs.scope != rhs.scope { return lhs.scope.rawValue < rhs.scope.rawValue }
            if lhs.source.groupPriority != rhs.source.groupPriority {
                return lhs.source.groupPriority < rhs.source.groupPriority
            }
            if lhs.orderIndex != rhs.orderIndex { return lhs.orderIndex < rhs.orderIndex }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var selectedRule: RuleRecord? {
        guard let id = selectedRuleID else { return nil }
        return rules.first(where: { $0.id == id })
    }

    // MARK: - Load

    func load() async {
        guard let client else { return }
        loading = true
        defer { loading = false }
        do {
            rules = try await client.listRules(scope: nil)
            errorMessage = nil
            if let selectedRuleID, !rules.contains(where: { $0.id == selectedRuleID }) {
                self.selectedRuleID = nil
            }
        } catch {
            rulesLogger.error("Failed to load rules: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mutations

    func addRule(_ rule: RuleRecord) async {
        guard let client else { return }
        do {
            try await client.upsertRule(rule)
            await load()
            selectedRuleID = rule.id
        } catch {
            rulesLogger.error("Upsert failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func updateRule(_ rule: RuleRecord) async {
        guard let client else { return }
        do {
            try await client.upsertRule(rule)
            await load()
        } catch {
            rulesLogger.error("Update failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelected() async {
        guard let id = selectedRuleID, let rule = rules.first(where: { $0.id == id }) else { return }
        guard rule.source.isMutable else {
            errorMessage = "Seeded rules can't be deleted. Disable it or create an override instead."
            return
        }
        await delete(id: id)
    }

    func delete(id: String) async {
        guard let client else { return }
        do {
            try await client.deleteRule(id: id)
            if selectedRuleID == id { selectedRuleID = nil }
            await load()
        } catch {
            rulesLogger.error("Delete failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func toggleEnabled(id: String) async {
        guard let client, let rule = rules.first(where: { $0.id == id }) else { return }
        do {
            try await client.setRuleEnabled(id: id, enabled: !rule.enabled)
            await load()
        } catch {
            rulesLogger.error("Toggle failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func reorder(scope: ManifoldKit.RuleScope, ids: [String]) async {
        guard let client else { return }
        do {
            try await client.reorderRules(scope: scope, ids: ids)
            await load()
        } catch {
            rulesLogger.error("Reorder failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func resetSeededRules() async {
        guard let client else { return }
        do {
            try await client.resetSeededRules()
            await load()
        } catch {
            rulesLogger.error("Reset seeded rules failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Live match preview (inspector)

    /// Debounces preview requests — called on selection / inspector edits.
    func refreshPreview(for rule: RuleRecord?, agent: TargetApp) {
        previewTask?.cancel()
        guard let rule, let client else {
            preview = nil
            return
        }
        previewAgent = agent
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            if Task.isCancelled { return }
            do {
                let result = try await client.previewRuleMatches(rule: rule, agent: agent)
                if Task.isCancelled { return }
                await MainActor.run { self?.preview = result }
            } catch {
                rulesLogger.error("Preview failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Convenience factories

extension RuleRecord {
    /// Constructs a user-authored file rule with sensible defaults.
    static func newUserFileRule(name: String = "New file rule") -> RuleRecord {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        return RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: "",
            scope: .file,
            matcher: .pathGlob("**/new-pattern"),
            action: .deny,
            agents: [],
            window: .always,
            source: .user,
            enabled: true,
            orderIndex: 100,
            createdAt: iso,
            updatedAt: iso
        )
    }

    static func newUserEmailRule(name: String = "New email rule") -> RuleRecord {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        return RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: "",
            scope: .email,
            matcher: .emailDomain("*.example.com"),
            action: .deny,
            agents: [],
            window: .always,
            source: .user,
            enabled: true,
            orderIndex: 100,
            createdAt: iso,
            updatedAt: iso
        )
    }

    static func newUserAgentRule(name: String = "New agent rule") -> RuleRecord {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        return RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: "",
            scope: .agent,
            matcher: .agentWrite,
            action: .deny,
            agents: [],
            window: .always,
            source: .user,
            enabled: true,
            orderIndex: 100,
            createdAt: iso,
            updatedAt: iso
        )
    }
}
