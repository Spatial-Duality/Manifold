import SwiftUI
import ManifoldKit

/// Rules Dashboard — protection summary, per-agent stats, active shields overview.
struct RulesDashboardView: View {
    @Bindable var rulesModel: EmailRulesModel
    let selectedAgent: TargetApp

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protection Dashboard")
                        .font(Typ.sectionTitle)
                    Text(summaryLine)
                        .font(Typ.body)
                        .foregroundStyle(.secondary)
                }

                agentStatCard(
                    name: selectedAgent == .codex ? "Codex" : "Claude",
                    color: selectedAgent == .codex ? .codexPurple : .claudeBlue,
                    accessible: rulesModel.domainRules.filter { $0.action == .allow }.count,
                    blocked: rulesModel.shields.filter(\.isEnabled).reduce(0) { $0 + $1.blockedCount }
                )

                // Active shields
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Shields")
                        .font(Typ.heading)

                    HStack(spacing: 8) {
                        ForEach(rulesModel.shields) { shield in
                            HStack(spacing: 4) {
                                Image(systemName: shield.isEnabled ? "shield.fill" : "shield")
                                    .font(.caption)
                                Text(shield.name)
                                    .font(Typ.caption)
                                if shield.isEnabled && shield.blockedCount > 0 {
                                    Text("\u{00B7} \(shield.blockedCount) blocked")
                                        .font(Typ.numericCaption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                (shield.isEnabled ? Color.statusActive : Color.secondary)
                                    .opacity(Opacity.badgeFill),
                                in: Capsule()
                            )
                            .foregroundStyle(shield.isEnabled ? .primary : .secondary)
                        }
                    }
                }

                // Empty state for recent activity
                if rulesModel.shields.flatMap(\.recentMatches).isEmpty {
                    ContentUnavailableView {
                        Label("No Recent Shield Activity", systemImage: "shield")
                    } description: {
                        Text("Emails blocked by shields will appear here.")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Shield Matches")
                            .font(Typ.heading)
                        ForEach(rulesModel.shields.flatMap(\.recentMatches).sorted { $0.date > $1.date }.prefix(8)) { match in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.subject)
                                        .font(Typ.body)
                                        .lineLimit(1)
                                    Text(match.from)
                                        .font(Typ.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(match.date, style: .relative)
                                    .font(Typ.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 740, alignment: .leading)
        }
        .navigationTitle("Protection Dashboard")
    }

    private var summaryLine: String {
        let activeShields = rulesModel.shields.filter(\.isEnabled).count
        let domainCount = rulesModel.domainRules.count
        let contactCount = rulesModel.contactRules.count
        let agentName = selectedAgent == .codex ? "Codex" : "Claude"
        return "\(agentName): \(activeShields) shields active \u{00B7} \(domainCount) domain rules \u{00B7} \(contactCount) contact overrides"
    }

    private func agentStatCard(name: String, color: Color, accessible: Int, blocked: Int) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 10) {
                Text(name).font(Typ.heading)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(accessible)")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(color)
                        Text("accessible")
                            .font(Typ.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(blocked)")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text("blocked")
                            .font(Typ.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}
