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
    let sourceNames: [(name: String, hasAccess: Bool)]
    let emailGovernance: AgentEmailGovernanceSummary?
    let isPaused: Bool
    let onPauseToggle: () -> Void
    let onReviewAccess: () -> Void
    let onViewActivity: () -> Void

    @State private var isHovered = false

    private var agentKey: String {
        agentName.lowercased()
    }

    private var sharedSources: [(name: String, hasAccess: Bool)] {
        sourceNames.filter { $0.hasAccess }
    }

    private var hiddenSourceCount: Int {
        max(totalSources - sharedSources.count, 0)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left border accent (prototype Fix 1.2)
            RoundedRectangle(cornerRadius: 10)
                .fill(agentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 14) {
                headerRow
                accessSummarySection
                sourcesSection
                emailGovernanceSection

                Divider()

                activitySection
                actionsRow
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
        .accessibilityIdentifier("agentCard.\(agentKey)")
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
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
                }

                HStack(spacing: 6) {
                    if let coverage {
                        StatusBadge(
                            text: coverage.coverageState.displayName,
                            color: coverageColor(coverage.coverageState)
                        )
                        .accessibilityIdentifier("agentCard.\(agentKey).coverage")
                        StatusBadge(
                            text: coverage.verificationStatus.displayName,
                            color: coverage.verificationStatus == .verified ? .statusActive : .orange
                        )
                        .accessibilityIdentifier("agentCard.\(agentKey).verification")
                    }
                    if let policy {
                        StatusBadge(
                            text: policy.accessRecordingLevel.displayName,
                            color: .secondary
                        )
                    }
                }
            }
            Spacer()
            Button(isPaused ? "Resume Access" : "Pause Access", action: onPauseToggle)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("agentCard.\(agentKey).pauseToggle")
        }
    }

    // MARK: - Access Summary

    private var accessSummarySection: some View {
        HStack(spacing: 12) {
            summaryPill(
                title: "Shared Sources",
                value: totalSources == 0 ? "None" : "\(sharedSources.count) of \(totalSources)"
            )
            summaryPill(
                title: "Email Rules",
                value: emailGovernance.map { "\($0.totalRuleCount) rules" } ?? "Unavailable"
            )
            summaryPill(
                title: "Default Email",
                value: emailGovernance?.defaultPolicy.displayName ?? "Unavailable"
            )
        }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            Text(value)
                .font(Typ.body)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILES AND FOLDERS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            if sharedSources.isEmpty {
                Text("No files or folders shared yet.")
                    .font(Typ.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(sharedSources.prefix(4), id: \.name) { source in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusActive)
                        Text(source.name)
                            .font(Typ.body)
                            .lineLimit(1)
                        Spacer()
                        Text("Shared")
                            .font(Typ.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if sharedSources.count > 4 {
                    Text("+\(sharedSources.count - 4) more shared")
                        .font(Typ.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if hiddenSourceCount > 0 {
                Text("\(hiddenSourceCount) source\(hiddenSourceCount == 1 ? "" : "s") not shared with \(agentName)")
                    .font(Typ.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Email Governance

    private var emailGovernanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EMAIL POLICY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            if let emailGovernance {
                governanceRow(systemImage: "shield", text: "\(emailGovernance.enabledShieldCount) active shields")
                governanceRow(
                    systemImage: "line.3.horizontal.decrease.circle",
                    text: "\(emailGovernance.domainRuleCount) domains · \(emailGovernance.contactRuleCount) contacts · \(emailGovernance.keywordRuleCount) keywords"
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

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button("Review Access", action: onReviewAccess)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("agentCard.\(agentKey).reviewAccess")
            Button("View Activity", action: onViewActivity)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("agentCard.\(agentKey).viewActivity")
            Spacer()
        }
        .padding(.top, 2)
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
