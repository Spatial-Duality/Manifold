// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RulesView — top-level unified Rules surface.
//
// Three-pane layout: sidebar (filters) → rule list table → inspector.
// All rules live in a single `RuleStore` on the runtime; this view
// reads/writes through `RulesModel` via `AppRuntimeClient`.
//
// File, email, and agent rules share the runtime-backed `RuleStore`; the
// inspector keeps the policy surface consistent across scopes.

import SwiftUI
import ManifoldKit

struct RulesView: View {
    @Environment(ManifoldStore.self) private var store
    @AppStorage("rules.inspectorVisible") private var inspectorVisible = true

    var body: some View {
        HStack(spacing: 0) {
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
                title: "Advisory",
                value: "\(model.previewOnlyStructuralRuleCount)",
                symbol: "eye",
                tint: ManifoldPalette.text3
            )
            Spacer(minLength: Spacing.s2)
            PrivacyBackendPill(status: privacyStatus)
                .help(enforcementMessage)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.thinMaterial)
        .accessibilityIdentifier("rules.enforcementBanner")
    }

    private var enforcementMessage: String {
        guard let privacyStatus else {
            return "File rules are enforced live. Privacy rules use the selected privacy filter when its runtime status is loaded."
        }
        if privacyStatus.modelLoaded {
            return "\(privacyBackendLabel(for: privacyStatus)) feeds privacy matchers. File and email rules run before sharing; agent behavior rules are tracked as advisory policies."
        }
        return "File and email rules are enforced live. Privacy filter rules enforce during preflight after the model is enabled."
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
    case .mlx:
        return PrivacyRuntimePresentation.displayName(status: status)
    default:
        return status.effectiveBackend.displayName
    }
}

// MARK: - Toolbar

private struct RulesToolbar: View {
    @Bindable var model: RulesModel
    @Binding var inspectorVisible: Bool
    @State private var isResettingSeeded = false

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Button {
                addBlankRule()
            } label: {
                Label("New Rule", systemImage: "plus")
            }
            .help(blankRuleHelp)
            .accessibilityIdentifier("rules.toolbar.newRule")

            Menu {
                Section("Privacy filter templates") {
                    newRuleButton("Block secrets", systemImage: "hand.raised", action: .deny) {
                        RuleRecord.newPrivacyFilterRule(
                            name: "Block secrets before sharing",
                            category: .secret,
                            action: .deny
                        )
                    }
                    newRuleButton("Redact My Identity", systemImage: "text.badge.checkmark", action: .redact) {
                        RuleRecord.newPrivacyControlRule(
                            name: "Redact My Identity before sharing",
                            matcher: .privacyMatchesMyIdentity,
                            action: .redact,
                            explanation: "Redacts registered My Identity matches before content is shared with an agent."
                        )
                    }
                    newRuleButton("Keep allowlisted public data", systemImage: "checkmark.shield", action: .allow) {
                        RuleRecord.newPrivacyControlRule(
                            name: "Keep public or company allowlist",
                            matcher: .privacyInOrgAllowlist,
                            action: .allow,
                            explanation: "Allows findings when they are covered by the public/company allowlist."
                        )
                    }
                    newRuleButton("Warn on high severity", systemImage: "exclamationmark.triangle", action: .warn) {
                        RuleRecord.newPrivacyControlRule(
                            name: "Warn on high severity privacy findings",
                            matcher: .privacySeverityAtLeast(.high),
                            action: .warn,
                            explanation: "Allows high-severity findings but records a warning in the provenance ledger."
                        )
                    }
                    newRuleButton("Metadata only (medium+)", systemImage: "tag", action: .downgrade) {
                        RuleRecord.newPrivacyControlRule(
                            name: "Metadata only for medium privacy findings",
                            matcher: .privacySeverityAtLeast(.medium),
                            action: .downgrade,
                            explanation: "Shares metadata instead of raw content when privacy findings are medium severity or higher."
                        )
                    }
                }
                Section("File templates") {
                    newRuleButton("Deny file reads", systemImage: "hand.raised", action: .deny) {
                        RuleRecord.newUserFileRule(name: "Deny file rule", action: .deny)
                    }
                    newRuleButton("Redact before sharing", systemImage: "text.badge.checkmark", action: .redact) {
                        RuleRecord.newUserFileRule(name: "Redact file rule", action: .redact)
                    }
                }
                Section("Email templates") {
                    newRuleButton("Deny email exposure", systemImage: "hand.raised", action: .deny) {
                        RuleRecord.newUserEmailRule(name: "Deny email rule", action: .deny)
                    }
                    newRuleButton("Summarize only", systemImage: "text.quote", action: .summarize) {
                        RuleRecord.newUserEmailRule(name: "Summarize email rule", action: .summarize)
                    }
                    newRuleButton("Metadata only", systemImage: "tag", action: .downgrade) {
                        RuleRecord.newUserEmailRule(name: "Metadata-only email rule", action: .downgrade)
                    }
                }
                Section("Agent behavior templates") {
                    newRuleButton("Deny matching action", systemImage: "hand.raised", action: .deny) {
                        RuleRecord.newUserAgentRule(name: "Deny agent rule", action: .deny)
                    }
                    newRuleButton("Warn and record", systemImage: "exclamationmark.triangle", action: .warn) {
                        RuleRecord.newUserAgentRule(name: "Warn on agent rule", action: .warn)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Start from a template")
            .accessibilityLabel("New rule from template")
            .accessibilityIdentifier("rules.toolbar.newRuleTemplates")

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

            Menu {
                Button {
                    Task {
                        isResettingSeeded = true
                        defer { isResettingSeeded = false }
                        await model.resetSeededRules()
                    }
                } label: {
                    Label("Restore suggested rules", systemImage: "arrow.clockwise")
                }
                .disabled(isResettingSeeded)
                .help("Re-enables suggested rules that were disabled and resyncs the catalog after an app update.")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("rules.toolbar.overflow")
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

    /// Adds a blank rule of the most likely scope based on the current sidebar
    /// filter. Selecting "Emails" and clicking + makes a blank email rule;
    /// selecting "Privacy filter" makes a default block-secrets rule.
    private func addBlankRule() {
        inspectorVisible = true
        let rule = makeBlankRule(for: model.filter)
        Task { await model.addRule(rule) }
    }

    private func makeBlankRule(for filter: RulesModel.Filter) -> RuleRecord {
        switch filter {
        case .scope(.email):
            return RuleRecord.newUserEmailRule()
        case .scope(.agent):
            return RuleRecord.newUserAgentRule()
        case .scope(.content):
            return RuleRecord.newUserContentRule()
        case .privacy:
            return RuleRecord.newPrivacyFilterRule(
                name: "New privacy rule",
                category: .secret,
                action: .deny
            )
        case .scope(.file), .all, .seeded:
            return RuleRecord.newUserFileRule()
        }
    }

    private var blankRuleHelp: String {
        switch model.filter {
        case .scope(.email): return "Add a blank email rule"
        case .scope(.agent): return "Add a blank agent behavior rule"
        case .scope(.content): return "Add a blank rule that covers files and email"
        case .privacy: return "Add a blank privacy filter rule"
        case .scope(.file), .all, .seeded: return "Add a blank file rule"
        }
    }
}
