// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Window-style menu bar extra panel. Answers five questions instantly:
/// 1. Is any AI active? 2. What can each agent see? 3. Is a work block running?
/// 4. Is an agent asking for more access? 5. How do I stop it?
struct MenuBarPanelView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 0) {
            MenuBarHeaderView()

            Divider()

            // Work block strip (only when active)
            if let block = store.policy.activeWorkBlock {
                MenuBarWorkBlockStrip(block: block)
                Divider()
            }

            // Agent cards
            if let claude = store.policy.claudePolicy {
                MenuBarAgentCard(
                    agent: .cowork,
                    policy: claude,
                    emailGovernance: store.policy.emailGovernance(for: .cowork),
                    isConnected: store.isClaudeConnected
                )
            }
            if let codex = store.policy.codexPolicy {
                MenuBarAgentCard(
                    agent: .codex,
                    policy: codex,
                    emailGovernance: store.policy.emailGovernance(for: .codex),
                    isConnected: store.isCodexConnected
                )
            }

            // Empty state
            if store.policy.claudePolicy == nil && store.policy.codexPolicy == nil {
                VStack(spacing: Spacing.standard) {
                    Text("No AI agents configured")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Open Settings to set up Claude or Codex.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(Spacing.edge)
            }

            Divider()

            MenuBarQuickActions()
        }
        .frame(width: 380)
        .task {
            await store.policy.loadPolicies()
            await store.policy.loadActiveWorkBlock()
        }
    }
}

// MARK: - Header

struct MenuBarHeaderView: View {
    @Environment(ManifoldStore.self) var store

    private var anyAgentActive: Bool {
        let claude = store.policy.claudePolicy
        let codex = store.policy.codexPolicy
        return (claude != nil && claude?.isPaused != true) ||
               (codex != nil && codex?.isPaused != true)
    }

    private var statusText: String {
        if !store.isConnected && store.policy.claudePolicy == nil {
            return "No agents connected"
        }
        var parts: [String] = []
        if let claude = store.policy.claudePolicy, !claude.isPaused { parts.append("Claude active") }
        if let codex = store.policy.codexPolicy, !codex.isPaused { parts.append("Codex active") }
        if parts.isEmpty { return "All access paused" }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Manifold")
                    .font(Typ.heading)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if anyAgentActive {
                Button("Pause All") {
                    Task { await store.policy.pauseAllAgents() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Work Block Strip

struct MenuBarWorkBlockStrip: View {
    let block: WorkBlockRecord
    @Environment(ManifoldStore.self) var store

    private static let isoFormatter = ISO8601DateFormatter()

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(block.agent == .codex ? Color.codexPurple : Color.claudeBlue)
                .frame(width: 8, height: 8)

            Text("Tracked Work Block")
                .font(Typ.caption.weight(.medium))

            Text("\u{00B7}")
                .foregroundStyle(.tertiary)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let elapsed = Self.isoFormatter.date(from: block.startedAt).map {
                    context.date.timeIntervalSince($0)
                } ?? 0
                let min = Int(elapsed) / 60
                Text("\(min)m")
                    .font(Typ.numericCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Finish") {
                NSApp.activate(ignoringOtherApps: true)
                Task { await store.policy.finishWorkBlock() }
            }
            .controlSize(.mini)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((block.agent == .codex ? Color.codexPurple : Color.claudeBlue).opacity(0.06))
    }
}

// MARK: - Agent Card

struct MenuBarAgentCard: View {
    let agent: TargetApp
    let policy: AgentAccessPolicy
    let emailGovernance: AgentEmailGovernanceSummary?
    let isConnected: Bool
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let coverage = store.policy.coverage(for: agent)
            HStack {
                Circle()
                    .fill(agent == .codex ? Color.codexPurple : Color.claudeBlue)
                    .frame(width: 8, height: 8)
                Text(agent == .codex ? "Codex" : "Claude")
                    .font(Typ.body.weight(.medium))

                if policy.isPaused {
                    Text("Paused")
                        .font(Typ.caption.weight(.medium))
                        .foregroundStyle(Color.statusPaused)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.statusPaused.opacity(Opacity.badgeFill), in: Capsule())
                } else if !isConnected {
                    Text("Offline")
                        .font(Typ.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(policy.isPaused ? "Resume" : "Pause") {
                    Task {
                        if policy.isPaused {
                            await store.policy.resumeAgent(agent)
                        } else {
                            await store.policy.pauseAgent(agent)
                        }
                    }
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)
                .tint(policy.isPaused ? .statusActive : .statusPaused)
            }

            if !policy.isPaused {
                HStack(spacing: 12) {
                    if let coverage {
                        Label(coverage.coverageState.displayName, systemImage: coverageIcon(coverage.coverageState))
                            .font(.caption)
                            .foregroundStyle(coverageColor(coverage.coverageState))
                        Text(coverage.verificationStatus.displayName)
                            .font(.caption)
                            .foregroundStyle(coverage.verificationStatus == .verified ? Color.statusActive : .orange)
                    }
                    Label("\(policy.allowedSourceIDs.count) sources", systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let emailGovernance {
                        Label("\(emailGovernance.totalRuleCount) rules", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("\(emailGovernance.enabledShieldCount) shields", systemImage: "shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(emailGovernance.emailSensitivity.displayName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(policy.accessRecordingLevel.displayName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(policy.isPaused ? 0.6 : 1.0)
    }

    private func coverageIcon(_ state: CoverageState) -> String {
        switch state {
        case .manifoldRouted:
            return "shield"
        case .trackedWorkspace:
            return "square.stack.3d.up"
        case .outsideCoverage:
            return "exclamationmark.triangle"
        }
    }

    private func coverageColor(_ state: CoverageState) -> Color {
        switch state {
        case .manifoldRouted:
            return .blue
        case .trackedWorkspace:
            return agent == .codex ? .codexPurple : .claudeBlue
        case .outsideCoverage:
            return .orange
        }
    }
}

// MARK: - Quick Actions

struct MenuBarQuickActions: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 0) {
            if store.policy.activeWorkBlock == nil && store.isConnected {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    store.reviewSheetTrigger = ReviewAccessChange(
                        description: "Start tracking changes",
                        kind: .startWorkBlock
                    )
                } label: {
                    Label("Start Tracked Work Block", systemImage: "timeline.selection")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                store.selectedTab = .overview
            } label: {
                Label("Open Manifold", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o")
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Settings\u{2026}", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 2)

            Button("Quit Manifold") {
                store.quitManifold()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .keyboardShortcut("q")
        }
    }
}
