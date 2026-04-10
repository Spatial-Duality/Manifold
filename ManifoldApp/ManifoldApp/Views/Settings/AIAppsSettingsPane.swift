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
            Section {
                AgentHealthCard(
                    agentName: "Codex",
                    agentColor: .purple,
                    state: store.integrationHealth.codex,
                    onSetup: { showCodexSheet = true }
                )
            }
        }
        .formStyle(.grouped)
        .task { await store.integrationHealth.checkAll() }
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

// MARK: - Agent Health Card

private struct AgentHealthCard: View {
    let agentName: String
    let agentColor: Color
    let state: AgentConnectionState
    var onSetup: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(agentColor).frame(width: 8, height: 8)
                Text(agentName).font(.headline)
                Spacer()
                OverallStatusBadge(status: state.overallStatus)
            }

            switch state.id {
            case .cowork:
                CheckRow("App installed", status: state.appInstalled)
                CheckRow("MCP configured", status: state.mcpConfigured)
                CheckRow("Connection verified", status: state.connectionVerified)
            case .codex:
                CheckRow("CLI installed", status: state.cliInstalled)
                CheckRow("Manifold added", status: state.mcpAdded)
            }

            if let error = state.errorDetail {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let onSetup {
                Button(setupLabel) { onSetup() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
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
            Text(label).font(.callout)
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
