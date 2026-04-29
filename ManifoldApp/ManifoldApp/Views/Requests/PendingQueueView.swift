// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RequestsQueueView — vertical stack of approval request cards, newest at top.
// Each card is self-contained: agent avatar, headline, target, context,
// and the CommitLadder. Privacy exposure cards get a redacted preview with
// category chips, severity bar, and a one-click "Save as rule" affordance.

import SwiftUI
import ManifoldKit

struct RequestsQueueView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s3) {
                ForEach(store.pendingRequests) { request in
                    ApprovalRequestCard(request: request, store: store)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .push(from: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .padding(Spacing.s4)
        }
        .animation(ManifoldMotion.state, value: store.pendingRequests)
        .accessibilityIdentifier("requests.queue")
    }
}

struct ApprovalRequestCard: View {
    let request: ApprovalRequest
    let store: ManifoldStore
    @State private var savedRuleID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s2) {
                GradientAvatar(agent: request.agent, size: .medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.headline)
                        .font(ManifoldType.bodyMedium)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(request.createdAt.formatted(.relative(presentation: .named)))
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                operationPill
            }

            Label {
                Text(request.target)
                    .font(ManifoldType.mono)
                    .padding(.horizontal, Spacing.s1)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
            }

            Text(request.context)
                .font(ManifoldType.caption)
                .foregroundStyle(.tertiary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)

            if request.kind == .privacyExposure {
                privacyDecisionSummary
                privacyDetails
            }

            actionRow
        }
        .padding(Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("requests.card.\(request.id)")
    }

    private var operationPill: some View {
        Pill(text: operationLabel, variant: operationVariant)
    }

    private var operationLabel: String {
        switch request.operation {
        case .readFile, .readFolder: return "read"
        case .write:                 return "write"
        case .searchContent:         return "search"
        case .listDirectory:         return "list"
        case .mailboxRead:           return "mail"
        }
    }

    private var operationVariant: Pill.Variant {
        switch request.operation {
        case .write:        return .attention
        case .mailboxRead:  return .agent(.codex)
        default:            return .agent(request.agent)
        }
    }

    // MARK: - Privacy exposure details

    private var privacyDecisionSummary: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.s2)],
            alignment: .leading,
            spacing: Spacing.s2
        ) {
            PrivacyDecisionTile(
                title: "Detected",
                value: privacyDetectionLabel,
                systemImage: "sparkles.rectangle.stack",
                variant: request.severity == .critical || request.severity == .high ? .attention : .scope
            )
            PrivacyDecisionTile(
                title: "Default Safe Share",
                value: "Redacted",
                systemImage: "text.badge.checkmark",
                variant: .defaultScope
            )
            PrivacyDecisionTile(
                title: "Remember",
                value: primaryCategory?.displayName ?? "Rule option",
                systemImage: "text.badge.plus",
                variant: .preview
            )
        }
        .accessibilityIdentifier("requests.privacy.decisionSummary")
    }

    private var privacyDetectionLabel: String {
        if let severity = request.severity, severity != .none {
            return severity.rawValue.capitalized
        }
        if let category = request.matchedCategories.first {
            return category.displayName
        }
        return "Review"
    }

    /// Severity bar + category chips + findings summary + redacted preview.
    /// The original payload is never persisted on-disk, so this surface
    /// stands in for a true side-by-side diff: it is the authoritative
    /// rendering of what the agent would actually see.
    @ViewBuilder
    private var privacyDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .center, spacing: Spacing.s3) {
                if let severity = request.severity {
                    PrivacySeverityBar(severity: severity)
                }
                if !request.matchedCategories.isEmpty {
                    HStack(spacing: Spacing.s1) {
                        ForEach(request.matchedCategories, id: \.self) { category in
                            CategoryChip(category: category, compact: true)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let findings = request.findingsSummary, !findings.isEmpty {
                Text(findings)
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let preview = request.redactedPreview, !preview.isEmpty {
                redactedPane(preview: preview)
            }
        }
        .accessibilityIdentifier("requests.privacy.details")
    }

    private func redactedPane(preview: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(spacing: Spacing.s1) {
                Circle()
                    .fill(ManifoldPalette.active)
                    .frame(width: 6, height: 6)
                Text("Redacted — what the agent sees")
                    .font(ManifoldType.tiny)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(ManifoldPalette.text2)
            }
            ScrollView(.vertical, showsIndicators: true) {
                Text(attributedRedacted(from: preview))
                    .font(ManifoldType.monoBody)
                    .foregroundStyle(ManifoldPalette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Spacing.s2)
            }
            .frame(maxHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(ManifoldPalette.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
            )
        }
        .accessibilityIdentifier("requests.privacy.preview")
    }

    /// Tint each `[CATEGORY REDACTED]` token with its category color so the
    /// user sees *what kind* of thing was replaced and *where*. Mirrors the
    /// logic in PrivacyDiffView.
    private func attributedRedacted(from text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for category in PrivacyCategory.allCases {
            let token = category.replacementToken
            guard !token.isEmpty else { continue }
            var cursor = attributed.startIndex
            while cursor < attributed.endIndex {
                let remainder = attributed[cursor..<attributed.endIndex]
                guard let relative = remainder.range(of: token, options: .caseInsensitive) else { break }
                let lower = relative.lowerBound
                let upper = relative.upperBound
                attributed[lower..<upper].backgroundColor = CategoryChip.color(for: category).opacity(0.18)
                attributed[lower..<upper].foregroundColor = CategoryChip.color(for: category)
                attributed[lower..<upper].font = ManifoldType.monoBody
                cursor = upper
            }
        }
        return attributed
    }

    // MARK: - Action row

    @ViewBuilder
    private var actionRow: some View {
        switch request.kind {
        case .standingWrite:
            CommitLadder(
                agent: request.agent,
                showsSessionScope: request.supportsSessionScope && store.activeSession != nil,
                onNotThisTime: { Task { await store.answer(request, with: .notThisTime) } },
                onOnce:        { Task { await store.answer(request, with: .once) } },
                onSession:     { Task {
                    guard let sid = store.activeSession?.id else { return }
                    await store.answer(request, with: .forSession(sessionID: sid))
                } },
                onDefault:     { Task { await store.answer(request, with: .addToDefault) } }
            )
        case .privacyExposure:
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(alignment: .center, spacing: Spacing.s2) {
                    PrivacyApprovalButtons(
                        onDeny: { Task { await store.answer(request, with: .notThisTime) } },
                        onShareRedacted: { Task { await store.answer(request, with: .shareRedacted) } },
                        onShareOriginal: { Task { await store.answer(request, with: .shareOriginalOnce) } }
                    )
                    Spacer()
                    rememberRuleMenu
                }

                Text("Deny stops this share. Share Redacted sends only the filtered text above. Share Original Once does not change future policy.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Promote the privacy finding into a persistent rule. The menu mirrors
    /// the backend actions a privacy rule can actually take today: allow,
    /// deny, warn, redact, or log. "Ask every time" still belongs to the
    /// agent privacy policy, not RuleStore.
    @ViewBuilder
    private var rememberRuleMenu: some View {
        Menu {
            if let category = primaryCategory {
                Button {
                    Task {
                        await savePrivacyRule(
                            name: "Redact \(category.displayName.lowercased()) before sharing",
                            matcher: .privacyContainsCategory(category),
                            action: .redact,
                            explanation: "Created from a privacy review. Sends filtered text when \(category.displayName.lowercased()) appears."
                        )
                    }
                } label: {
                    Label("Redact this category", systemImage: "text.badge.checkmark")
                }

                Button {
                    Task {
                        await savePrivacyRule(
                            name: "Block \(category.displayName.lowercased()) before sharing",
                            matcher: .privacyContainsCategory(category),
                            action: .deny,
                            explanation: "Created from a privacy review. Blocks \(category.displayName.lowercased()) before an agent sees it."
                        )
                    }
                } label: {
                    Label("Block this category", systemImage: "hand.raised")
                }

                Button {
                    Task {
                        await savePrivacyRule(
                            name: "Warn on \(category.displayName.lowercased())",
                            matcher: .privacyContainsCategory(category),
                            action: .warn,
                            explanation: "Created from a privacy review. Allows the share but records a warning."
                        )
                    }
                } label: {
                    Label("Warn and record", systemImage: "exclamationmark.triangle")
                }
            }

            if let severity = request.severity, severity != .none {
                Divider()
                Button {
                    Task {
                        await savePrivacyRule(
                            name: "Block \(severity.rawValue) privacy findings",
                            matcher: .privacySeverityAtLeast(severity),
                            action: .deny,
                            explanation: "Created from a privacy review. Blocks privacy findings at \(severity.rawValue) severity or above."
                        )
                    }
                } label: {
                    Label("Block this severity and above", systemImage: "gauge.with.dots.needle.67percent")
                }
            }

            Divider()
            Button {
                Task {
                    await savePrivacyRule(
                        name: "Redact My Identity before sharing",
                        matcher: .privacyMatchesMyIdentity,
                        action: .redact,
                        explanation: "Redacts registered My Identity matches before content is shared."
                    )
                }
            } label: {
                Label("Redact My Identity", systemImage: "person.text.rectangle")
            }

            Button {
                Task {
                    await savePrivacyRule(
                        name: "Keep public or company allowlist",
                        matcher: .privacyInOrgAllowlist,
                        action: .allow,
                        explanation: "Allows privacy findings only when they are covered by the public/company allowlist."
                    )
                }
            } label: {
                Label("Keep allowlisted public data", systemImage: "checkmark.shield")
            }
        } label: {
            Label(savedRuleID == nil ? "Remember" : "Rule saved",
                  systemImage: savedRuleID == nil ? "text.badge.plus" : "checkmark.seal.fill")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .disabled(savedRuleID != nil)
        .help("Turn this privacy decision into a durable rule.")
        .accessibilityIdentifier("requests.action.saveRule")
    }

    private func savePrivacyRule(
        name: String,
        matcher: RuleMatcher,
        action: ManifoldKit.RuleAction,
        explanation: String
    ) async {
        let iso = ISO8601DateFormatter.shared.string(from: Date())
        let rule = RuleRecord(
            id: "rule-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            explanation: explanation,
            scope: .agent,
            matcher: matcher,
            action: action,
            agents: [request.agent],
            window: .always,
            source: .user,
            enabled: true,
            orderIndex: 100,
            createdAt: iso,
            updatedAt: iso
        )
        await store.rules.addRule(rule)
        savedRuleID = rule.id
    }

    private struct PrivacyDecisionTile: View {
        let title: String
        let value: String
        let systemImage: String
        let variant: Pill.Variant

        var body: some View {
            HStack(spacing: Spacing.s2) {
                Image(systemName: systemImage)
                    .foregroundStyle(variant.color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(value)
                        .font(ManifoldType.captionMedium)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.s2)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(variant.color.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .strokeBorder(variant.color.opacity(0.18), lineWidth: 0.5)
            )
        }
    }

    /// Pick the most severe matched category to anchor the rule. Falls back
    /// to the first category when severity ranking ties.
    private var primaryCategory: PrivacyCategory? {
        let order: [PrivacyCategory] = [.secret, .accountNumber, .privatePerson, .email, .phone, .address, .url, .date]
        for candidate in order where request.matchedCategories.contains(candidate) {
            return candidate
        }
        return request.matchedCategories.first
    }

}

struct PrivacyApprovalButtons: View {
    var onDeny: () -> Void = {}
    var onShareRedacted: () -> Void = {}
    var onShareOriginal: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.s1) {
            Button("Deny", action: onDeny)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ManifoldPalette.attention)
                .accessibilityIdentifier("requests.action.deny")

            Button("Share Redacted", action: onShareRedacted)
                .keyboardShortcut(.return, modifiers: .shift)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(ManifoldPalette.active)
                .accessibilityIdentifier("requests.action.shareRedacted")

            Button("Share Original Once", action: onShareOriginal)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("requests.action.shareOriginalOnce")
        }
    }
}
