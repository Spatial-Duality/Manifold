// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct AIAppsSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var showClaudeSheet = false
    @State private var showCodexSheet = false

    var body: some View {
        Form {
            Section {
                AgentHealthCard(
                    agentName: "Claude",
                    agentColor: .blue,
                    state: store.integrationHealth.claude,
                    onSetup: { showClaudeSheet = true }
                )
            }
            if let policy = store.policy.claudePolicy {
                Section("Claude Access Recording") {
                    AccessRecordingLevelPicker(
                        agent: .cowork,
                        selection: policy.accessRecordingLevel
                    )
                }
            }
            Section {
                AgentHealthCard(
                    agentName: "Codex",
                    agentColor: .purple,
                    state: store.integrationHealth.codex,
                    onSetup: { showCodexSheet = true }
                )
            }
            if let policy = store.policy.codexPolicy {
                Section("Codex Access Recording") {
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
}

private struct AccessRecordingLevelPicker: View {
    @Environment(ManifoldStore.self) var store
    let agent: TargetApp
    let selection: AccessRecordingLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Recording Level", selection: binding) {
                ForEach(AccessRecordingLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text(currentLevel.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var binding: Binding<AccessRecordingLevel> {
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

// MARK: - Agent Health Card

private struct AgentHealthCard: View {
    let agentName: String
    let agentColor: Color
    let state: AgentConnectionState
    var onSetup: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with headline state chip
            HStack {
                Circle().fill(agentColor).frame(width: 10, height: 10)
                Text(agentName).font(Typ.sectionTitle)
                Spacer()
                // Headline chip — the state the user sees first
                Text(state.overallStatus.displayLabel)
                    .font(Typ.caption.weight(.medium))
                    .foregroundStyle(chipForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(chipBackground, in: Capsule())
            }

            // Check rows — compact, secondary to the headline
            VStack(alignment: .leading, spacing: 6) {
                switch state.id {
                case .cowork:
                    CheckRow("Claude Desktop installed", status: state.appInstalled)
                    CheckRow("Claude Desktop configured", status: state.mcpConfigured)
                    CheckRow("Claude Code configured", status: state.claudeCodeConfigured)
                    CheckRow("Connection verified", status: state.connectionVerified)
                case .codex:
                    CheckRow("Codex app installed", status: state.codexAppInstalled)
                    CheckRow("Manifold added", status: state.mcpAdded)
                }
            }
            .font(Typ.body)
            .foregroundStyle(.secondary)

            if let error = state.errorDetail {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let onSetup {
                if state.overallStatus == .notInstalled {
                    Button(setupLabel) { onSetup() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Button(setupLabel) { onSetup() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private var chipForeground: Color {
        switch state.overallStatus {
        case .connected: .green
        case .error: .orange
        case .notInstalled: .secondary
        default: .blue
        }
    }

    private var chipBackground: Color {
        chipForeground.opacity(0.12)
    }

    private var setupLabel: String {
        switch state.overallStatus {
        case .connected: "Reconnect"
        case .error: "Repair Connection"
        default: "Set Up \(agentName)"
        }
    }
}

// MARK: - Overall Status Badge

struct OverallStatusBadge: View {
    let status: AgentConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(status.displayLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: .green
        case .configured, .installed: .blue
        case .error: .orange
        default: .gray
        }
    }
}

// MARK: - Check Row

struct CheckRow: View {
    let label: String
    let status: AgentConnectionStatus

    init(_ label: String, status: AgentConnectionStatus) {
        self.label = label
        self.status = status
    }

    var body: some View {
        HStack(spacing: 8) {
            statusIcon.frame(width: 16)
            Text(label).font(Typ.body)
            Spacer()
            Text(status.displayLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .connected, .installed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .checking:
            ProgressView().controlSize(.small)
        case .notInstalled:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unknown, .configured:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}
