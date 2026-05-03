// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// Ledger search metadata.
//
// The actual search field is system-owned via `.searchable` on the
// `NavigationSplitView`, so macOS controls placement, sizing, activation,
// and Liquid Glass treatment.

import SwiftUI

extension LedgerDestination {
    var searchPrompt: String {
        switch self {
        case .work: return "Search work"
        case .access: return "Search access"
        case .mail: return "Search mail"
        case .rules: return "Search rules"
        }
    }
}
