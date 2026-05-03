// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RuleListTable — SwiftUI Table listing of rules filtered by the sidebar.
//
// Per app-ui rules, this uses `Table` for desktop affordances: sortable
// columns, keyboard selection, right-click menus, drag reorder hooks.

import SwiftUI
import ManifoldKit

struct RuleListTable: View {
    @Bindable var model: RulesModel
    @State private var columnCustomization: TableColumnCustomization<RuleRecord> = {
        var c = TableColumnCustomization<RuleRecord>()
        c[visibility: "hits"] = .hidden
        return c
    }()

    var body: some View {
        Group {
            if model.filteredRules.isEmpty {
                RulesEmptyState(filter: model.filter)
                    .accessibilityIdentifier("rules.emptyState")
            } else {
                table
                    .accessibilityIdentifier("rules.table")
            }
        }
        .id("\(model.filter.id)-\(model.searchText)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ManifoldPalette.surface)
    }

    private var table: some View {
        Table(of: RuleRecord.self,
              selection: Binding(
                get: { model.selectedRuleID.map { Set([$0]) } ?? Set<String>() },
                set: { model.selectedRuleID = $0.first }
              ),
              columnCustomization: $columnCustomization) {
            TableColumn("Status") { rule in
                Toggle("", isOn: Binding(
                    get: { rule.enabled },
                    set: { enabled in
                        Task { await model.setEnabled(id: rule.id, enabled: enabled) }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(rule.enabled ? "Enabled" : "Disabled")
            }
            .width(44)
            .customizationID("status")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Action") { rule in
                RuleActionBadge(action: rule.action)
            }
            .width(72)
            .customizationID("action")

            TableColumn("Name") { rule in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .font(ManifoldType.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if rule.isPrivacyFilterBacked {
                        Label("Privacy filter preflight", systemImage: "sparkles.rectangle.stack")
                            .font(ManifoldType.tiny.weight(.semibold))
                            .foregroundStyle(ManifoldPalette.selection)
                    }
                    Text(RuleSummary.summarize(rule.matcher))
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    model.selectedRuleID = rule.id
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rule.name)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("rules.rowTitle.\(rule.id)")
            }
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Gate") { rule in
                RuleGatePill(rule: rule)
            }
            .width(124)
            .customizationID("gate")

            TableColumn("Scope") { rule in
                HStack(spacing: Spacing.s1) {
                    Image(systemName: rule.scope.systemImage)
                        .foregroundStyle(.secondary)
                    Text(rule.scope.displayName)
                        .font(ManifoldType.caption)
                }
            }
            .width(86)
            .customizationID("scope")

            TableColumn("Agents") { rule in
                AgentsChipRow(agents: rule.agents)
            }
            .width(100)
            .customizationID("agents")

            TableColumn("Hits (30d)") { rule in
                Text("\(rule.matchCount)")
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(72)
            .customizationID("hits")
        } rows: {
            ForEach(model.filteredRules) { rule in
                TableRow(rule)
                    .contextMenu {
                        contextMenu(for: rule)
                    }
            }
        }
        .tableStyle(.inset)
    }

    @ViewBuilder
    private func contextMenu(for rule: RuleRecord) -> some View {
        Button(rule.enabled ? "Disable" : "Enable") {
            Task { await model.setEnabled(id: rule.id, enabled: !rule.enabled) }
        }
        if rule.source.isMutable {
            Button("Delete", role: .destructive) {
                Task { await model.delete(id: rule.id) }
            }
        } else {
            Text("Suggested rules are managed by Manifold. Disable to mute.")
        }
    }
}

// MARK: - Supporting cells

private struct RuleActionBadge: View {
    let action: ManifoldKit.RuleAction

    var body: some View {
        Text(action.rawValue.uppercased())
            .font(ManifoldType.tiny.weight(.semibold))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private var color: Color {
        switch action {
        case .allow:     return ManifoldPalette.active
        case .deny:      return ManifoldPalette.danger
        case .warn:      return ManifoldPalette.paused
        case .redact:    return ManifoldPalette.selection
        case .summarize: return ManifoldPalette.selection
        case .downgrade: return ManifoldPalette.selection
        case .log:       return ManifoldPalette.text3
        }
    }
}

private struct AgentsChipRow: View {
    let agents: Set<TargetApp>

    var body: some View {
        if agents.isEmpty {
            Text("All agents")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: Spacing.s1) {
                ForEach(Array(agents).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { agent in
                    Pill(text: AgentMeta.label(agent), variant: .agent(agent))
                }
            }
        }
    }
}

private struct RuleGatePill: View {
    let rule: RuleRecord

    var body: some View {
        Pill(text: text, variant: variant)
            .help(help)
    }

    private var text: String {
        if rule.isPrivacyFilterBacked { return "Preflight" }
        if rule.scope == .file || rule.scope == .email { return "Live" }
        return "Preview"
    }

    private var variant: Pill.Variant {
        if rule.isPrivacyFilterBacked { return .agent(.codex) }
        if rule.scope == .file || rule.scope == .email { return .session }
        return .preview
    }

    private var help: String {
        if rule.isPrivacyFilterBacked {
            return "Runs through the privacy filter before selected content is shared."
        }
        if rule.scope == .file {
            return "Enforced by the file-read gate."
        }
        if rule.scope == .email {
            return "Enforced by the email-read gate."
        }
        return "Visible for planning until its structural runtime gate is complete."
    }
}

private struct RulesEmptyState: View {
    let filter: RulesModel.Filter

    var body: some View {
        EmptyStateIllustration(
            systemImage: filter.symbol,
            title: "No rules in \(filter.title.lowercased())",
            subtitle: message,
            tint: ManifoldPalette.active,
            style: .manifoldMark
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s8)
    }

    private var message: String {
        if filter == .seeded {
            return "Suggested rules are default protections from Manifold. Restore them from the More menu if they were disabled or removed during an app update."
        }
        if filter == .privacy {
            return "Create a Privacy Filter rule to block, redact, warn, or log content found by the privacy filter before an agent sees it."
        }
        return "Add a rule with the + button. Rules control what agents can read, write, or see — applied before content leaves Manifold."
    }
}

// MARK: - Scope glyph

extension RuleScope {
    var systemImage: String {
        switch self {
        case .file:    return "folder"
        case .email:   return "envelope"
        case .content: return "doc.on.doc"
        case .agent:   return "sparkles"
        }
    }
}
