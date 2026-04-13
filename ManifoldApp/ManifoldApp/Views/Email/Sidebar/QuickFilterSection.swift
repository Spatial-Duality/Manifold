// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct QuickFilterSection: View {
    @Bindable var selection: EmailSelectionModel
    @State private var showOverflow = false

    var body: some View {
        Section("Favorites") {
            ForEach(QuickFilter.defaultVisible) { filter in
                filterButton(for: filter)
            }

            DisclosureGroup("More Filters", isExpanded: $showOverflow) {
                ForEach(QuickFilter.overflow) { filter in
                    filterButton(for: filter)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func filterButton(for filter: QuickFilter) -> some View {
        Button {
            if selection.activeFilter == filter {
                selection.activeFilter = nil
            } else {
                selection.activateFilter(filter)
            }
        } label: {
            Label(filter.displayName, systemImage: filter.systemImage)
                .foregroundStyle(selection.activeFilter == filter ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .fontWeight(selection.activeFilter == filter ? .medium : .regular)
    }
}
