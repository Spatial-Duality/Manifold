// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SpaceSwitcher: View {
    @Binding var selection: LedgerDestination

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
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.r2, style: .continuous)
                                .fill(selection == destination ? ManifoldPalette.selectionSoft : Color.clear)
                        )
                        .foregroundStyle(selection == destination ? ManifoldPalette.text : ManifoldPalette.text2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ledger.space.\(destination.id)")
                .accessibilityLabel(destination.title)
                .accessibilityAddTraits(selection == destination ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.surface3.opacity(0.7))
        )
        .padding(.horizontal, Spacing.s3)
        .padding(.top, Spacing.s2)
        .padding(.bottom, Spacing.s1)
        .accessibilityIdentifier("ledger.spaceSwitcher")
    }
}
