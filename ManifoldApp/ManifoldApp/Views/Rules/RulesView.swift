// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RulesView — top-level unified Rules surface.
//
// Three-pane layout: sidebar (filters) → rule list table → inspector.
// All rules live in a single `RuleStore` on the runtime; this view
// reads/writes through `RulesModel` via `AppRuntimeClient`.
//
// Per design principle 10: this replaces the Phase 11 preview surface.
// File rules and privacy-preflight rules are runtime-backed today. Email
// and agent structural rules keep their preview affordances visible until
// equivalent gates are wired end to end.

import SwiftUI
import ManifoldKit

struct RulesView: View {
    @Environment(ManifoldStore.self) private var store
    @AppStorage("rules.inspectorVisible") private var inspectorVisible = true

    var body: some View {
        HStack(spacing: 0) {
            RulesSidebar(model: store.rules)
                .frame(width: 200)
                .background(ManifoldPalette.surface2)

            Divider()

            VStack(spacing: 0) {
                RulesToolbar(model: store.rules, inspectorVisible: $inspectorVisible)
                Divider()
                RulesPolicyHeader(
                    model: store.rules,
                    privacyStatus: store.governance.privacyRuntimeStatus
                )
                Divider()
                RuleListTable(model: store.rules)
            }

            if inspectorVisible {
                Divider()
                RuleInspector(model: store.rules)
                    .frame(width: 360)
                    .background(.regularMaterial)
            }
        }
        .task {
            if store.rules.rules.isEmpty {
                await store.rules.load()
            }
            if store.governance.privacyRuntimeStatus == nil {
                await store.governance.loadPolicies()
            }
        }
        .onChange(of: store.rules.selectedRuleID) { _, _ in
            store.rules.refreshPreview(for: store.rules.selectedRule, agent: store.rules.previewAgent)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.surface.rules")
    }
}

private struct RulesPolicyHeader: View {
    @Bindable var model: RulesModel
    let privacyStatus: PrivacyRuntimeStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Policy runs before content leaves Manifold")
                        .font(ManifoldType.bodyMedium)
                    Text(enforcementMessage)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.s4)
                PrivacyBackendPill(status: privacyStatus)
            }

            HStack(spacing: Spacing.s2) {
                RulesMetric(
                    title: "Enabled",
                    value: "\(model.enabledRuleCount)",
                    symbol: "checkmark.circle",
                    tint: ManifoldPalette.active
                )
                RulesMetric(
                    title: "Privacy filter",
                    value: "\(model.privacyFilterRuleCount)",
                    symbol: "sparkles.rectangle.stack",
                    tint: ManifoldPalette.selection
                )
                RulesMetric(
                    title: "Blocking",
                    value: "\(model.blockingRuleCount)",
                    symbol: "hand.raised",
                    tint: ManifoldPalette.attention
                )
                RulesMetric(
                    title: "Preview-only",
                    value: "\(model.previewOnlyStructuralRuleCount)",
                    symbol: "eye",
                    tint: ManifoldPalette.text3
                )
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(.thinMaterial)
        .accessibilityIdentifier("rules.enforcementBanner")
    }

    private var enforcementMessage: String {
        guard let privacyStatus else {
            return "File rules are enforced live. Privacy rules use the selected privacy filter when its runtime status is loaded."
        }
        if privacyStatus.modelLoaded {
            return "\(privacyBackendLabel(for: privacyStatus)) feeds privacy matchers. File gates and privacy preflight rules run before sharing; non-privacy email and agent rules remain labeled as preview-only."
        }
        return "File rules are enforced live. Privacy filter rules will enforce during preflight after the model is enabled."
    }
}

private struct PrivacyBackendPill: View {
    let status: PrivacyRuntimeStatus?

    var body: some View {
        HStack(spacing: Spacing.s1) {
            Image(systemName: status?.modelLoaded == true ? "checkmark.shield.fill" : "shield")
            Text(label)
                .lineLimit(1)
        }
        .font(ManifoldType.captionMedium)
        .foregroundStyle(status?.modelLoaded == true ? ManifoldPalette.active : ManifoldPalette.text2)
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill((status?.modelLoaded == true ? ManifoldPalette.activeSoft : ManifoldPalette.surface2).opacity(0.9))
        )
        .accessibilityIdentifier("rules.privacyBackend")
    }

    private var label: String {
        guard let status else { return "Privacy status loading" }
        let backend = privacyBackendLabel(for: status)
        return status.modelLoaded ? "\(backend) loaded" : "\(backend) not loaded"
    }
}

