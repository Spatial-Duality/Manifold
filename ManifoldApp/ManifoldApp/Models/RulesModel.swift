// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
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
        case privacy
        case scope(ManifoldKit.RuleScope)
        case seeded
        case userAuthored
        case suggested

        var id: String {
            switch self {
            case .all: return "all"
            case .privacy: return "privacy"
            case .scope(let s): return "scope-\(s.rawValue)"
            case .seeded: return "seeded"
            case .userAuthored: return "user"
            case .suggested: return "suggested"
            }
        }

        static var allCases: [Filter] {
            [.all, .privacy, .scope(.file), .scope(.email), .scope(.content), .scope(.agent), .seeded, .userAuthored, .suggested]
        }

        var title: String {
            switch self {
            case .all: return "All Rules"
            case .privacy: return "Privacy Filter"
            case .scope(.file): return "Files"
            case .scope(.email): return "Emails"
            case .scope(.content): return "Files + Mail"
            case .scope(.agent): return "Agent Behaviour"
            case .seeded: return "Built-in"
            case .userAuthored: return "Mine"
            case .suggested: return "Suggested"
            }
        }

        var symbol: String {
            switch self {
            case .all: return "list.bullet"
            case .privacy: return "sparkles.rectangle.stack"
            case .scope(.file): return "folder"
            case .scope(.email): return "envelope"
            case .scope(.content): return "doc.on.doc"
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
            case .privacy:
                return rule.isPrivacyFilterBacked
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
            let needles = searchText
                .lowercased()
                .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
                .map(String.init)
            searched = base.filter { rule in
                let agents = rule.agents
                    .map { AgentMeta.label($0) }
                    .joined(separator: " ")
                let haystack = [
                    rule.name,
                    rule.explanation,
                    RuleSummary.summarize(rule.matcher),
                    rule.action.rawValue,
                    rule.scope.displayName,
                    rule.source.rawValue,
                    agents,
                    rule.isPrivacyFilterBacked ? "openai privacy filter privacy preflight model sensitive pii secret identity" : ""
                ].joined(separator: " ").lowercased()
                return needles.allSatisfy { haystack.contains($0) }
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

    var enabledRuleCount: Int {
        rules.filter(\.enabled).count
    }

    var privacyFilterRuleCount: Int {
        rules.filter(\.isPrivacyFilterBacked).count
    }

    var blockingRuleCount: Int {
        rules.filter { [.deny, .redact, .summarize, .downgrade].contains($0.action) }.count
    }

    var previewOnlyStructuralRuleCount: Int {
        rules.filter(\.isPreviewOnlyStructuralRule).count
    }

    // MARK: - Selection

    func selectFilter(_ nextFilter: Filter) {
        filter = nextFilter
        repairSelectionForCurrentFilter()
    }

    // MARK: - Load

    func load() async {
        guard let client else { return }
        loading = true
        defer { loading = false }
        do {
            rules = try await client.listRules(scope: nil)
            errorMessage = nil
            repairSelectionForCurrentFilter()
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

    private func repairSelectionForCurrentFilter() {
        let visible = filteredRules
        if let selectedRuleID, visible.contains(where: { $0.id == selectedRuleID }) {
            return
        }
        selectedRuleID = visible.first?.id
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
    static func newUserFileRule(
        name: String = "New file rule",
        action: ManifoldKit.RuleAction = .deny
    ) -> RuleRecord {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        return RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: "",
            scope: .file,
            matcher: .pathGlob("**/new-pattern"),
            action: action,
            agents: [],
            window: .always,
            source: .user,
            enabled: true,
            orderIndex: 100,
            createdAt: iso,
            updatedAt: iso
        )
    }

    static func newUserEmailRule(
        name: String = "New email rule",
        action: ManifoldKit.RuleAction = .deny
    ) -> RuleRecord {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        return RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: "",
            scope: .email,
            matcher: .emailDomain("*.example.com"),
            action: action,
            agents: [],
            window: .always,
            source: .user,
            enabled: true,
            orderIndex: 100,
            createdAt: iso,
            updatedAt: iso
        )
    }

    static func newUserAgentRule(
        name: String = "New agent rule",
        action: ManifoldKit.RuleAction = .deny
    ) -> RuleRecord {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        return RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: "",
            scope: .agent,
            matcher: .agentWrite,
            action: action,
            agents: [],
            window: .always,
            source: .user,
            enabled: true,
            orderIndex: 100,
            createdAt: iso,
            updatedAt: iso
        )
    }

    /// A `content`-scoped rule applies to BOTH file and email payloads.
    /// Use this for cross-content rules (e.g. "redact privacy findings").
    static func newUserContentRule(
        name: String = "New cross-content rule",
        action: ManifoldKit.RuleAction = .redact
    ) -> RuleRecord {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        return RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: "Applies to file reads and email reads.",
            scope: .content,
            matcher: .privacySeverityAtLeast(.medium),
            action: action,
            agents: [],
            window: .always,
            source: .user,
            enabled: true,
            orderIndex: 100,
            createdAt: iso,
            updatedAt: iso
        )
    }

    /// A privacy-filter rule that applies to ALL payloads. Stored as
    /// `.content` so the engine evaluates it on file + email requests.
    static func newPrivacyFilterRule(
        name: String = "New privacy filter rule",
        category: PrivacyCategory = .secret,
        action: ManifoldKit.RuleAction = .deny
    ) -> RuleRecord {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        return RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: "Uses the privacy filter model before content is shared with an agent.",
            scope: .content,
            matcher: .privacyContainsCategory(category),
            action: action,
            agents: [],
            window: .always,
            source: .user,
            enabled: true,
            orderIndex: 100,
            createdAt: iso,
            updatedAt: iso
        )
    }

    static func newPrivacyControlRule(
        name: String,
        matcher: RuleMatcher,
        action: ManifoldKit.RuleAction,
        explanation: String
    ) -> RuleRecord {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        return RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: explanation,
            scope: .content,
            matcher: matcher,
            action: action,
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

extension RuleRecord {
    var isPrivacyFilterBacked: Bool {
        matcher.containsPrivacyMatcher
    }

    var isRuntimeBackedByCurrentGates: Bool {
        scope == .file || scope == .email || isPrivacyFilterBacked
    }

    var isPreviewOnlyStructuralRule: Bool {
        !isRuntimeBackedByCurrentGates
    }
}

extension RuleMatcher {
    var containsPrivacyMatcher: Bool {
        switch self {
        case .privacyContainsCategory, .privacyMatchesMyIdentity,
             .privacyInOrgAllowlist, .privacySeverityAtLeast:
            return true
        case .all(let children), .any(let children):
            return children.contains { $0.containsPrivacyMatcher }
        case .not(let child):
            return child.containsPrivacyMatcher
        default:
            return false
        }
    }
}
