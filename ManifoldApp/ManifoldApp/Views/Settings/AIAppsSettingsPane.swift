import SwiftUI
import ManifoldKit

struct AIAppsSettingsPane: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Form {
            Section {
                AgentHealthCard(
                    agentName: "Claude",
                    agentColor: .blue,
                    state: store.integrationHealth.claude
                )
            }
            Section {
                AgentHealthCard(
                    agentName: "Codex",
                    agentColor: .purple,
                    state: store.integrationHealth.codex
                )
            }
        }
        .formStyle(.grouped)
        .task { await store.integrationHealth.checkAll() }
    }
}

// MARK: - Agent Health Card

private struct AgentHealthCard: View {
    let agentName: String
    let agentColor: Color
    let state: AgentConnectionState

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
