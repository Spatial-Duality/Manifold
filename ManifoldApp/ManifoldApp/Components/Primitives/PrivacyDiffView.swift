// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// PrivacyDiffView — side-by-side redaction preview.
//
// Shown in the approval queue when an agent asks to read content the
// privacy model flagged. The left pane shows the original with category
// spans highlighted; the right pane shows what the agent would actually
// see after redaction. Categories legend + severity read along the top
// so the user can make the call in under two seconds.

import SwiftUI
import ManifoldKit

struct PrivacyDiffView: View {
    let originalText: String
    let redactedText: String
    let categories: [PrivacyCategory]
    let severity: PrivacySeverity
    let findingsSummary: String
    var maxHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            header
            panes
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
        .accessibilityIdentifier("privacy.diff")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            PrivacySeverityBar(severity: severity)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(findingsSummary.isEmpty ? "Privacy review" : findingsSummary)
                    .font(ManifoldType.bodyMedium)
                    .foregroundStyle(ManifoldPalette.text)
                if !categories.isEmpty {
                    HStack(spacing: Spacing.s1) {
                        ForEach(categories, id: \.self) { category in
                            CategoryChip(category: category, compact: true)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("privacy.diff.header")
    }

    private var panes: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            pane(title: "Original", accent: ManifoldPalette.attention) {
                Text(originalText)
                    .font(ManifoldType.monoBody)
                    .foregroundStyle(ManifoldPalette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            pane(title: "Redacted — what the agent sees", accent: ManifoldPalette.active) {
                Text(attributedRedacted)
                    .font(ManifoldType.monoBody)
                    .foregroundStyle(ManifoldPalette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .accessibilityIdentifier("privacy.diff.panes")
    }

    private func pane<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s1) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(ManifoldType.tiny)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(ManifoldPalette.text2)
            }
            ScrollView(.vertical, showsIndicators: true) {
                content()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Spacing.s2)
            }
            .frame(maxHeight: maxHeight)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(ManifoldPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// Tint each `[CATEGORY REDACTED]` token inside the redacted text with
    /// its category color so the user can see at a glance *what kind* of
    /// thing was replaced and *where*. Category-agnostic surrounding text
    /// stays in the default body color.
    private var attributedRedacted: AttributedString {
        var attributed = AttributedString(redactedText)
        for category in PrivacyCategory.allCases {
            let token = category.replacementToken
            guard !token.isEmpty else { continue }
            // AttributedString has no ranged `range(of:in:)`. Walk matches
            // by slicing the substring after each hit and rebinding indices.
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
}

#Preview("PrivacyDiffView") {
    PrivacyDiffView(
        originalText: "From: ada@acme.com\nHi team, please wire $4,500 to account 1234-5678 — secret key: sk_live_abc123...",
        redactedText: "From: [EMAIL REDACTED]\nHi team, please wire $4,500 to account [ACCOUNT REDACTED] — secret key: [SECRET REDACTED]...",
        categories: [.email, .accountNumber, .secret],
        severity: .critical,
        findingsSummary: "1 email, 1 account, 1 secret — critical"
    )
    .padding(Spacing.s5)
    .frame(width: 720)
    .background(ManifoldPalette.bg)
}
