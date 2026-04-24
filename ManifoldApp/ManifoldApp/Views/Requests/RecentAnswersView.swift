// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RecentAnswersView — recently-answered requests, grouped by hour/day.
// Same card shape with an answer chip in the top-right.

import SwiftUI
import ManifoldKit

struct RecentAnswersView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            AnswerTraceRow(symbol: "arrow.uturn.backward", title: "Reversible by design", detail: "Temporary grants expire back to the default policy.")
            AnswerTraceRow(symbol: "list.bullet.rectangle", title: "Evidence lands in Activity", detail: "Approved, denied, and privacy-filtered decisions are kept with the session record.")
            AnswerTraceRow(symbol: "arrow.left.arrow.right", title: "Useful for handoff", detail: "Claude and Codex can build on recorded context without seeing everything.")
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}

private struct AnswerTraceRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2) {
            Image(systemName: symbol)
                .foregroundStyle(ManifoldPalette.selection)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(ManifoldType.captionMedium)
                Text(detail)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
