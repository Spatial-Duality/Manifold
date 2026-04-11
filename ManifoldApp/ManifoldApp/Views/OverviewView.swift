import SwiftUI
import ManifoldKit

/// Overview tab — full-width dashboard. Answers the trust question:
/// "What can this AI see right now?" Each agent gets a rich dashboard card
/// showing sources, domains, recent activity, and per-agent controls.
struct OverviewView: View {
    @Environment(ManifoldStore.self) var store
    @State private var reviewSheetChange: ReviewAccessChange?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                if !store.isRuntimeConnected {
                    emptyState
                } else {
                    agentCards

                    // Track Changes footer (spans both cards)
                    trackChangesFooter
                }
            }
            .padding(Spacing.xlarge)
            .frame(maxWidth: 640)
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

    // MARK: - Status Subtitle (1.3)

    private var statusSubtitle: String {
        if !store.isRuntimeConnected {
            return "Connecting\u{2026}"
        }
        var parts: [String] = []
        if store.isClaudeConnected {
            parts.append(store.policy.claudePolicy?.isPaused == true ? "Claude paused" : "Claude active")
        }
        if store.isCodexConnected {
            parts.append(store.policy.codexPolicy?.isPaused == true ? "Codex paused" : "Codex active")
        }
        if parts.isEmpty {
            return "No agents connected"
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Agent Cards (1.1, 1.2)

    @ViewBuilder
    private var agentCards: some View {
        let claudePolicy = store.policy.claudePolicy
        let codexPolicy = store.policy.codexPolicy
        let activeSources = store.sources.filter { !$0.isRemoved }
        let totalSources = activeSources.count

        let claudeSourceNames = activeSources
            .filter { claudePolicy?.allowedSourceIDs.contains($0.sourceID) == true }
            .map(\.displayName)
        let codexSourceNames = activeSources
            .filter { codexPolicy?.allowedSourceIDs.contains($0.sourceID) == true }
            .map(\.displayName)

        let claudeActivity = store.history.activityEntries
            .filter { $0.agent?.lowercased() == "claude" || $0.agent == TargetApp.cowork.rawValue }
        let codexActivity = store.history.activityEntries
            .filter { $0.agent?.lowercased() == "codex" || $0.agent == TargetApp.codex.rawValue }

        AgentPolicyCard(
            agentName: "Claude",
            agentColor: .claudeBlue,
            isConnected: store.isClaudeConnected,
            policy: claudePolicy,
            totalSources: totalSources,
            recentActivity: Array(claudeActivity.prefix(3)),
            sourceNames: claudeSourceNames,
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
            totalSources: totalSources,
            recentActivity: Array(codexActivity.prefix(3)),
            sourceNames: codexSourceNames,
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

    // MARK: - Track Changes Footer (1.4)

    @ViewBuilder
    private var trackChangesFooter: some View {
        if store.isRuntimeConnected && store.sources.contains(where: { !$0.isRemoved }) && store.policy.activeWorkBlock == nil {
            HStack {
                Spacer()
                Button {
                    reviewSheetChange = ReviewAccessChange(
                        description: "Start tracking changes",
                        kind: .startWorkBlock
                    )
                } label: {
                    Label("Start Tracked Work Block", systemImage: "timeline.selection")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                Spacer()
            }
            .padding(.top, Spacing.standard)
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
