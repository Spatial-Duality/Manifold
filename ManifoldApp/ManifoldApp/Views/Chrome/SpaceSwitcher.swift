// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SpaceSwitcher: View {
    @Binding var selection: LedgerDestination
    @State private var hoveredDestination: LedgerDestination?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LedgerDestination.allCases) { destination in
                Button {
                    selection = destination
                } label: {
                    Label(destination.title, systemImage: destination.systemImage)
                        .font(ManifoldType.captionMedium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .padding(.horizontal, Spacing.s2)
                        .background(tabBackground(for: destination))
                        .foregroundStyle(selection == destination ? ManifoldPalette.text : ManifoldPalette.text2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredDestination = isHovering ? destination : nil
                }
                .accessibilityIdentifier("ledger.space.\(destination.id)")
                .accessibilityLabel(destination.title)
                .accessibilityAddTraits(selection == destination ? .isSelected : [])
            }
        }
        .padding(2)
        // Liquid glass chrome — matches the brand header hover material so
        // the whole sidebar top reads as one chrome layer instead of brand
        // glass over flat surface3.
        .liquidGlass(cornerRadius: Spacing.r3)
        .padding(.horizontal, Spacing.s3)
        .padding(.top, Spacing.s2)
        .padding(.bottom, Spacing.s1)
        .accessibilityIdentifier("ledger.spaceSwitcher")
    }

    @ViewBuilder
    private func tabBackground(for destination: LedgerDestination) -> some View {
        let shape = RoundedRectangle(cornerRadius: Spacing.r2, style: .continuous)
        if selection == destination {
            shape.fill(ManifoldPalette.selectionSoft)
        } else if hoveredDestination == destination {
            shape.fill(ManifoldPalette.surface3.opacity(0.5))
        } else {
            shape.fill(Color.clear)
        }
    }
}
