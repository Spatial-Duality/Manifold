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
                    ProgressView("Loading agent policies...")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Agent Defaults")
            } footer: {
                Text("Change a single app in its column, or use Both to apply one value to Claude and Codex. OpenAI Privacy Filter model settings live in Privacy.")
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

// MARK: - Agent defaults table

private struct AgentPolicyTable: View {
    @Environment(ManifoldStore.self) var store

    private let settingWidth: CGFloat = 170
    private let valueWidth: CGFloat = 128
    private let bothWidth: CGFloat = 112

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.s3, verticalSpacing: Spacing.s2) {
            headerRow
            Divider().gridCellColumns(4)

            groupRow("Recording")
            GridRow {
                settingCell("Recording level", help: recordingHelp)
                recordingPicker(for: .cowork)
                recordingPicker(for: .codex)
                recordingBothMenu()
            }

            if hasPrivacyPolicy {
                Divider().gridCellColumns(4)
                groupRow("Privacy Policy")
                handlingRow(
                    title: "Text content",
                    keyPath: \.textHandling,
                    accessibilitySuffix: "text"
                )
                handlingRow(
                    title: "Code and diffs",
                    keyPath: \.codeHandling,
                    accessibilitySuffix: "code"
                )
                secretRow()

                Divider().gridCellColumns(4)
                groupRow("Categories")
                ForEach(PrivacyCategory.allCases, id: \.self) { category in
                    categoryRow(category)
                }
            } else {
                Divider().gridCellColumns(4)
                GridRow {
                    settingCell("Privacy Policy")
                    Text("Privacy settings unavailable")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .gridCellColumns(3)
                }
            }
        }
        .padding(.vertical, Spacing.s1)
        .accessibilityIdentifier("settings.agents.policyTable")
    }

    private var headerRow: some View {
        GridRow {
            Text("Setting")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
                .frame(width: settingWidth, alignment: .leading)
            agentHeader(.cowork)
            agentHeader(.codex)
            Text("Both")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
                .frame(width: bothWidth, alignment: .leading)
        }
    }

    private func agentHeader(_ agent: TargetApp) -> some View {
        Label(AgentMeta.label(agent), systemImage: AgentMeta.systemImage(agent))
            .font(ManifoldType.captionMedium)
            .foregroundStyle(AgentMeta.color(agent))
            .frame(width: valueWidth, alignment: .leading)
    }

    private func groupRow(_ title: String) -> some View {
        GridRow {
            Text(title)
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(ManifoldPalette.text2)
                .textCase(.uppercase)
                .gridCellColumns(4)
        }
    }

    private func settingCell(_ title: String, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(ManifoldType.caption)
            if let help {
                Text(help)
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: settingWidth, alignment: .leading)
    }

    private var recordingHelp: String {
        if let common = commonRecordingLevel {
            return common.guidance
        }
        return "Claude and Codex currently use different recording levels."
    }

    private func recordingPicker(for agent: TargetApp) -> some View {
        Picker(AgentMeta.label(agent), selection: recordingBinding(for: agent)) {
            ForEach(AccessRecordingLevel.allCases, id: \.self) { level in
                Text(level.displayName).tag(level)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: valueWidth, alignment: .leading)
        .accessibilityIdentifier("settings.agents.recording.\(agent.rawValue)")
    }

    private func recordingBothMenu() -> some View {
        valueMenu(title: commonRecordingLevel?.displayName ?? "Mixed", width: bothWidth) {
            ForEach(AccessRecordingLevel.allCases, id: \.self) { level in
                Button(level.displayName) {
                    Task {
                        await store.governance.updateAccessRecordingLevel(level, for: .cowork)
                        await store.governance.updateAccessRecordingLevel(level, for: .codex)
                    }
                }
            }
        }
        .accessibilityIdentifier("settings.agents.recording.both")
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

    @ViewBuilder
    private func handlingRow(
        title: String,
        keyPath: WritableKeyPath<AgentPrivacyPolicy, PrivacyHandlingMode>,
        accessibilitySuffix: String
    ) -> some View {
        GridRow {
            settingCell(title)
            handlingPicker(for: .cowork, keyPath: keyPath, accessibilitySuffix: accessibilitySuffix)
            handlingPicker(for: .codex, keyPath: keyPath, accessibilitySuffix: accessibilitySuffix)
            handlingBothMenu(keyPath: keyPath, accessibilitySuffix: accessibilitySuffix)
        }
    }

    private func handlingPicker(
        for agent: TargetApp,
        keyPath: WritableKeyPath<AgentPrivacyPolicy, PrivacyHandlingMode>,
        accessibilitySuffix: String
    ) -> some View {
        Picker(AgentMeta.label(agent), selection: handlingBinding(for: agent, keyPath: keyPath)) {
            ForEach(PrivacyHandlingMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: valueWidth, alignment: .leading)
        .accessibilityIdentifier("settings.agents.privacy.\(accessibilitySuffix).\(agent.rawValue)")
    }

    private func handlingBothMenu(
        keyPath: WritableKeyPath<AgentPrivacyPolicy, PrivacyHandlingMode>,
        accessibilitySuffix: String
    ) -> some View {
        valueMenu(title: commonHandling(keyPath: keyPath)?.displayName ?? "Mixed", width: bothWidth) {
            ForEach(PrivacyHandlingMode.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    updateBothPrivacyPolicies { $0[keyPath: keyPath] = mode }
                }
            }
        }
        .accessibilityIdentifier("settings.agents.privacy.\(accessibilitySuffix).both")
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

    private func commonHandling(keyPath: WritableKeyPath<AgentPrivacyPolicy, PrivacyHandlingMode>) -> PrivacyHandlingMode? {
        let claude = store.governance.privacyPolicy(for: .cowork)?[keyPath: keyPath]
        let codex = store.governance.privacyPolicy(for: .codex)?[keyPath: keyPath]
        return claude == codex ? claude : nil
    }

    private func secretRow() -> some View {
        GridRow {
            settingCell("Secrets")
            secretPicker(for: .cowork)
            secretPicker(for: .codex)
            secretBothMenu()
        }
    }

    private func secretPicker(for agent: TargetApp) -> some View {
        Picker(AgentMeta.label(agent), selection: secretBinding(for: agent)) {
            ForEach(PrivacySecretHandling.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: valueWidth, alignment: .leading)
        .accessibilityIdentifier("settings.agents.privacy.secrets.\(agent.rawValue)")
    }

    private func secretBothMenu() -> some View {
        valueMenu(title: commonSecretHandling?.displayName ?? "Mixed", width: bothWidth) {
            ForEach(PrivacySecretHandling.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    updateBothPrivacyPolicies { $0.secretHandling = mode }
                }
            }
        }
        .accessibilityIdentifier("settings.agents.privacy.secrets.both")
    }

    private func secretBinding(for agent: TargetApp) -> Binding<PrivacySecretHandling> {
        Binding(
            get: { store.governance.privacyPolicy(for: agent)?.secretHandling ?? .warn },
            set: { newValue in
                updatePrivacyPolicy(for: agent) { $0.secretHandling = newValue }
            }
        )
    }

    private var commonSecretHandling: PrivacySecretHandling? {
        let claude = store.governance.privacyPolicy(for: .cowork)?.secretHandling
        let codex = store.governance.privacyPolicy(for: .codex)?.secretHandling
        return claude == codex ? claude : nil
    }

    private func categoryRow(_ category: PrivacyCategory) -> some View {
        GridRow {
            settingCell(category.displayName)
            categoryToggle(for: .cowork, category: category)
            categoryToggle(for: .codex, category: category)
            categoryBothMenu(category)
        }
    }

    private func categoryToggle(for agent: TargetApp, category: PrivacyCategory) -> some View {
        Toggle(AgentMeta.label(agent), isOn: categoryBinding(for: agent, category: category))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(width: valueWidth, alignment: .leading)
            .accessibilityIdentifier("settings.agents.privacy.category.\(category.rawValue).\(agent.rawValue)")
    }

    private func categoryBothMenu(_ category: PrivacyCategory) -> some View {
        valueMenu(title: categoryBothLabel(category), width: bothWidth) {
            Button("On for Both") {
                updateCategory(category, enabled: true, forBoth: true)
            }
            Button("Off for Both") {
                updateCategory(category, enabled: false, forBoth: true)
            }
        }
        .accessibilityIdentifier("settings.agents.privacy.category.\(category.rawValue).both")
    }

    private func categoryBinding(for agent: TargetApp, category: PrivacyCategory) -> Binding<Bool> {
        Binding(
            get: { store.governance.privacyPolicy(for: agent)?.enabledCategories.contains(category) ?? false },
            set: { isEnabled in
                updateCategory(category, enabled: isEnabled, for: agent)
            }
        )
    }

    private func categoryBothLabel(_ category: PrivacyCategory) -> String {
        let claude = store.governance.privacyPolicy(for: .cowork)?.enabledCategories.contains(category)
        let codex = store.governance.privacyPolicy(for: .codex)?.enabledCategories.contains(category)
        guard claude == codex, let value = claude else { return "Mixed" }
        return value ? "On" : "Off"
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

    private func valueMenu<Content: View>(
        title: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu(title) {
            content()
        }
        .menuStyle(.button)
        .controlSize(.small)
        .frame(width: width, alignment: .leading)
    }
}
