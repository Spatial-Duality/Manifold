// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EmptyStateIllustration — glowing card + icon composite.
//
// Used by every "nothing is here yet" surface (empty Access, empty Mail,
// empty Requests). Gentle not celebratory — an empty state in a trust
// product is the default state, and should feel calm.

import SwiftUI

struct EmptyStateIllustration: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var tint: Color = ManifoldPalette.claude

    var body: some View {
        VStack(spacing: Spacing.s4) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 92, height: 92)
                    .blur(radius: 24)
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(tint)
            }
            .frame(height: 120)

            VStack(spacing: Spacing.s1) {
                Text(title)
                    .font(ManifoldType.heading)
                    .foregroundStyle(ManifoldPalette.text)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(ManifoldType.body)
                        .foregroundStyle(ManifoldPalette.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 360)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle ?? "")")
    }
}

#Preview("Empty state — folders") {
    EmptyStateIllustration(
        systemImage: "folder.badge.plus",
        title: "No folders shared yet",
        subtitle: "Nothing is shared until you share it. Add a folder to let Claude or Codex read it inside a session."
    )
    .frame(width: 520, height: 360)
    .background(ManifoldPalette.bg)
}

#Preview("Empty state — requests") {
    EmptyStateIllustration(
        systemImage: "checkmark.seal",
        title: "Nothing is waiting on you",
        subtitle: "When an agent asks for access it will land here. Requests get answered in a ladder — deny, once, session, default.",
        tint: ManifoldPalette.active
    )
    .frame(width: 520, height: 360)
    .background(ManifoldPalette.bg)
}