private struct RulesMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(ManifoldType.numericCaption.weight(.semibold))
                    .monospacedDigit()
                Text(title)
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}

private func privacyBackendLabel(for status: PrivacyRuntimeStatus) -> String {
    switch status.effectiveBackend {
    case .officialCLI:
        return "OpenAI privacy filter"
    default:
        return status.effectiveBackend.displayName
    }
}

// MARK: - Sidebar

private struct RulesSidebar: View {
    @Bindable var model: RulesModel

    var body: some View {
        List {
            Section("Scope") {
                ForEach(RulesModel.Filter.allCases) { filter in
                    if case .scope = filter {
                        sidebarRow(for: filter)
                    } else if filter == .all {
                        sidebarRow(for: filter)
                    }
                }
            }

            Section("Model") {
                sidebarRow(for: .privacy)
            }

            Section("Source") {
                ForEach(RulesModel.Filter.allCases) { filter in
                    switch filter {
                    case .seeded, .userAuthored, .suggested:
                        sidebarRow(for: filter)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("rules.sidebar")
    }

    private func sidebarRow(for filter: RulesModel.Filter) -> some View {
        Button {
            model.selectFilter(filter)
        } label: {
            HStack(spacing: Spacing.s2) {
                Image(systemName: filter.symbol)
                    .frame(width: 18)
                    .foregroundStyle(model.filter == filter ? ManifoldPalette.selection : .secondary)
                Text(filter.title)
                    .font(ManifoldType.body)
                    .foregroundStyle(model.filter == filter ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s2)
                Text("\(count(for: filter))")
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(sidebarBackground(for: filter))
        .accessibilityLabel("\(filter.title), \(count(for: filter)) rules")
        .accessibilityAddTraits(model.filter == filter ? [.isSelected] : [])
            .accessibilityIdentifier("rules.sidebar.\(filter.id)")
    }

    @ViewBuilder
    private func sidebarBackground(for filter: RulesModel.Filter) -> some View {
        if model.filter == filter {
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.selectionSoft.opacity(0.85))
                .padding(.horizontal, 4)
        } else {
            Color.clear
        }
    }

    private func count(for filter: RulesModel.Filter) -> Int {
        switch filter {
        case .all: return model.rules.count
        case .privacy: return model.rules.filter(\.isPrivacyFilterBacked).count
        case .scope(let s): return model.rules.filter { $0.scope == s }.count
        case .seeded: return model.rules.filter { $0.source == .seeded }.count
        case .userAuthored: return model.rules.filter { [.user, .userOverride, .imported].contains($0.source) }.count
        case .suggested: return model.rules.filter { $0.source == .suggested }.count
        }
    }
}

// MARK: - Toolbar

private struct RulesToolbar: View {
    @Bindable var model: RulesModel
    @Binding var inspectorVisible: Bool

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Menu {
                Menu("Privacy Filter Rule") {
                    newRuleButton(
                        "Deny sensitive content",
                        systemImage: "hand.raised",
                        action: .deny
                    ) {
                        RuleRecord.newPrivacyFilterRule(
                            name: "Deny privacy match",
                            action: .deny
                        )
                    }
                    newRuleButton(
                        "Redact sensitive spans",
                        systemImage: "text.badge.checkmark",
                        action: .redact
                    ) {
                        RuleRecord.newPrivacyFilterRule(
                            name: "Redact privacy match",
                            action: .redact
                        )
                    }
                    newRuleButton(
                        "Warn and record",
                        systemImage: "exclamationmark.triangle",
                        action: .warn
                    ) {
                        RuleRecord.newPrivacyFilterRule(
                            name: "Warn on privacy match",
                            action: .warn
                        )
                    }
                    newRuleButton(
                        "Log only",
                        systemImage: "list.bullet.rectangle",
                        action: .log
                    ) {
                        RuleRecord.newPrivacyFilterRule(
                            name: "Log privacy match",
                            action: .log
                        )
                    }
                }
                Divider()

                Menu("File Rule") {
                    newRuleButton("Deny file reads", systemImage: "hand.raised", action: .deny) {
                        RuleRecord.newUserFileRule(name: "Deny file rule", action: .deny)
                    }
                    newRuleButton("Redact before sharing", systemImage: "text.badge.checkmark", action: .redact) {
                        RuleRecord.newUserFileRule(name: "Redact file rule", action: .redact)
                    }
                    newRuleButton("Warn and record", systemImage: "exclamationmark.triangle", action: .warn) {
                        RuleRecord.newUserFileRule(name: "Warn on file rule", action: .warn)
                    }
                    newRuleButton("Log only", systemImage: "list.bullet.rectangle", action: .log) {
                        RuleRecord.newUserFileRule(name: "Log file rule", action: .log)
                    }
                }

                Menu("Email Rule") {
                    newRuleButton("Deny email exposure", systemImage: "hand.raised", action: .deny) {
                        RuleRecord.newUserEmailRule(name: "Deny email rule", action: .deny)
                    }
                    newRuleButton("Redact before sharing", systemImage: "text.badge.checkmark", action: .redact) {
                        RuleRecord.newUserEmailRule(name: "Redact email rule", action: .redact)
                    }
                    newRuleButton("Summarize only", systemImage: "text.quote", action: .summarize) {
                        RuleRecord.newUserEmailRule(name: "Summarize email rule", action: .summarize)
                    }
                    newRuleButton("Metadata only", systemImage: "tag", action: .downgrade) {
                        RuleRecord.newUserEmailRule(name: "Metadata-only email rule", action: .downgrade)
                    }
                    newRuleButton("Warn and record", systemImage: "exclamationmark.triangle", action: .warn) {
                        RuleRecord.newUserEmailRule(name: "Warn on email rule", action: .warn)
                    }
                    newRuleButton("Log only", systemImage: "list.bullet.rectangle", action: .log) {
                        RuleRecord.newUserEmailRule(name: "Log email rule", action: .log)
                    }
                }

                Menu("Agent Rule") {
                    newRuleButton("Deny matching action", systemImage: "hand.raised", action: .deny) {
                        RuleRecord.newUserAgentRule(name: "Deny agent rule", action: .deny)
                    }
                    newRuleButton("Warn and record", systemImage: "exclamationmark.triangle", action: .warn) {
                        RuleRecord.newUserAgentRule(name: "Warn on agent rule", action: .warn)
                    }
                    newRuleButton("Log only", systemImage: "list.bullet.rectangle", action: .log) {
                        RuleRecord.newUserAgentRule(name: "Log agent rule", action: .log)
                    }
                }
            } label: {
                Label("New Rule", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("rules.toolbar.newRule")

            Divider().frame(height: 16)

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            TextField("Search rules", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .accessibilityIdentifier("rules.toolbar.search")

            Button {
                withAnimation(ManifoldMotion.micro) { inspectorVisible.toggle() }
            } label: {
                Image(systemName: inspectorVisible ? "sidebar.right" : "sidebar.right")
                    .foregroundStyle(inspectorVisible ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(inspectorVisible ? "Hide inspector" : "Show inspector")
            .accessibilityIdentifier("rules.toolbar.inspector")
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rules.toolbar")
    }

    @ViewBuilder
    private func newRuleButton(
        _ title: String,
        systemImage: String,
        action: ManifoldKit.RuleAction,
        makeRule: @escaping () -> RuleRecord
    ) -> some View {
        Button {
            inspectorVisible = true
            Task { await model.addRule(makeRule()) }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .help(newRuleHelp(for: action))
    }

    private func newRuleHelp(for action: ManifoldKit.RuleAction) -> String {
        switch action {
        case .allow: return "Allow matching content."
        case .deny: return "Block matching content before it leaves Manifold."
        case .warn: return "Allow matching content and record a warning."
        case .redact: return "Strip sensitive spans before sharing matching content."
        case .summarize: return "Share a summary instead of raw matching content."
        case .downgrade: return "Share metadata only for matching content."
        case .log: return "Record matches without changing access."
        }
    }
}
