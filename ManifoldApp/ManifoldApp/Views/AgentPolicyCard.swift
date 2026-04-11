import SwiftUI
import ManifoldKit

/// Glanceable agent badge for the Overview tab.
/// Shows: agent name + state chip + pause button, file/email summaries, actions.
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

    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: agent + state chip + pause button
            headerRow
                .padding(.bottom, Spacing.standard)

            Divider()
                .padding(.vertical, Spacing.standard)

            // Summaries with stronger number emphasis
            VStack(alignment: .leading, spacing: Spacing.tight) {
                fileSummaryRow
                emailSummaryRow
            }
            .padding(.bottom, Spacing.standard)

            Divider()
                .padding(.vertical, Spacing.standard)

            // Actions
            actionsRow
        }
        .padding(Spacing.edge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isPaused ? .orange.opacity(0.3) : .separator, lineWidth: isPaused ? 1 : 0.5)
        }
        .opacity(isPaused ? 0.75 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(agentName) access card, \(isPaused ? "paused" : "active")")
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? agentColor : .gray)
                .frame(width: 10, height: 10)
                .animation(.snappy, value: isConnected)

            Text(agentName)
                .font(.headline)

            // State chip — user always knows current access state
            Text(isPaused ? "Paused" : "Active")
                .font(.caption.weight(.medium))
                .foregroundStyle(isPaused ? .orange : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (isPaused ? Color.orange : agentColor).opacity(0.12),
                    in: Capsule()
                )

            // Connection status — problems are louder than success
            if isConnected {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Not Connected", systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.12), in: Capsule())
            }

            Spacer()

            // Pause/Resume — styled as bordered button with consequence
            Button(isPaused ? "Resume Access" : "Pause Access") {
                onPauseToggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isPaused ? .green : .red)
            .accessibilityLabel(isPaused ? "Resume access for \(agentName)" : "Pause access for \(agentName)")
            .accessibilityHint(isPaused ? "Resumes \(agentName) file and email access" : "Immediately suspends all \(agentName) access")
        }
    }

    // MARK: - Summaries

    private var fileSummaryRow: some View {
        HStack(spacing: Spacing.tight) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            if sourceCount > 0 {
                Text("\(sourceCount)")
                    .font(.callout.weight(.medium))
                    .contentTransition(.numericText())
                Text("of \(totalSources) sources")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("No file access")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var emailSummaryRow: some View {
        HStack(spacing: Spacing.tight) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            if emailAccountCount > 0 {
                Text("\(emailAccountCount)")
                    .font(.callout.weight(.medium))
                    .contentTransition(.numericText())
                Text("domain\(emailAccountCount == 1 ? "" : "s") visible")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                // Actionable — navigate to Emails tab
                Button {
                    store.selectedTab = .emails
                } label: {
                    HStack(spacing: Spacing.tight) {
                        Text("Set up email access")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: Spacing.section) {
            Button("Update Access\u{2026}", action: onReviewAccess)
                .controlSize(.regular)

            Button(action: onViewActivity) {
                Label("Activity", systemImage: "waveform.path")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
