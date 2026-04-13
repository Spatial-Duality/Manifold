// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Dashboard-style agent card matching the interactive prototype.
/// Left border in agent color, tinted background, sources/domains/activity inline,
/// per-agent pause/resume control.
struct AgentPolicyCard: View {
    let agentName: String
    let agentColor: Color
    let isConnected: Bool
    let policy: AgentAccessPolicy?
    let coverage: AgentCoverageSnapshot?
    let totalSources: Int
    let recentActivity: [AuditEntry]
    let sourceNames: [(name: String, count: Int, hasAccess: Bool)]
    let emailGovernance: AgentEmailGovernanceSummary?
    let isPaused: Bool
    let onPauseToggle: () -> Void
    let onReviewAccess: () -> Void
    let onViewActivity: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Left border accent (prototype Fix 1.2)
            RoundedRectangle(cornerRadius: 10)
                .fill(agentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 14) {
                headerRow
                sourcesSection
                emailGovernanceSection

                Divider()

                activitySection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(agentColor.opacity(Opacity.rowTint))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
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
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(agentColor)
                    .frame(width: 10, height: 10)
                Text(agentName)
                    .font(.system(size: 15, weight: .semibold))
                StatusBadge(
                    text: isPaused ? "Paused" : (isConnected ? "Connected" : "Offline"),
                    color: isPaused ? .statusPaused : (isConnected ? .statusActive : .secondary)
                )
                if let coverage {
                    StatusBadge(
                        text: coverage.coverageState.displayName,
                        color: coverageColor(coverage.coverageState)
                    )
                    StatusBadge(
                        text: coverage.verificationStatus.displayName,
                        color: coverage.verificationStatus == .verified ? .statusActive : .orange
                    )
                }
                if let policy {
                    StatusBadge(
                        text: policy.accessRecordingLevel.displayName,
                        color: .secondary
                    )
                }
            }
            Spacer()
            Button(isPaused ? "Resume Access" : "Pause Access", action: onPauseToggle)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOURCES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            ForEach(sourceNames.prefix(5), id: \.name) { source in
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(source.name)
                            .font(Typ.body)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Text("^[\(source.count) file](inflect: true)")
                            .font(Typ.numericCaption)
                            .foregroundStyle(.tertiary)
                        Circle()
                            .fill(source.hasAccess ? Color.statusActive : Color.gray)
                            .frame(width: 6, height: 6)
                    }
                }
            }

            if sourceNames.count > 5 {
                Text("+\(sourceNames.count - 5) more")
                    .font(Typ.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Email Governance

    private var emailGovernanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EMAIL GOVERNANCE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            if let emailGovernance {
                governanceRow(systemImage: "shield", text: "\(emailGovernance.enabledShieldCount) active shields")
                governanceRow(
                    systemImage: "line.3.horizontal.decrease.circle",
                    text: "\(emailGovernance.domainRuleCount) domain rules · \(emailGovernance.contactRuleCount) contacts · \(emailGovernance.keywordRuleCount) keywords"
                )
                governanceRow(
                    systemImage: "dial.low",
                    text: "Sensitivity: \(emailGovernance.emailSensitivity.displayName)"
                )
                governanceRow(
                    systemImage: "gearshape",
                    text: "Default: \(emailGovernance.defaultPolicy.displayName)"
                )
            } else {
                Text("Email policy unavailable")
                    .font(Typ.body)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func governanceRow(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(Typ.body)
            Spacer()
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT ACTIVITY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            if recentActivity.isEmpty {
                Text("No recent activity")
                    .font(Typ.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(recentActivity.prefix(3)) { entry in
                    HStack {
                        HStack(spacing: 4) {
                            Text(ActionFormatting.shortAction(for: entry.action))
                                .font(Typ.caption)
                                .fontWeight(.medium)
                            if let path = entry.filePath {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(Typ.mono)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        TimeLabel(iso8601: entry.timestamp)
                    }
                }
            }
        }
    }

    private func coverageColor(_ state: CoverageState) -> Color {
        switch state {
        case .manifoldRouted:
            return .blue
        case .trackedWorkspace:
            return agentColor
        case .outsideCoverage:
            return .orange
        }
    }
}
