// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AgentsSettingsPane — the "Agents" settings pane.
//
// Connection cards stay separate from per-agent defaults. Recording level and
// privacy policy are edited in one table so Claude, Codex, or both can be
// updated without scanning duplicate sections.

import SwiftUI
import ManifoldKit

struct AgentsSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var showClaudeSheet = false
    @State private var showCodexSheet = false

    var body: some View {
        Form {
            Section("Connections") {
                claudeCard
                Divider()
                codexCard
            }

            Section {
                if store.governance.claudePolicy != nil,
                   store.governance.codexPolicy != nil {
                    AgentPolicyTable()
                } else {
                    ProgressView("Loading agent policies…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Agent Defaults")
            } footer: {
                Text("Change Claude or Codex directly, or use Apply to both for one shared default. OpenAI Privacy Filter model settings live in Privacy.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
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

// MARK: - Agent defaults forms

private struct AgentPolicyTable: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            applyToBothMenu

            agentDefaults(for: .cowork)
            agentDefaults(for: .codex)

            if !hasPrivacyPolicy {
                Text("Privacy policy defaults are unavailable until policies finish loading.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.s1)
        .accessibilityIdentifier("settings.agents.policyForms")
    }

    private var applyToBothMenu: some View {
        HStack(alignment: .center, spacing: Spacing.s2) {
            Text("Shared changes")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Section("Recording level") {
                    ForEach(AccessRecordingLevel.allCases, id: \.self) { level in
                        Button(level.displayName) {
                            Task {
                                await store.governance.updateAccessRecordingLevel(level, for: .cowork)
                                await store.governance.updateAccessRecordingLevel(level, for: .codex)
                            }
                        }
                    }
                }

                if hasPrivacyPolicy {
                    Menu("Text content") {
                        privacyHandlingButtons { policy, mode in
                            policy.textHandling = mode
                        }
                    }
                    Menu("Code and diffs") {
                        privacyHandlingButtons { policy, mode in
                            policy.codeHandling = mode
                        }
                    }
                    Menu("Secrets") {
                        ForEach(PrivacySecretHandling.allCases, id: \.self) { mode in
                            Button(mode.displayName) {
                                updateBothPrivacyPolicies { $0.secretHandling = mode }
                            }
                        }
                    }
                    Menu("Categories") {
                        Button("Turn all on") {
                            updateBothPrivacyPolicies { policy in
                                policy.enabledCategories = Set(PrivacyCategory.allCases)
                            }
                        }
                        Button("Turn all off") {
                            updateBothPrivacyPolicies { policy in
                                policy.enabledCategories.removeAll()
                            }
                        }
                        Divider()
                        ForEach(PrivacyCategory.allCases, id: \.self) { category in
                            Menu(category.displayName) {
                                Button("On") {
                                    updateCategory(category, enabled: true, forBoth: true)
                                }
                                Button("Off") {
                                    updateCategory(category, enabled: false, forBoth: true)
                                }
                            }
                        }
                    }
                }
            } label: {
                Label("Apply to both…", systemImage: "person.2")
            }
            .menuStyle(.button)
            .controlSize(.regular)
            .accessibilityIdentifier("settings.agents.applyToBoth")
        }
    }

    private func privacyHandlingButtons(
        apply: @escaping (inout AgentPrivacyPolicy, PrivacyHandlingMode) -> Void
    ) -> some View {
        ForEach(PrivacyHandlingMode.allCases, id: \.self) { mode in
            Button(mode.displayName) {
                updateBothPrivacyPolicies { policy in
                    apply(&policy, mode)
                }
            }
        }
    }

    private func agentDefaults(for agent: TargetApp) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Picker("Recording level", selection: recordingBinding(for: agent)) {
                    ForEach(AccessRecordingLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.agents.recording.\(agent.rawValue)")

                Text(recordingBinding(for: agent).wrappedValue.guidance)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if hasPrivacyPolicy {
                    Divider()
                    privacyDefaults(for: agent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(AgentMeta.label(agent), systemImage: AgentMeta.systemImage(agent))
                .font(ManifoldType.bodyMedium)
                .foregroundStyle(AgentMeta.color(agent))
        }
    }

    private func privacyDefaults(for agent: TargetApp) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Picker("Text content", selection: handlingBinding(for: agent, keyPath: \.textHandling)) {
                ForEach(PrivacyHandlingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.agents.privacy.text.\(agent.rawValue)")

            Picker("Code and diffs", selection: handlingBinding(for: agent, keyPath: \.codeHandling)) {
                ForEach(PrivacyHandlingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.agents.privacy.code.\(agent.rawValue)")

            Picker("Secrets", selection: secretBinding(for: agent)) {
                ForEach(PrivacySecretHandling.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.agents.privacy.secrets.\(agent.rawValue)")

            DisclosureGroup("Privacy categories") {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    ForEach(PrivacyCategory.allCases, id: \.self) { category in
                        Toggle(category.displayName, isOn: categoryBinding(for: agent, category: category))
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("settings.agents.privacy.category.\(category.rawValue).\(agent.rawValue)")
                    }
                }
                .padding(.top, Spacing.s1)
            }
        }
    }

    private func recordingBinding(for agent: TargetApp) -> Binding<AccessRecordingLevel> {
        Binding(
            get: { store.governance.policy(for: agent)?.accessRecordingLevel ?? .lightweight },
            set: { newValue in
                Task { await store.governance.updateAccessRecordingLevel(newValue, for: agent) }
            }
        )
    }

    private var commonRecordingLevel: AccessRecordingLevel? {
        let claude = store.governance.policy(for: .cowork)?.accessRecordingLevel
        let codex = store.governance.policy(for: .codex)?.accessRecordingLevel
        return claude == codex ? claude : nil
    }

    private func handlingBinding(
        for agent: TargetApp,
        keyPath: WritableKeyPath<AgentPrivacyPolicy, PrivacyHandlingMode>
    ) -> Binding<PrivacyHandlingMode> {
        Binding(
            get: { store.governance.privacyPolicy(for: agent)?[keyPath: keyPath] ?? .off },
            set: { newValue in
                updatePrivacyPolicy(for: agent) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func secretBinding(for agent: TargetApp) -> Binding<PrivacySecretHandling> {
        Binding(
            get: { store.governance.privacyPolicy(for: agent)?.secretHandling ?? .warn },
            set: { newValue in
                updatePrivacyPolicy(for: agent) { $0.secretHandling = newValue }
            }
        )
    }

    private func categoryBinding(for agent: TargetApp, category: PrivacyCategory) -> Binding<Bool> {
        Binding(
            get: { store.governance.privacyPolicy(for: agent)?.enabledCategories.contains(category) ?? false },
            set: { isEnabled in
                updateCategory(category, enabled: isEnabled, for: agent)
            }
        )
    }

    private func updateCategory(_ category: PrivacyCategory, enabled: Bool, for agent: TargetApp) {
        updatePrivacyPolicy(for: agent) { policy in
            if enabled {
                policy.enabledCategories.insert(category)
            } else {
                policy.enabledCategories.remove(category)
            }
        }
    }

    private func updateCategory(_ category: PrivacyCategory, enabled: Bool, forBoth: Bool) {
        guard forBoth else { return }
        updateBothPrivacyPolicies { policy in
            if enabled {
                policy.enabledCategories.insert(category)
            } else {
                policy.enabledCategories.remove(category)
            }
        }
    }

    private func updatePrivacyPolicy(for agent: TargetApp, mutate: (inout AgentPrivacyPolicy) -> Void) {
        guard var updated = store.governance.privacyPolicy(for: agent) else { return }
        mutate(&updated)
        Task { await store.governance.updatePrivacyPolicy(updated) }
    }

    private func updateBothPrivacyPolicies(mutate: (inout AgentPrivacyPolicy) -> Void) {
        guard var claude = store.governance.privacyPolicy(for: .cowork),
              var codex = store.governance.privacyPolicy(for: .codex) else { return }
        mutate(&claude)
        mutate(&codex)
        Task {
            await store.governance.updatePrivacyPolicy(claude)
            await store.governance.updatePrivacyPolicy(codex)
        }
    }

    private var hasPrivacyPolicy: Bool {
        store.governance.privacySettings != nil
            && store.governance.privacyPolicy(for: .cowork) != nil
            && store.governance.privacyPolicy(for: .codex) != nil
    }

}
