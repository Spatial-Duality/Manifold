// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// B-06: About window — app icon, version, copyright, links.
struct AboutView: View {
    var body: some View {
        VStack(spacing: Spacing.s3) {
            GradientAvatar(app: true, size: .extraLarge)
                .padding(.bottom, Spacing.s1)

            Text("Manifold")
                .font(ManifoldType.heading)

            Text("Version \(Bundle.main.shortVersionString)")
                .font(ManifoldType.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("Control what Claude and Codex can see here.")
                .font(ManifoldType.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .frame(width: 200)

            Text("© 2026 Spatial Duality. Apache License 2.0.")
                .font(ManifoldType.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(Spacing.s7)
        .frame(width: 320)
    }
}
