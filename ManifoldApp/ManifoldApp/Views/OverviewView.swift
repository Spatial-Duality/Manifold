// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Overview tab — the quickest answer to “what can each agent see right now?”
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
        .navigationTitle("Overview")
        .navigationSubtitle(statusSubtitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.screen")
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
        if !store.isRuntimeConnected { return "Starting local runtime\u{2026}" }
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
             hasAccess: claudePolicy?.allowedSourceIDs.contains(source.sourceID) == true)
        }
        let codexSourceData = activeSources.map { source in
            (name: source.displayName,
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
                    Text("Need a governed edit?")
                        .font(Typ.body)
                        .fontWeight(.medium)
                    Text("Start a tracked workspace so file changes stay reviewable before anything touches your originals.")
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
                .accessibilityIdentifier("overview.startTrackedWorkBlock")
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
            Label("Connect Claude Or Codex", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text("Choose the files and email access you want to govern, then review what each agent can see.")
        } actions: {
            Button("Open Settings\u{2026}") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
