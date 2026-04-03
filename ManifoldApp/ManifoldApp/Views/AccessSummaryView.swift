import SwiftUI
import ManifoldKit

struct AccessSummaryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What Claude can see")
                .font(.headline)

            Divider()

            // Files
            HStack {
                Label("\(fileSourceCount) file sources", systemImage: "folder")
                Spacer()
                Text("\(totalFileCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            // Emails
            HStack {
                if let result = appState.emailClassification {
                    Label("\(result.shared) emails shared", systemImage: "envelope")
                    Spacer()
                    if result.autoHidden > 0 {
                        Text("\(result.autoHidden) hidden")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                } else {
                    Label("No emails connected", systemImage: "envelope")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .font(.subheadline)

            // Sensitive files
            let sensitiveCount = appState.sources.filter { $0.isSensitive }.count
            if sensitiveCount > 0 {
                Label("\(sensitiveCount) sensitive files exposed", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            }

            Divider()

            // Run status
            if case .active(let agent, let runID) = appState.agentStatus {
                HStack {
                    Label("\(agent) access active", systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                    Spacer()
                    Text(String(runID.prefix(12)))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.quaternary)
                }
            } else {
                Label("No active access", systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var fileSourceCount: Int {
        appState.sources.filter { $0.type != .email }.count
    }

    private var totalFileCount: Int {
        appState.sources.filter { $0.type != .email }.reduce(0) { $0 + $1.fileCount }
    }
}

#Preview("Access Summary") {
    AccessSummaryView()
        .environmentObject(AppState())
}
