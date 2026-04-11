import SwiftUI

/// B-06: About window — app icon, version, copyright, links.
struct AboutView: View {
    var body: some View {
        VStack(spacing: Spacing.section) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Manifold")
                .font(Typ.sectionTitle)

            Text("Version \(Bundle.main.shortVersionString)")
                .font(Typ.caption)
                .foregroundStyle(.secondary)

            Text("Control what AI agents can see on your Mac.")
                .font(Typ.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 200)

            Text("\u{00A9} 2026 Spatial Duality. All rights reserved.")
                .font(Typ.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(Spacing.xlarge)
        .frame(width: 320)
    }
}
