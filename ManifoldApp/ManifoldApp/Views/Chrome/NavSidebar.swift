// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// NavSidebar — the 5-item Ledger sidebar.
//
// Reads as a narrow rail of "evidence categories", not an app's "tabs".
// Destination icons are SF Symbols, destination order is fixed, and the
// sidebar does not scroll. Accessibility labels use the destination
// title; per-row tooltips give the plain-language subtitle.

import SwiftUI
import ManifoldKit

struct NavSidebar: View {
    @Binding var selection: LedgerDestination
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(LedgerDestination.allCases) { dest in
                    NavRow(
                        destination: dest,
                        isSelected: selection == dest,
                        pendingCount: badgeCount(for: dest)
                    )
                    .tag(dest)
                }
            } header: {
                HStack(spacing: Spacing.s2) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(ManifoldPalette.claude)
                    Text("Manifold")
                        .font(ManifoldType.title)
                }
                .padding(.vertical, Spacing.s1)
            }

            if let session = store.activeSession {
                Section("Session") {
                    SessionChip(
                        name: session.name,
                        remainingSeconds: session.remainingSeconds,
                        isTrackedEdit: session.isTrackedEdit
                    )
                    .padding(.vertical, Spacing.s1)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func badgeCount(for dest: LedgerDestination) -> Int {
        dest == .requests ? store.pendingRequests.count : 0
    }
}

/// A single nav row. Selected state uses a tinted accent fill; the badge
/// is ManifoldPalette.attention so it reads as "waiting on you" (never
/// confused with Claude's default color).
private struct NavRow: View {
    let destination: LedgerDestination
    let isSelected: Bool
    let pendingCount: Int

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? ManifoldPalette.claude : ManifoldPalette.text2)
                .frame(width: 18, alignment: .center)

            Text(destination.title)
                .font(ManifoldType.body)
                .foregroundStyle(isSelected ? ManifoldPalette.text : ManifoldPalette.text2)

            Spacer()

            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(ManifoldType.numericCaption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(ManifoldPalette.attention))
                    .accessibilityLabel("\(pendingCount) pending")
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(destination.title)
        .accessibilityHint(destination.emptySubtitle)
    }
}
