// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RecentAnswersView — recently-answered requests, grouped by hour/day.
// Same card shape with an answer chip in the top-right.

import SwiftUI
import ManifoldKit

struct RecentAnswersView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Recent answers")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .padding(.horizontal, Spacing.s4)
                    .padding(.top, Spacing.s2)

                Text("Each answer you give shows up here so you can reverse course without hunting through the ledger.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Spacing.s4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
