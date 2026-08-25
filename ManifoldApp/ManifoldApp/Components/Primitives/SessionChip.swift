// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SessionChip — "a session is live" marker.
//
// Green pulsing dot + "SESSION" kicker + session name. Appears in the
// menu bar panel and in the Ledger window's integrated toolbar.

import SwiftUI

struct SessionChip: View {
    let name: String
    var remainingSeconds: TimeInterval?
    var isTrackedEdit: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseOn = false

    var body: some View {
        HStack(spacing: Spacing.s2) {
            if isTrackedEdit {
                Image(systemName: "timeline.selection")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(ManifoldPalette.claude)
            } else {
                ZStack {
                    if !reduceMotion {
                        Circle()
                            .fill(ManifoldPalette.active.opacity(0.40))
                            .frame(width: 14, height: 14)
                            .scaleEffect(pulseOn ? 1.0 : 0.55)
                            .opacity(pulseOn ? 0 : 0.9)
                            .animation(ManifoldMotion.pulseEaseOut, value: pulseOn)
                            .onAppear { pulseOn = true }
                    }
                    Circle()
                        .fill(ManifoldPalette.active)
                        .frame(width: 7, height: 7)
                }
                .frame(width: 14, height: 14)
            }

            Text("SESSION")
                .font(ManifoldType.tiny)
                .foregroundStyle(.secondary)
                .tracking(0.4)

            Text(name)
                .font(ManifoldType.bodyMedium)
                .lineLimit(1)
                .truncationMode(.middle)

            if let remaining = remainingSeconds {
                Spacer(minLength: Spacing.s2)
                Text(Self.format(remaining))
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s1)
        .background(
            Capsule(style: .continuous)
                .fill((isTrackedEdit ? ManifoldPalette.claude : ManifoldPalette.active)
                    .opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    (isTrackedEdit ? ManifoldPalette.claude : ManifoldPalette.active)
                        .opacity(0.22),
                    lineWidth: 0.5
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session live: \(name)")
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

#Preview("Session chips") {
    VStack(spacing: Spacing.s4) {
        SessionChip(name: "Jane follow-up", remainingSeconds: 6120)
        SessionChip(name: "Writing sprint", remainingSeconds: 14400)
        SessionChip(name: "Refactor models", remainingSeconds: 1860, isTrackedEdit: true)
    }
    .padding(Spacing.s6)
    .background(ManifoldPalette.bg)
}
