// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RulesWindowView — the global policy surface.
//
// Rules render as natural-language sentences. The raw glob/predicate
// lives behind an "Advanced" disclosure, never at the first glance
// (Principle 5: language). A native segmented picker switches domain
// (Files / Email / Agents) — no custom capsule tabs.
//
// History annotations ("last fired", "fired N times") are sentenced to
// be real data from the store once rule evaluation is wired; today
// rules say "not yet fired" honestly rather than fake a count. The
// fields live on `Rule` so when the audit pipeline emits rule-fired
// entries, `RulesModel.recordFiring(...)` is the single seam.
//
// Seeds are owned by `RulesModel` now (plan §5.4). The view just reads
// and writes through `store.rules`.

import SwiftUI
import ManifoldKit

struct RulesWindowView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var domain: Rule.Domain = .files
    @State private var showingNewRuleSheet = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    ForEach(visibleRules) { rule in
                        RuleCard(
                            rule: rule,
                            isEnabled: enabledBinding(for: rule),
                            onDelete: rule.seeded ? nil : { store.rules.delete(id: rule.id) }
                        )
                    }

                    if visibleRules.isEmpty {
                        emptyState
                    }
                }
                .padding(Spacing.s4)
            }
        }
        .sheet(isPresented: $showingNewRuleSheet) {
            NewRuleSheet(domain: domain) { newRule in
                store.rules.add(newRule)
                showingNewRuleSheet = false
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.s3) {
            Picker("Domain", selection: $domain) {
                ForEach(Rule.Domain.allCases, id: \.self) { d in
                    Text(d.label).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            Button("New rule\u{2026}", systemImage: "plus") {
                showingNewRuleSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.s3) {
            Image(systemName: "checklist")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No rules in \(domain.label.lowercased()) yet")
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

    private var visibleRules: [Rule] {
        store.rules.rules(in: domain)
    }

    private func enabledBinding(for rule: Rule) -> Binding<Bool> {
        Binding(
            get: { store.rules.rule(id: rule.id)?.enabled ?? false },
            set: { newValue in store.rules.setEnabled(id: rule.id, enabled: newValue) }
        )
    }
}

private extension Rule.Domain {
    var label: String {
        switch self {
        case .files:  return "Files"
        case .email:  return "Email"
        case .agents: return "Agents"
        }
    }
}

/// One rule, rendered as a natural-language sentence. Raw pattern is
/// only reachable through the "Advanced" disclosure. History lives on
/// a second line that tells the truth: today that truth is "not yet
/// fired" because rule firings aren't yet written to the audit log.
struct RuleCard: View {
    let rule: Rule
    @Binding var isEnabled: Bool
    /// `nil` for seeded rules, which cannot be deleted (only toggled).
    let onDelete: (() -> Void)?

    @State private var isExpanded = false

    private var verbColor: Color {
        switch rule.verb {
        case .allow: return ManifoldPalette.active
        case .deny:  return ManifoldPalette.attention
        case .warn:  return ManifoldPalette.paused
        }
    }

    /// The rule as a single English sentence.
    private var sentence: String {
        // "DENY files matching *.env anywhere" → "Never share files matching *.env anywhere."
        // "ALLOW agents to read ~/Projects" → "Allow agents to read ~/Projects."
        // "WARN on writes to .git/" → "Warn when writes to .git/ happen."
        switch rule.verb {
        case .deny:  return "Never share \(rule.subject) \(rule.object)."
        case .allow: return "Allow \(rule.subject) \(rule.object)."
        case .warn:  return "Warn on \(rule.subject) \(rule.object)."
        }
    }

    /// Hoisted formatter — `RelativeDateTimeFormatter` is expensive to
    /// construct and `historySentence` is called from `body` for every
    /// rule card on every render.
    private static let relativeFormatter = RelativeDateTimeFormatter()

    /// History footnote — reads real model fields so the runtime can
    /// light up the "Fired N times" path later without further view
    /// changes. Until something writes to `lastFiredAt`, renders "Not
    /// yet fired" honestly (Principle 10).
    private var historySentence: String {
        guard let last = rule.lastFiredAt else { return "Not yet fired" }
        let rel = Self.relativeFormatter.localizedString(for: last, relativeTo: .now)
        if rule.firesPast7Days <= 0 {
            return "Last fired \(rel)"
        }
        let count = rule.firesPast7Days
        return "Fired \(count) time\(count == 1 ? "" : "s") this week · last \(rel)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            headerRow
            if isExpanded { advanced }
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
        .opacity(isEnabled ? 1 : 0.55)
        .contextMenu { contextMenuItems }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Toggle("Rule enabled", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s2) {
                    Text(rule.verb.rawValue.uppercased())
                        .font(ManifoldType.tiny.weight(.semibold))
                        .foregroundStyle(verbColor)
                        .tracking(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(verbColor.opacity(0.13)))

                    Text(sentence)
                        .font(ManifoldType.body)
                        .lineLimit(2)
                }

                HStack(spacing: Spacing.s2) {
                    Text(historySentence)
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                    Text("·").foregroundStyle(.tertiary).font(ManifoldType.tiny)
                    Text(rule.seeded ? "Seeded" : "User rule")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                withAnimation(ManifoldMotion.micro) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide advanced" : "Show advanced (pattern, created, delete)")
        }
    }

    @ViewBuilder
    private var advanced: some View {
        Divider()
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .top, spacing: Spacing.s2) {
                Text("PATTERN")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                    .frame(width: 72, alignment: .leading)
                Text(rule.pattern)
                    .font(ManifoldType.mono)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: Spacing.s2) {
                Text("CREATED")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                    .frame(width: 72, alignment: .leading)
                Text(rule.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }

            if let onDelete {
                HStack {
                    Spacer()
                    Button("Delete rule", role: .destructive, action: onDelete)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(isEnabled ? "Disable" : "Enable") { isEnabled.toggle() }
        if let onDelete {
            Divider()
            Button("Delete rule", role: .destructive, action: onDelete)
        }
    }
}
