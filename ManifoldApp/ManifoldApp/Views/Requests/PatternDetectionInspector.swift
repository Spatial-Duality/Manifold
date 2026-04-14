// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// PatternDetectionInspector — "you denied this pattern 3 times — want a
// rule?" inspector. Surfaces when the denial pattern crosses a threshold.

import SwiftUI
import ManifoldKit

struct PatternDetectionInspector: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text("Patterns")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title3)
                        .foregroundStyle(ManifoldPalette.attention)
                    Text("No patterns yet")
                        .font(ManifoldType.bodyMedium)
                    Text("When you deny the same request shape three or more times, Manifold offers to turn it into a rule. You'll see the matching files and a 14-day denial chart.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(ManifoldPalette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.s3)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.r4)
                        .fill(ManifoldPalette.attentionSoft)
                )
            }
            .padding(Spacing.s4)
        }
    }
}
