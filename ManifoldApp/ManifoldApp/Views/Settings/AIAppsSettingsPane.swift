// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AgentsSettingsPane — the "Agents" settings pane.
//
// Stage-11 rebuild on the shared primitive AgentCard. Every visible
// concept (identity, status, check rows, primary action) now draws
// from Components/Primitives so this pane matches the rest of the
// Ledger-window surface set.

import SwiftUI
import ManifoldKit

struct AgentsSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var showClaudeSheet = false
    @State private var showCodexSheet = false

    var body: some View {
        Form {
            // Claude — connection, then this agent's recording + privacy
            Section("Claude") {
                claudeCard
            }
            if let governance = store.governance.claudePolicy {
                Section("Recording level") {
                    AccessRecordingLevelPicker(
                        agent: .cowork,
                        selection: governance.accessRecordingLevel
                    )
                }
            }
            if store.governance.privacySettings != nil,
               let claudePrivacy = store.governance.claudePrivacyPolicy {
                Section {
                    AgentPrivacyPolicyEditor(policy: claudePrivacy)
                } header: {
                    Text("Privacy policy")
                } footer: {
                    Text("Global privacy settings live in the Privacy pane.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Codex — same shape
            Section("Codex") {
                codexCard
            }
            if let governance = store.governance.codexPolicy {
                Section("Recording level") {
                    AccessRecordingLevelPicker(
                        agent: .codex,
                        selection: governance.accessRecordingLevel
                    )
                }
            }
            if store.governance.privacySettings != nil,
               let codexPrivacy = store.governance.codexPrivacyPolicy {
                Section {
                    AgentPrivacyPolicyEditor(policy: codexPrivacy)
                } header: {
                    Text("Privacy policy")
                } footer: {
                    Text("Global privacy settings live in the Privacy pane.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await store.integrationHealth.checkAll()
            await store.governance.loadPolicies()
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
        guard let governance = store.governance.claudePolicy else { return nil }
        let folders = governance.allowedSourceIDs.count
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
        guard let governance = store.governance.codexPolicy else { return nil }
        let folders = governance.allowedSourceIDs.count
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
                Task { await store.governance.updateAccessRecordingLevel(newValue, for: agent) }
            }
        )
    }

    private var currentLevel: AccessRecordingLevel {
        store.governance.policy(for: agent)?.accessRecordingLevel ?? selection
    }
}

private struct AgentPrivacyPolicyEditor: View {
    @Environment(ManifoldStore.self) var store
    let policy: AgentPrivacyPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Picker("Text content", selection: textHandlingBinding) {
                ForEach(PrivacyHandlingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Code and diffs", selection: codeHandlingBinding) {
                ForEach(PrivacyHandlingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Secrets", selection: secretHandlingBinding) {
                ForEach(PrivacySecretHandling.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("Categories")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                ForEach(PrivacyCategory.allCases, id: \.self) { category in
                    Toggle(category.displayName, isOn: categoryBinding(category))
                }
            }
        }
    }

    private var textHandlingBinding: Binding<PrivacyHandlingMode> {
        Binding(
            get: { store.governance.privacyPolicy(for: policy.agent)?.textHandling ?? policy.textHandling },
            set: { newValue in
                update { $0.textHandling = newValue }
            }
        )
    }

    private var codeHandlingBinding: Binding<PrivacyHandlingMode> {
        Binding(
            get: { store.governance.privacyPolicy(for: policy.agent)?.codeHandling ?? policy.codeHandling },
            set: { newValue in
                update { $0.codeHandling = newValue }
            }
        )
    }

    private var secretHandlingBinding: Binding<PrivacySecretHandling> {
        Binding(
            get: { store.governance.privacyPolicy(for: policy.agent)?.secretHandling ?? policy.secretHandling },
            set: { newValue in
                update { $0.secretHandling = newValue }
            }
        )
    }

    private func categoryBinding(_ category: PrivacyCategory) -> Binding<Bool> {
        Binding(
            get: { store.governance.privacyPolicy(for: policy.agent)?.enabledCategories.contains(category) ?? policy.enabledCategories.contains(category) },
            set: { isEnabled in
                update {
                    if isEnabled {
                        $0.enabledCategories.insert(category)
                    } else {
                        $0.enabledCategories.remove(category)
                    }
                }
            }
        )
    }

    private func update(_ mutate: (inout AgentPrivacyPolicy) -> Void) {
        var updated = store.governance.privacyPolicy(for: policy.agent) ?? policy
        mutate(&updated)
        Task { await store.governance.updatePrivacyPolicy(updated) }
    }
}
