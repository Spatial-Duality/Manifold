// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RulesModel — the "always-on deny layer" store (plan §5.4).
//
// Ownership move: the seed catalog was previously a `private static func`
// on RulesWindowView, which meant the view-layer owned canonical policy
// data. That leaked two ways — seeds couldn't be consumed from other
// surfaces (activity filters, onboarding hints, command palette), and any
// future persistence would have had to reach into the view. This model
// owns the list, exposes rule-domain helpers, and provides the mutation
// entry points RulesWindowView and NewRuleSheet call.
//
// History annotations (`lastFiredAt`, `firesPast7Days`) are stored on
// each Rule. Today nothing writes to them — we default to nil/0 so the
// UI can render "Not yet fired" honestly. When the runtime starts
// emitting rule-fired audit entries, `recordFiring(ruleID:at:)` below
// is the single place to update them.
//
// Persistence is intentionally not wired yet — the runtime side of rules
// (`RulesStore` in ManifoldKit) doesn't exist, and faking persistence on
// the app side would cause "your rule came back different after a
// restart" bugs. Rules today live in-memory for the app session, which
// is honest about what the store can currently offer.

import Foundation
import ManifoldKit

@Observable
@MainActor
final class RulesModel {
    /// Full ruleset (seeds + user-created + suggested). Mutations go
    /// through the `add`/`delete`/`setEnabled` methods so any future
    /// persistence has a single seam.
    private(set) var rules: [Rule]

    init(seedsEnabled: Bool = true) {
        rules = Self.defaults(enabled: seedsEnabled)
    }

    // MARK: - Queries

    func rules(in domain: Rule.Domain) -> [Rule] {
        rules.filter { $0.domain == domain }
    }

    func rule(id: String) -> Rule? {
        rules.first(where: { $0.id == id })
    }

    // MARK: - Mutations

    /// Append a user-authored rule produced by NewRuleSheet.
    func add(_ rule: Rule) {
        rules.append(rule)
    }

    /// Remove a rule. Seeded rules are non-destructible (see plan §5.4);
    /// callers filter before invoking this, but we guard here too so a
    /// programmer error can't wipe a seed.
    func delete(id: String) {
        guard let existing = rules.first(where: { $0.id == id }), !existing.seeded else { return }
        rules.removeAll { $0.id == id }
    }

    /// Toggle a rule's enabled flag. Seeded rules support this (per
    /// Principle 3 — defaults can be turned off when the user decides).
    func setEnabled(id: String, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled = enabled
    }

    // MARK: - History hooks
    //
    // The runtime doesn't yet emit rule-fired audit entries; when it does,
    // `ManifoldStore.refreshAll()` should decode them and call
    // `recordFiring(ruleID:at:)` for each, and `rollUpWeeklyCounts(as:)`
    // once per refresh to keep the seven-day count fresh.

    /// Record a single rule firing. No-op for unknown rule IDs.
    func recordFiring(ruleID: String, at date: Date) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        let current = rules[index].lastFiredAt
        if current == nil || date > current! {
            rules[index].lastFiredAt = date
        }
    }

    /// Replace the seven-day fire count for a rule. Callers compute the
    /// count from audit entries filtered to the past week.
    func setWeeklyFireCount(ruleID: String, count: Int) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].firesPast7Days = max(0, count)
    }

    // MARK: - Defaults

    /// The seed catalog. Every entry is marked `seeded: true` so the view
    /// suppresses the delete affordance and `createdBy: .seeded` so the
    /// ledger can narrate provenance.
    static func defaults(enabled: Bool = true) -> [Rule] {
        let now = Date()
        return [
            Rule(id: "seed-env", domain: .files, verb: .deny,
                 subject: "files matching *.env",
                 object: "anywhere",
                 pattern: "**/*.env",
                 enabled: enabled, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-pem", domain: .files, verb: .deny,
                 subject: "files matching *.pem",
                 object: "anywhere",
                 pattern: "**/*.pem",
                 enabled: enabled, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-ssh", domain: .files, verb: .deny,
                 subject: "files in .ssh/",
                 object: "anywhere",
                 pattern: "**/.ssh/**",
                 enabled: enabled, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-aws", domain: .files, verb: .deny,
                 subject: "files in .aws/",
                 object: "anywhere",
                 pattern: "**/.aws/**",
                 enabled: enabled, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-git", domain: .files, verb: .deny,
                 subject: "writes to .git/",
                 object: "anywhere",
                 pattern: "**/.git/**",
                 enabled: enabled, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-cc", domain: .email, verb: .deny,
                 subject: "messages containing credit card numbers",
                 object: "any mailbox",
                 pattern: "body:/\\b\\d{13,19}\\b/",
                 enabled: enabled, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-ssn", domain: .email, verb: .deny,
                 subject: "messages containing Social Security numbers",
                 object: "any mailbox",
                 pattern: "body:/\\b\\d{3}-\\d{2}-\\d{4}\\b/",
                 enabled: enabled, seeded: true, createdBy: .seeded, createdAt: now),
        ]
    }
}
