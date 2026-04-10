import SwiftUI

/// Simplified glanceable agent badge for the Overview tab.
/// Shows: agent name + connection + pause, files summary line,
/// email summary line, action buttons.
/// NOT a dashboard — no per-source lists, no activity feed, no work block status.
struct AgentPolicyCard: View {
    let agentName: String
    let agentColor: Color
    let isConnected: Bool
    let sourceCount: Int
    let totalSources: Int
    let emailAccountCount: Int
    let isPaused: Bool
    let onPauseToggle: () -> Void
    let onReviewAccess: () -> Void
    let onViewActivity: () -> Void

    @State private var pauseHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            // Header: agent dot + name + connection + pause
            header

            // Files summary
            HStack(spacing: Spacing.tight) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                if sourceCount > 0 {
                    Text("\(sourceCount) of \(totalSources) sources")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No file access")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }

            // Email summary
            HStack(spacing: Spacing.tight) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                if emailAccountCount > 0 {
                    Text("\(emailAccountCount) email account\(emailAccountCount == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No email access")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }

            // Actions
            HStack(spacing: Spacing.section) {
                Button("Review & Update Access", action: onReviewAccess)
                    .controlSize(.regular)

                Button {
                    onViewActivity()
                } label: {
                    Text("View Activity →")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
        }
        .padding(Spacing.edge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(agentName) access card")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Circle()
                .fill(isConnected ? agentColor : .gray)
                .frame(width: 10, height: 10)

            Text(agentName)
                .font(.title3.weight(.medium))

            if isConnected {
                Text("connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: Capsule())
            } else {
                Text("disconnected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Pause Access button — emergency control
            Button {
                onPauseToggle()
            } label: {
                Text(isPaused ? "Resume Access" : "Pause Access")
                    .font(.callout)
                    .foregroundStyle(pauseButtonColor)
            }
            .buttonStyle(.plain)
            .onHover { pauseHovered = $0 }
        }
    }

    private var pauseButtonColor: Color {
        if isPaused { return .green }
        return pauseHovered ? .red : agentColor
    }
}
