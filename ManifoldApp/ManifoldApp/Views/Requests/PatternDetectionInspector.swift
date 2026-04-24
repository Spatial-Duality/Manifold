// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// PatternDetectionInspector — "you denied this pattern 3 times — want a
// rule?" inspector. Surfaces when the denial pattern crosses a threshold.

import SwiftUI
import ManifoldKit

struct PatternDetectionInspector: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(ManifoldPalette.attention)
                Text("No repeated denials yet")
                    .font(ManifoldType.captionMedium)
            }
            Text("After the same request shape is denied three times, Manifold offers a suggested rule with its matching files, emails, or privacy categories.")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.s1) {
                Pill(text: "3x deny", variant: .attention)
                Pill(text: "suggest rule", variant: .preview)
            }
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.attentionSoft.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.attention.opacity(0.18), lineWidth: 0.5)
        )
        .accessibilityIdentifier("requests.patterns")
    }
}
