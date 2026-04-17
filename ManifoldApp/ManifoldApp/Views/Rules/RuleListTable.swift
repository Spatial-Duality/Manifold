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

    var body: some View {
        Group {
            if model.filteredRules.isEmpty {
                RulesEmptyState(filter: model.filter)
            } else {
                table
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ManifoldPalette.surface)
    }

    private var table: some View {
        Table(of: RuleRecord.self, selection: Binding(
            get: { model.selectedRuleID.map { Set([$0]) } ?? Set<String>() },
            set: { model.selectedRuleID = $0.first }
        )) {
            TableColumn("Status") { rule in
                Toggle("", isOn: Binding(
                    get: { rule.enabled },
                    set: { _ in Task { await model.toggleEnabled(id: rule.id) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(rule.source == .seeded && !rule.enabled)
                .accessibilityLabel(rule.enabled ? "Enabled" : "Disabled")
            }
            .width(44)

            TableColumn("Action") { rule in
                RuleActionBadge(action: rule.action)
            }
            .width(72)

            TableColumn("Name") { rule in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .font(ManifoldType.body)
                    Text(RuleSummary.summarize(rule.matcher))
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            TableColumn("Scope") { rule in
                HStack(spacing: Spacing.s1) {
                    Image(systemName: rule.scope.systemImage)
                        .foregroundStyle(.secondary)
                    Text(rule.scope.displayName)
                        .font(ManifoldType.caption)
                }
            }
            .width(86)

            TableColumn("Agents") { rule in
                AgentsChipRow(agents: rule.agents)
            }
            .width(100)

            TableColumn("Source") { rule in
                SourcePill(source: rule.source)
            }
            .width(90)

            TableColumn("Hits (30d)") { rule in
                Text("\(rule.matchCount)")
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(72)
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
            Task { await model.toggleEnabled(id: rule.id) }
        }
        if rule.source.isMutable {
            Button("Delete", role: .destructive) {
                Task { await model.delete(id: rule.id) }
            }
        } else {
            Text("Seeded — disable to mute")
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

private struct SourcePill: View {
    let source: RuleSource

    var body: some View {
        switch source {
        case .seeded:       Pill(text: "Seeded", variant: .seeded)
        case .userOverride: Pill(text: "Override", variant: .attention)
        case .user:         Pill(text: "Custom", variant: .user)
        case .imported:     Pill(text: "Imported", variant: .neutral)
        case .suggested:    Pill(text: "Suggested", variant: .preview)
        }
    }
}

private struct RulesEmptyState: View {
    let filter: RulesModel.Filter

    var body: some View {
        VStack(spacing: Spacing.s3) {
            Image(systemName: filter.symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No rules in \(filter.title.lowercased())")
                .font(ManifoldType.bodyMedium)
            Text("Create a rule using the + menu in the toolbar. Rules control what agents can read, write, or see.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s8)
    }
}

// MARK: - Scope glyph

extension RuleScope {
    var systemImage: String {
        switch self {
        case .file:  return "folder"
        case .email: return "envelope"
        case .agent: return "sparkles"
        }
    }
}
