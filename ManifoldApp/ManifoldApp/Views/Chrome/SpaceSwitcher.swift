// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SpaceSwitcher: View {
    @Binding var selection: LedgerDestination

    var body: some View {
        Picker("Space", selection: $selection) {
            ForEach(LedgerDestination.allCases) { destination in
                Text(destination.title)
                    .tag(destination)
                    .help(destination.title)
                    .accessibilityLabel(destination.title)
                    .accessibilityIdentifier("ledger.space.\(destination.id)")
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.s3)
        .padding(.top, Spacing.s2)
        .padding(.bottom, Spacing.s2)
        .accessibilityIdentifier("ledger.spaceSwitcher")
    }
}
