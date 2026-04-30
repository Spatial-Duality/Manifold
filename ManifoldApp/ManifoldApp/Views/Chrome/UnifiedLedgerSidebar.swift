// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct UnifiedLedgerSidebar: View {
    @Binding var destination: LedgerDestination
    @Binding var accessSection: AccessSection
    let work: WorkModel

    var body: some View {
        VStack(spacing: 0) {
            SpaceSwitcher(selection: $destination)
            Divider()

            switch destination {
            case .work:
                WorkNavigator(work: work)
            case .access:
                AccessNavigator(selection: $accessSection)
            case .mail:
                MailNavigator()
            case .rules:
                RulesNavigator()
            }
        }
        .navigationSplitViewColumnWidth(min: 248, ideal: 284, max: 340)
        .accessibilityIdentifier("ledger.sidebar")
    }
}
