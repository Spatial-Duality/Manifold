import SwiftUI
import ManifoldKit

/// Overview tab — two-column agent dashboard matching the interactive prototype.
/// No sidebar. Agent cards fill the viewport with real data.
struct OverviewView: View {
    @Environment(ManifoldStore.self) var store
    @State private var reviewSheetChange: ReviewAccessChange?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !store.isRuntimeConnected {
                    emptyState
                } else {
                    agentCards
                    trackChangesFooter
                }
            }
            .padding(Spacing.large)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Manifold")
        .navigationSubtitle(statusSubtitle)
        .task {
            await store.loadSummary()
            await store.policy.loadPolicies()
        }
        .sheet(item: $reviewSheetChange) { change in
            ReviewAccessSheet(pendingChange: change)
                .environment(store)
                .frame(minWidth: 560, minHeight: 500)
        }
    }

    // MARK: - Status Subtitle

    private var statusSubtitle: String {
        if !store.isRuntimeConnected { return "Connecting\u{2026}" }
        var parts: [String] = []
        if store.isClaudeConnected {
            parts.append(store.policy.claudePolicy?.isPaused == true ? "Claude paused" : "Claude active")
        }
        if store.isCodexConnected {
            parts.append(store.policy.codexPolicy?.isPaused == true ? "Codex paused" : "Codex active")
        }
        if parts.isEmpty { return "No agents connected" }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Agent Cards (side by side, prototype Fix 1.1)

    @ViewBuilder
    private var agentCards: some View {
        let claudePolicy = store.policy.claudePolicy
        let codexPolicy = store.policy.codexPolicy
        let activeSources = store.sources.filter { !$0.isRemoved }
        let totalSources = activeSources.count

        let claudeSourceData = activeSources.map { source in
            (name: source.displayName,
             count: 0, // count populated by lazy enumeration elsewhere
             hasAccess: claudePolicy?.allowedSourceIDs.contains(source.sourceID) == true)
        }
        let codexSourceData = activeSources.map { source in
            (name: source.displayName,
             count: 0,
             hasAccess: codexPolicy?.allowedSourceIDs.contains(source.sourceID) == true)
        }

        let claudeEmailGovernance = store.policy.emailGovernance(for: .cowork)
        let codexEmailGovernance = store.policy.emailGovernance(for: .codex)

        let claudeActivity = store.history.activityEntries
            .filter { $0.agent?.lowercased() == "claude" || $0.agent == TargetApp.cowork.rawValue }
        let codexActivity = store.history.activityEntries
            .filter { $0.agent?.lowercased() == "codex" || $0.agent == TargetApp.codex.rawValue }

        HStack(spacing: 16) {
            AgentPolicyCard(
                agentName: "Claude",
                agentColor: .claudeBlue,
                isConnected: store.isClaudeConnected,
                policy: claudePolicy,
                coverage: store.policy.claudeCoverage,
                totalSources: totalSources,
                recentActivity: Array(claudeActivity.prefix(3)),
                sourceNames: claudeSourceData,
                emailGovernance: claudeEmailGovernance,
                isPaused: claudePolicy?.isPaused ?? false,
                onPauseToggle: {
                    Task {
                        if claudePolicy?.isPaused == true {
                            await store.policy.resumeAgent(.cowork)
                        } else {
                            await store.policy.pauseAgent(.cowork)
                        }
                    }
                },
                onReviewAccess: {
                    reviewSheetChange = ReviewAccessChange(description: "Review Claude access", kind: .explicit)
                },
                onViewActivity: { store.showActivityDrawer = true }
            )

            AgentPolicyCard(
                agentName: "Codex",
                agentColor: .codexPurple,
                isConnected: store.isCodexConnected,
                policy: codexPolicy,
                coverage: store.policy.codexCoverage,
                totalSources: totalSources,
                recentActivity: Array(codexActivity.prefix(3)),
                sourceNames: codexSourceData,
                emailGovernance: codexEmailGovernance,
                isPaused: codexPolicy?.isPaused ?? false,
                onPauseToggle: {
                    Task {
                        if codexPolicy?.isPaused == true {
                            await store.policy.resumeAgent(.codex)
                        } else {
                            await store.policy.pauseAgent(.codex)
                        }
                    }
                },
                onReviewAccess: {
                    reviewSheetChange = ReviewAccessChange(description: "Review Codex access", kind: .explicit)
                },
                onViewActivity: { store.showActivityDrawer = true }
            )
        }
    }

    // MARK: - Track Changes Footer (prototype Fix 1.4)

    @ViewBuilder
    private var trackChangesFooter: some View {
        if store.isRuntimeConnected && store.sources.contains(where: { !$0.isRemoved }) && store.policy.activeWorkBlock == nil {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracked Work Block")
                        .font(Typ.body)
                        .fontWeight(.medium)
                    Text("Monitor and review all AI file changes in real time")
                        .font(Typ.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    reviewSheetChange = ReviewAccessChange(
                        description: "Start tracking changes",
                        kind: .startWorkBlock
                    )
                } label: {
                    Text("Start Tracked Work Block")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.3))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No AI Agents Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text("Connect Claude or Codex to start managing what AI can access on your Mac.")
        } actions: {
            Button("Open Settings\u{2026}") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
