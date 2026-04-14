// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RulesWindowView — the global policy surface.
//
// Three tabs by domain (Files / Email / Agents). Each tab lists rules
// as sentences with code chips. "+ New rule" opens a sheet with the
// subject/verb/object grammar builder and a live blast-radius preview.

import SwiftUI
import ManifoldKit

struct RulesWindowView: View {
    enum Tab: String, Hashable, CaseIterable {
        case files, email, agents

        var label: String {
            switch self {
            case .files:  return "Files"
            case .email:  return "Email"
            case .agents: return "Agents"
            }
        }

        var systemImage: String {
            switch self {
            case .files:  return "doc.text"
            case .email:  return "envelope"
            case .agents: return "person.2"
            }
        }

        var ruleDomain: Rule.Domain {
            switch self {
            case .files:  return .files
            case .email:  return .email
            case .agents: return .agents
            }
        }
    }

    @State private var tab: Tab = .files
    @State private var showingNewRuleSheet = false
    @State private var rules: [Rule] = Self.seedRules()

    var body: some View {
        VStack(spacing: 0) {
            RulesTabBar(selection: $tab, onNewRule: { showingNewRuleSheet = true })
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    ForEach(rules.filter { $0.domain == tab.ruleDomain }) { rule in
                        RuleCard(rule: rule) { updated in
                            if let i = rules.firstIndex(where: { $0.id == updated.id }) {
                                rules[i] = updated
                            }
                        }
                    }

                    if rules.filter({ $0.domain == tab.ruleDomain }).isEmpty {
                        VStack(spacing: Spacing.s3) {
                            Image(systemName: "checklist")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text("No rules in \(tab.label.lowercased()) yet")
                                .font(ManifoldType.bodyMedium)
                            Text("Rules apply before defaults. Seeded rules cover common cases; new rules go above them in evaluation order.")
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s8)
                    }
                }
                .padding(Spacing.s4)
            }
        }
        .sheet(isPresented: $showingNewRuleSheet) {
            NewRuleSheet(domain: tab.ruleDomain) { newRule in
                rules.append(newRule)
                showingNewRuleSheet = false
            }
        }
    }

    /// Seeds default safe rules per Stage-11 Phase 7 migration spec.
    private static func seedRules() -> [Rule] {
        let now = Date()
        return [
            Rule(id: "seed-env", domain: .files, verb: .deny,
                 subject: "files matching *.env",
                 object: "anywhere",
                 pattern: "**/*.env",
                 enabled: true, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-pem", domain: .files, verb: .deny,
                 subject: "files matching *.pem",
                 object: "anywhere",
                 pattern: "**/*.pem",
                 enabled: true, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-ssh", domain: .files, verb: .deny,
                 subject: "files in .ssh/",
                 object: "anywhere",
                 pattern: "**/.ssh/**",
                 enabled: true, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-aws", domain: .files, verb: .deny,
                 subject: "files in .aws/",
                 object: "anywhere",
                 pattern: "**/.aws/**",
                 enabled: true, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-git", domain: .files, verb: .deny,
                 subject: "writes to .git/",
                 object: "anywhere",
                 pattern: "**/.git/**",
                 enabled: true, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-cc", domain: .email, verb: .deny,
                 subject: "messages containing credit card numbers",
                 object: "any mailbox",
                 pattern: "body:/\\b\\d{13,19}\\b/",
                 enabled: true, seeded: true, createdBy: .seeded, createdAt: now),
            Rule(id: "seed-ssn", domain: .email, verb: .deny,
                 subject: "messages containing Social Security numbers",
                 object: "any mailbox",
                 pattern: "body:/\\b\\d{3}-\\d{2}-\\d{4}\\b/",
                 enabled: true, seeded: true, createdBy: .seeded, createdAt: now),
        ]
    }
}

private struct RulesTabBar: View {
    @Binding var selection: RulesWindowView.Tab
    let onNewRule: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(RulesWindowView.Tab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: Spacing.s1) {
                        Image(systemName: tab.systemImage).font(.caption.weight(.medium))
                        Text(tab.label).font(ManifoldType.body)
                    }
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s1)
                    .background(Capsule().fill(selection == tab ? ManifoldPalette.claudeSoft : .clear))
                    .foregroundStyle(selection == tab ? ManifoldPalette.claude : ManifoldPalette.text2)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                onNewRule()
            } label: {
                Label("New rule\u{2026}", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
    }
}

struct RuleCard: View {
    let rule: Rule
    let onToggle: (Rule) -> Void

    private var verbColor: Color {
        switch rule.verb {
        case .allow: return ManifoldPalette.active
        case .deny:  return ManifoldPalette.attention
        case .warn:  return ManifoldPalette.paused
        }
    }

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { on in
                    var copy = rule
                    copy.enabled = on
                    onToggle(copy)
                }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: Spacing.s1) {
                HStack(spacing: Spacing.s1) {
                    Text(rule.verb.rawValue.uppercased())
                        .font(ManifoldType.tiny.weight(.semibold))
                        .foregroundStyle(verbColor)
                        .tracking(0.5)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(verbColor.opacity(0.13)))

                    Text(rule.subject)
                        .font(ManifoldType.body)
                    Text(rule.object)
                        .font(ManifoldType.body)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Spacing.s1) {
                    Text(rule.pattern)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if rule.seeded {
                        Pill(text: "seeded", variant: .seeded)
                    } else {
                        Pill(text: "user", variant: .user)
                    }
                }
            }
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
        .opacity(rule.enabled ? 1 : 0.6)
    }
}
