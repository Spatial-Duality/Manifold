import SwiftUI

/// One-time boundary notice shown before the first "Grant to Claude."
/// Sets correct expectations about what Manifold does and doesn't control.
struct GuardrailNotice: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.checkered")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("What Manifold controls")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Label(
                    "Local files in the managed workspace",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)

                Label(
                    "Every file modification is tracked and versioned",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)

                Label(
                    "Restore any previous version with one click",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)

                Divider()

                Label(
                    "Claude connectors and plugins",
                    systemImage: "xmark.circle"
                )
                .foregroundStyle(.secondary)

                Label(
                    "Computer use and network access",
                    systemImage: "xmark.circle"
                )
                .foregroundStyle(.secondary)

                Label(
                    "Actions outside the workspace boundary",
                    systemImage: "xmark.circle"
                )
                .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 8)

            Text("Manifold applies to local files in the workspace only. External capabilities are outside this boundary.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Button("I understand") {
                onAccept()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 420)
    }
}

#Preview("Guardrail Notice") {
    GuardrailNotice { }
}
