import SwiftUI
import ManifoldKit

/// Dashboard-style agent card for the Overview tab.
/// Shows: agent identity (color border + tint), connection state, file/email summaries,
/// recent activity, and per-agent controls. Fills viewport with real data.
struct AgentPolicyCard: View {
    let agentName: String
    let agentColor: Color
    let isConnected: Bool
    let policy: AgentAccessPolicy?
    let totalSources: Int
    let recentActivity: [AuditEntry]
    let sourceNames: [String]
    let isPaused: Bool
    let onPauseToggle: () -> Void
    let onReviewAccess: () -> Void
    let onViewActivity: () -> Void

    @State private var isHovered = false

    private var sourceCount: Int { policy?.allowedSourceIDs.count ?? 0 }
    private var domainCount: Int { policy?.allowedEmailDomains.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, Spacing.standard)

            Divider()
                .padding(.vertical, Spacing.standard)

            // Source names with access dots
            sourceSummary
                .padding(.bottom, Spacing.standard)

            // Email summary
            emailSummary
                .padding(.bottom, Spacing.standard)

            Divider()
                .padding(.vertical, Spacing.standard)

            // Recent activity (up to 3 events)
            if !recentActivity.isEmpty {
                recentActivitySection
                    .padding(.bottom, Spacing.standard)

                Divider()
                    .padding(.vertical, Spacing.standard)
            }

            // Actions
            actionsRow
        }
        .padding(Spacing.edge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(agentColor.opacity(Opacity.rowTint))
        }
        .overlay {
            if isPaused {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.statusPaused.opacity(0.3), lineWidth: 0.5)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(isHovered ? 0.12 : 0.08), radius: isHovered ? 5 : 3, y: isHovered ? 2 : 1)
        .onHover { isHovered = $0 }
        .animation(Anim.micro, value: isHovered)
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
                .animation(Anim.stateChange, value: isConnected)

            Text(agentName)
                .font(Typ.heading)

            Text(isPaused ? "Paused" : "Active")
                .font(Typ.caption.weight(.medium))
                .foregroundStyle(isPaused ? Color.statusPaused : agentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (isPaused ? Color.statusPaused : agentColor).opacity(Opacity.badgeFill),
                    in: Capsule()
                )

            if !isConnected && !isPaused {
                Label("Not Connected", systemImage: "exclamationmark.circle")
                    .font(Typ.caption.weight(.medium))
                    .foregroundStyle(Color.statusWarning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.statusWarning.opacity(Opacity.badgeFill), in: Capsule())
            }

            Spacer()

            Button(isPaused ? "Resume Access" : "Pause Access", action: onPauseToggle)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isPaused ? .statusActive : .statusDanger)
                .accessibilityLabel(isPaused ? "Resume access for \(agentName)" : "Pause access for \(agentName)")
        }
    }

    // MARK: - Source Summary

    private var sourceSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack(spacing: Spacing.tight) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                if sourceCount > 0 {
                    Text("\(sourceCount)")
                        .font(.callout.weight(.medium))
                        .contentTransition(.numericText())
                    Text("of \(totalSources) sources")
                        .font(Typ.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No file access")
                        .font(Typ.body)
                        .foregroundStyle(.tertiary)
                }
            }

            // Show source folder names with access dots
            if !sourceNames.isEmpty {
                ForEach(sourceNames.prefix(5), id: \.self) { name in
                    HStack(spacing: Spacing.tight) {
                        Circle()
                            .fill(agentColor)
                            .frame(width: 5, height: 5)
                        Text(name)
                            .font(Typ.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 20)
                }
                if sourceNames.count > 5 {
                    Text("+\(sourceNames.count - 5) more")
                        .font(Typ.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 20)
                }
            }
        }
    }

    // MARK: - Email Summary

    private var emailSummary: some View {
        HStack(spacing: Spacing.tight) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            if domainCount > 0 {
                Text("\(domainCount)")
                    .font(.callout.weight(.medium))
                    .contentTransition(.numericText())
                Text("^[\(domainCount) domain](inflect: true) visible")
                    .font(Typ.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("No email access")
                    .font(Typ.body)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text("Recent")
                .font(Typ.caption.weight(.medium))
                .foregroundStyle(.tertiary)

            ForEach(recentActivity.prefix(3)) { entry in
                HStack(spacing: Spacing.standard) {
                    Image(systemName: ActionFormatting.icon(for: entry.action))
                        .foregroundStyle(ActionFormatting.color(for: entry.action))
                        .imageScale(.small)
                        .frame(width: 14)
                    Text(ActionFormatting.description(for: entry))
                        .font(Typ.caption)
                        .lineLimit(1)
                    Spacer()
                    TimeLabel(iso8601: entry.timestamp)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: Spacing.standard) {
            Button("Update Access\u{2026}", action: onReviewAccess)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Activity", systemImage: "waveform.path", action: onViewActivity)
                .labelStyle(.titleAndIcon)
                .buttonStyle(.plain)
                .font(Typ.caption)
                .foregroundStyle(.secondary)
        }
    }
}
