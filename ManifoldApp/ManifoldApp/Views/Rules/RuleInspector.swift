// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RuleInspector — inline editor for the selected rule.
//
// Replaces the modal NewRuleSheet: selecting a rule reveals the inspector;
// creating a rule focuses its name field. Edits commit on blur/return via
// the `commit()` path which validates + upserts through the runtime.

import SwiftUI
import ManifoldKit

struct RuleInspector: View {
    @Environment(ManifoldStore.self) private var store
    @Bindable var model: RulesModel
    @State private var draft: RuleRecord?
    @State private var validationError: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if let rule = model.selectedRule {
                editor(for: rule)
                    .id(rule.id)
                    .onAppear {
                        draft = rule
                        nameFocused = rule.name == "New file rule"
                            || rule.name == "New email rule"
                            || rule.name == "New agent rule"
                            || rule.name == "New privacy filter rule"
                    }
                    .onChange(of: rule.id) { _, _ in
                        draft = rule
                        validationError = nil
                    }
            } else {
                emptyState
            }
        }
        .background(ManifoldPalette.surface2)
        .accessibilityIdentifier("rules.inspector")
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: Spacing.s3) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Select a rule")
                .font(ManifoldType.bodyMedium)
            Text("Inspector shows a rule's conditions, live match preview, and recent hits.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("rules.inspector.empty")
    }

    // MARK: - Editor

    @ViewBuilder
    private func editor(for rule: RuleRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                header(rule: rule)

                if !rule.source.isMutable {
                    seededBanner
                }

                if (draft ?? rule).isPrivacyFilterBacked {
                    PrivacyFilterRuleBanner(status: store.governance.privacyRuntimeStatus)
                }

                Form {
                    Section("Name") {
                        TextField("Name", text: Binding(
                            get: { draft?.name ?? rule.name },
                            set: { newValue in
                                var d = draft ?? rule
                                d.name = newValue
                                draft = d
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .disabled(!rule.source.isMutable)
                        .onSubmit { commit() }
                        .accessibilityIdentifier("rules.inspector.name")

                        TextField("Explanation (optional)", text: Binding(
                            get: { draft?.explanation ?? rule.explanation },
                            set: { newValue in
                                var d = draft ?? rule
                                d.explanation = newValue
                                draft = d
                            }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .disabled(!rule.source.isMutable)
                        .accessibilityIdentifier("rules.inspector.explanation")
                    }

                    Section("What this rule does") {
                        Picker("When matched", selection: Binding(
                            get: { draft?.action ?? rule.action },
                            set: { newValue in
                                var d = draft ?? rule
                                d.action = newValue
                                draft = d
                            }
                        )) {
                            ForEach(actionChoices(for: draft ?? rule), id: \.self) { action in
                                Text(actionLabel(action)).tag(action)
                            }
                        }
                        .disabled(!rule.source.isMutable)
                        .accessibilityIdentifier("rules.inspector.action")

                        Text(actionDescription(draft?.action ?? rule.action))
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Section("Conditions") {
                        RuleBuilder(
                            scope: rule.scope,
                            matcher: Binding(
                                get: { draft?.matcher ?? rule.matcher },
                                set: { newValue in
                                    var d = draft ?? rule
                                    d.matcher = newValue
                                    draft = d
                                }
                            ),
                            isEditable: rule.source.isMutable
                        )
                    }

                    Section("Agents") {
                        AgentPicker(agents: Binding(
                            get: { draft?.agents ?? rule.agents },
                            set: { newValue in
                                var d = draft ?? rule
                                d.agents = newValue
                                draft = d
                            }
                        ), isEditable: rule.source.isMutable)
                    }

                    Section("Match preview") {
                        MatchPreview(model: model)
                    }

                    if rule.matchCount > 0 {
                        Section("Recent matches") {
                            RecentMatchesList(rule: rule)
                        }
                    }
                }
                .formStyle(.grouped)

                actionBar(for: rule)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s3)
        }
        .accessibilityIdentifier("rules.inspector.editor")
    }

    // MARK: - Header

    private func header(rule: RuleRecord) -> some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: rule.scope.systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(rule.isPrivacyFilterBacked ? ManifoldPalette.selection : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(ManifoldType.heading)
                    .lineLimit(2)
                Text(RuleSummary.summarize(rule.matcher))
                    .font(ManifoldType.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var seededBanner: some View {
        HStack(alignment: .top, spacing: Spacing.s2) {
            Image(systemName: "lock.shield")
                .foregroundStyle(ManifoldPalette.paused)
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested rule")
                    .font(ManifoldType.captionMedium)
                Text("Suggested rules are managed by Manifold. They can be disabled, but not edited. Create a Mine rule to override.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.s3)
        .background(ManifoldPalette.pausedSoft)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous))
        .accessibilityIdentifier("rules.inspector.seeded")
    }

    // MARK: - Action bar

    @ViewBuilder
    private func actionBar(for rule: RuleRecord) -> some View {
        HStack(spacing: Spacing.s2) {
            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle.fill")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
                    .lineLimit(2)
            }
            Spacer()

            if rule.source.isMutable {
                Button("Delete", role: .destructive) {
                    Task { await model.delete(id: rule.id) }
                }
                .accessibilityIdentifier("rules.inspector.delete")

                Button("Save Changes") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty(against: rule))
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityIdentifier("rules.inspector.save")
            }
        }
    }

    // MARK: - Helpers

    private func updateDraft(_ mutate: (inout RuleRecord) -> Void) {
        guard let selected = model.selectedRule else { return }
        var d = draft ?? selected
        mutate(&d)
        draft = d
    }

    private func isDirty(against rule: RuleRecord) -> Bool {
        guard let draft else { return false }
        return draft != rule
    }

    private func commit() {
        guard let draft, draft.source.isMutable else { return }
        var next = draft
        next.updatedAt = ISO8601DateFormatter.shared.string(from: Date())
        do {
            try RuleValidator.validate(next)
            validationError = nil
            Task { await model.updateRule(next) }
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func actionChoices(for rule: RuleRecord) -> [ManifoldKit.RuleAction] {
        if rule.isPrivacyFilterBacked {
            return [.allow, .deny, .warn, .redact, .summarize, .downgrade, .log]
        }
        switch rule.scope {
        case .file:    return [.allow, .deny, .warn, .redact, .log]
        case .email:   return [.allow, .deny, .warn, .redact, .summarize, .downgrade, .log]
        case .content: return [.allow, .deny, .warn, .redact, .summarize, .downgrade, .log]
        case .agent:   return [.allow, .deny, .warn, .log]
        }
    }

    private func actionLabel(_ a: ManifoldKit.RuleAction) -> String {
        switch a {
        case .allow:     return "Allow"
        case .deny:      return "Deny"
        case .warn:      return "Warn"
        case .redact:    return "Redact sensitive spans"
        case .summarize: return "Summarize"
        case .downgrade: return "Metadata only"
        case .log:       return "Log only"
        }
    }

    private func actionDescription(_ action: ManifoldKit.RuleAction) -> String {
        switch action {
        case .allow:
            return "Allow matching content through when no higher-priority deny blocks it."
        case .deny:
            return "Block matching content before it leaves Manifold."
        case .warn:
            return "Let matching content through, but record a warning in the ledger."
        case .redact:
            return "Share matching content only after privacy-sensitive spans are stripped."
        case .summarize:
            return "Share a summary instead of the original content."
        case .downgrade:
            return "Share metadata only, without the body or file contents."
        case .log:
            return "Do not change access; only record that the rule matched."
        }
    }
}

// MARK: - Privacy filter backing

private struct PrivacyFilterRuleBanner: View {
    let status: PrivacyRuntimeStatus?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(ManifoldPalette.selection)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ManifoldType.captionMedium)
                Text(message)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s3)
        .background(ManifoldPalette.selectionSoft.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous))
        .accessibilityIdentifier("rules.inspector.privacyFilter")
    }

    private var title: String {
        guard let status else { return "Privacy filter rule" }
        if status.effectiveBackend == .mlx {
            return "\(PrivacyRuntimePresentation.displayName(status: status)) rule"
        }
        return "\(status.effectiveBackend.displayName) privacy rule"
    }

    private var message: String {
        guard let status else {
            return "This rule uses privacy matcher output during preflight before content is shared with Claude or Codex."
        }
        if status.modelLoaded {
            return "The loaded privacy backend feeds category and severity matchers. Identity and allowlist matchers apply when live preflight supplies those enriched findings."
        }
        return "This rule is ready, but the privacy backend is not loaded. Enable the model in Privacy settings before relying on category or severity matches."
    }
}

// MARK: - Agent picker

private struct AgentPicker: View {
    @Binding var agents: Set<TargetApp>
    let isEditable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Toggle("Apply to all agents", isOn: Binding(
                get: { agents.isEmpty },
                set: { allAgents in
                    if allAgents { agents = [] } else { agents = [.cowork] }
                }
            ))
            .toggleStyle(.switch)
            .disabled(!isEditable)
            .accessibilityIdentifier("rules.inspector.agents.all")

            if !agents.isEmpty {
                HStack {
                    ForEach([TargetApp.cowork, TargetApp.codex], id: \.self) { agent in
                        Toggle(isOn: Binding(
                            get: { agents.contains(agent) },
                            set: { on in
                                if on { agents.insert(agent) } else { agents.remove(agent) }
                                if agents.isEmpty { agents.insert(agent) }
                            }
                        )) {
                            HStack(spacing: 4) {
                                AgentLogo(agent: agent, size: 12, treatment: .monochrome(ManifoldPalette.agent(agent)))
                                    .accessibilityHidden(true)
                                Text(AgentMeta.label(agent))
                            }
                        }
                        .toggleStyle(.button)
                        .tint(ManifoldPalette.agent(agent))
                        .disabled(!isEditable)
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Recent matches

private struct RecentMatchesList: View {
    let rule: RuleRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack {
                Text("Matched \(rule.matchCount) time\(rule.matchCount == 1 ? "" : "s") in 30 days")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = rule.lastMatchedAt {
                    Text(last.prefix(10))
                        .font(ManifoldType.numericCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Deep links to the full history arrive with the next audit integration.")
                .font(ManifoldType.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Plain-English summary

enum RuleSummary {
    static func summarize(_ matcher: RuleMatcher) -> String {
        switch matcher {
        case .pathGlob(let p):                    return p
        case .pathRegex(let p):                   return "regex: \(p)"
        case .fileSizeOver(let n):                return "size > \(bytes(n))"
        case .fileSizeUnder(let n):               return "size < \(bytes(n))"
        case .fileAgeOlderThan(let t):            return "older than \(days(t))"
        case .fileAgeNewerThan(let t):            return "newer than \(days(t))"
        case .fileHidden:                         return "hidden files"
        case .fileBinary:                         return "binary files"
        case .fileSecretDetected:                 return "contains a detected secret"
        case .gitignored:                         return "listed in .gitignore"
        case .fileExtension(let e):               return ".\(e) files"
        case .emailSender(let s):                 return "from \(s)"
        case .emailDomain(let d):                 return "from domain \(d)"
        case .emailSubjectKeyword(let k, _):      return "subject contains \"\(k)\""
        case .emailBodyKeyword(let k, _):         return "body contains \"\(k)\""
        case .emailKeyword(let f, let k, _):      return "\(f.displayName.lowercased()) contains \"\(k)\""
        case .emailHasAttachment:                 return "has any attachment"
        case .emailAttachmentLargerThan(let n):   return "attachment > \(bytes(n))"
        case .emailShield(let s):                 return "\(s.displayName) shield"
        case .emailInFolder(let f):               return "in folder \(f)"
        case .emailAccount(let a):                return "account \(a)"
        case .emailOlderThan(let t):              return "older than \(days(t))"
        case .agentTool(let t):                   return "tool: \(t.displayName)"
        case .agentWrite:                         return "any write call"
        case .agentDelete:                        return "any delete call"
        case .agentSessionLongerThan(let t):      return "session longer than \(minutes(t))"
        case .agentPayloadLargerThan(let n):      return "payload > \(bytes(n))"
        case .privacyContainsCategory(let c):     return "contains \(c.displayName.lowercased())"
        case .privacyMatchesMyIdentity:           return "matches My Identity"
        case .privacyInOrgAllowlist:              return "on org allowlist"
        case .privacySeverityAtLeast(let s):      return "privacy ≥ \(s.rawValue)"
        case .all(let children):                  return children.map(summarize).joined(separator: " AND ")
        case .any(let children):                  return children.map(summarize).joined(separator: " OR ")
        case .not(let child):                     return "NOT (\(summarize(child)))"
        case .always:                             return "always"
        case .never:                              return "never"
        }
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private static func days(_ t: TimeInterval) -> String {
        let days = Int(t / 86_400)
        if days >= 1 { return "\(days)d" }
        let hours = Int(t / 3600)
        return "\(hours)h"
    }

    private static func minutes(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return "\(m) min"
    }
}
