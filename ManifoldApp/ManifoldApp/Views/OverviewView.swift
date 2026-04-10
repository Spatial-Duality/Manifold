import SwiftUI
import ManifoldKit

/// Overview tab — full-width, no sidebar. Answers the trust question:
/// "What can this AI see right now?" Each agent gets a glanceable policy card.
struct OverviewView: View {
    @Environment(ManifoldStore.self) var store
    @State private var reviewSheetChange: ReviewAccessChange?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                if !store.isConnected {
                    emptyState
                } else {
                    agentCards
                }

                // Track Changes button (below cards)
                if store.isConnected && !store.sources.isEmpty {
                    Button {
                        reviewSheetChange = ReviewAccessChange(
                            description: "Start tracking changes",
                            kind: .startWorkBlock
                        )
                    } label: {
                        Label("Track Changes", systemImage: "timeline.selection")
                    }
                    .controlSize(.large)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.xlarge)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Overview")
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

    // MARK: - Agent Cards

    @ViewBuilder
    private var agentCards: some View {
        let claudePolicy = store.policy.claudePolicy
        let codexPolicy = store.policy.codexPolicy
        let totalSources = store.sources.filter { !$0.isRemoved }.count

        AgentPolicyCard(
            agentName: "Claude",
            agentColor: .blue,
            isConnected: store.isConnected && store.connectedAgent?.lowercased().contains("codex") != true,
            sourceCount: claudePolicy?.allowedSourceIDs.count ?? 0,
            totalSources: totalSources,
            emailAccountCount: claudePolicy?.allowedEmailDomains.count ?? 0,
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
                reviewSheetChange = ReviewAccessChange(
                    description: "Review Claude access",
                    kind: .explicit
                )
            },
            onViewActivity: {
                // TODO: open Activity drawer
            }
        )

        AgentPolicyCard(
            agentName: "Codex",
            agentColor: .purple,
            isConnected: store.connectedAgent?.lowercased().contains("codex") == true,
            sourceCount: codexPolicy?.allowedSourceIDs.count ?? 0,
            totalSources: totalSources,
            emailAccountCount: codexPolicy?.allowedEmailDomains.count ?? 0,
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
                reviewSheetChange = ReviewAccessChange(
                    description: "Review Codex access",
                    kind: .explicit
                )
            },
            onViewActivity: {}
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.section) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No AI agents connected")
                .font(.title3.weight(.medium))

            Text("Connect Claude or Codex to start managing what AI can access on your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Open Settings\u{2026}") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xlarge)
    }
}
