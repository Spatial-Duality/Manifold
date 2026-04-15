// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AIAppsSettingsPane — the "Agents" settings pane.
//
// Stage-11 rebuild on the shared primitive AgentCard. Every visible
// concept (identity, status, check rows, primary action) now draws
// from Components/Primitives so this pane matches the rest of the
// Ledger-window surface set.

import SwiftUI
import ManifoldKit

struct AIAppsSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var showClaudeSheet = false
    @State private var showCodexSheet = false

    var body: some View {
        Form {
            Section {
                claudeCard
            } header: {
                Text("Claude").font(ManifoldType.title)
            }

            if let policy = store.policy.claudePolicy {
                Section("Recording level · Claude") {
                    AccessRecordingLevelPicker(
                        agent: .cowork,
                        selection: policy.accessRecordingLevel
                    )
                }
            }

            Section {
                codexCard
            } header: {
                Text("Codex").font(ManifoldType.title)
            }

            if let policy = store.policy.codexPolicy {
                Section("Recording level · Codex") {
                    AccessRecordingLevelPicker(
                        agent: .codex,
                        selection: policy.accessRecordingLevel
                    )
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await store.integrationHealth.checkAll()
            await store.policy.loadPolicies()
        }
        .sheet(isPresented: $showClaudeSheet) {
            ConnectClaudeSheet()
                .environment(store)
        }
        .sheet(isPresented: $showCodexSheet) {
            ConnectCodexSheet()
                .environment(store)
        }
    }

    // MARK: - Claude card

    private var claudeCard: some View {
        let state = store.integrationHealth.claude
        return AgentCard(
            agent: .cowork,
            displayName: "Claude",
            consequenceText: claudeConsequence(),
            status: mapStatus(state.overallStatus),
            errorDetail: state.errorDetail,
            primaryAction: AgentCardAction(
                label: claudeActionLabel(for: state.overallStatus),
                handler: { showClaudeSheet = true }
            )
        ) {
            LiveCheckRow(label: "Claude Desktop installed",
                         status: state.appInstalled,
                         onRefresh: { await store.integrationHealth.checkClaude() })
            LiveCheckRow(label: "Claude Desktop configured",
                         status: state.mcpConfigured,
                         onRefresh: { await store.integrationHealth.checkClaude() })
            LiveCheckRow(label: "Claude Code configured",
                         status: state.claudeCodeConfigured,
                         onRefresh: { await store.integrationHealth.checkClaude() })
            LiveCheckRow(label: "Connection verified",
                         status: state.connectionVerified,
                         onRefresh: { await store.integrationHealth.checkClaude() })
        }
    }

    private func claudeConsequence() -> String? {
        guard let policy = store.policy.claudePolicy else { return nil }
        let folders = policy.allowedSourceIDs.count
        return "\(folders) folder\(folders == 1 ? "" : "s") in default scope"
    }

    private func claudeActionLabel(for status: AgentConnectionStatus) -> String {
        switch status {
        case .connected:    return "Reconnect"
        case .error:        return "Repair"
        default:            return "Set up Claude"
        }
    }

    // MARK: - Codex card

    private var codexCard: some View {
        let state = store.integrationHealth.codex
        return AgentCard(
            agent: .codex,
            displayName: "Codex",
            consequenceText: codexConsequence(),
            status: mapStatus(state.overallStatus),
            errorDetail: state.errorDetail,
            primaryAction: AgentCardAction(
                label: codexActionLabel(for: state.overallStatus),
                handler: { showCodexSheet = true }
            )
        ) {
            LiveCheckRow(label: "Codex app installed",
                         status: state.codexAppInstalled,
                         onRefresh: { await store.integrationHealth.checkCodex() })
            LiveCheckRow(label: "Manifold added",
                         status: state.mcpAdded,
                         onRefresh: { await store.integrationHealth.checkCodex() })
        }
    }

    private func codexConsequence() -> String? {
        guard let policy = store.policy.codexPolicy else { return nil }
        let folders = policy.allowedSourceIDs.count
        return "\(folders) folder\(folders == 1 ? "" : "s") in default scope"
    }

    private func codexActionLabel(for status: AgentConnectionStatus) -> String {
        switch status {
        case .connected:    return "Reconnect"
        case .error:        return "Repair"
        default:            return "Set up Codex"
        }
    }

    // MARK: - Status mapping

    private func mapStatus(_ status: AgentConnectionStatus) -> AgentCardStatus {
        switch status {
        case .connected:                  return .ok
        case .configured, .installed:     return .ok
        case .error:                      return .error
        case .notInstalled:               return .needsSetup
        case .checking, .unknown:         return .offline
        }
    }
}

// MARK: - Access recording level

private struct AccessRecordingLevelPicker: View {
    @Environment(ManifoldStore.self) var store
    let agent: TargetApp
    let selection: AccessRecordingLevel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Picker("Recording Level", selection: recordingLevelBinding) {
                ForEach(AccessRecordingLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(currentLevel.guidance)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Stable binding avoiding inline Binding(get:set:) in view body.
    private var recordingLevelBinding: Binding<AccessRecordingLevel> {
        Binding(
            get: { currentLevel },
            set: { newValue in
                Task { await store.policy.updateAccessRecordingLevel(newValue, for: agent) }
            }
        )
    }

    private var currentLevel: AccessRecordingLevel {
        store.policy.policy(for: agent)?.accessRecordingLevel ?? selection
    }
}
