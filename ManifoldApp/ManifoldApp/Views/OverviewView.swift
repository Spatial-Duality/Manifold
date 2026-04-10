import SwiftUI
import ManifoldKit

/// Overview tab — full-width, no sidebar. Answers the trust question:
/// "What can this AI see right now?" Each agent gets a glanceable policy card.
struct OverviewView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                if !store.isConnected {
                    emptyState
                } else {
                    agentCards
                }

                // Start Tracked Work Block button (below cards)
                if store.isConnected && !store.sources.isEmpty {
                    Button {
                        // TODO: Phase 9 — open Review sheet with work block CTA
                    } label: {
                        Label("Start Tracked Work Block", systemImage: "play.rectangle.fill")
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
        }
    }

    // MARK: - Agent Cards

    @ViewBuilder
    private var agentCards: some View {
        // Claude card (always shown when any agent connected)
        AgentPolicyCard(
            agentName: "Claude",
            agentColor: .blue,
            isConnected: store.connectedAgent?.lowercased().contains("codex") == false && store.isConnected,
            sourceCount: store.sources.filter(\.isAccessible).count,
            totalSources: store.sources.filter { !$0.isRemoved }.count,
            emailAccountCount: store.emailAccounts.accounts.count,
            isPaused: false, // TODO: Phase 5 — wire to PolicyModel
            onPauseToggle: {
                // TODO: Phase 5 — toggle pause via PolicyStore
            },
            onReviewAccess: {
                // TODO: Phase 8 — open Review Access sheet
            },
            onViewActivity: {
                // TODO: Phase 10 — open Activity drawer
            }
        )

        // Codex card (if codex has been seen)
        AgentPolicyCard(
            agentName: "Codex",
            agentColor: .purple,
            isConnected: store.connectedAgent?.lowercased().contains("codex") == true,
            sourceCount: 0,
            totalSources: store.sources.filter { !$0.isRemoved }.count,
            emailAccountCount: store.emailAccounts.accounts.count,
            isPaused: false,
            onPauseToggle: {},
            onReviewAccess: {},
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

            Text("Manifold will appear here when Claude or Codex connects via MCP.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xlarge)
    }
}
