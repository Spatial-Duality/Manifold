import SwiftUI

/// One-time boundary notice shown before the first "Grant to Claude."
/// Sets correct expectations about what Manifold does and doesn't control.
struct GuardrailNotice: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("What Manifold controls")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                GuardrailRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    text: "Local files in the managed workspace"
                )
                GuardrailRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    text: "Every file modification is tracked and versioned"
                )
                GuardrailRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    text: "Restore any previous version with one click"
                )

                Divider()

                GuardrailRow(
                    icon: "xmark.circle",
                    color: .secondary,
                    text: "Claude connectors and plugins"
                )
                GuardrailRow(
                    icon: "xmark.circle",
                    color: .secondary,
                    text: "Computer use and network access"
                )
                GuardrailRow(
                    icon: "xmark.circle",
                    color: .secondary,
                    text: "Actions outside the workspace boundary"
                )
            }
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

struct GuardrailRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 13))
        }
    }
}

#Preview("Guardrail Notice") {
    GuardrailNotice { }
}
