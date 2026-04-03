import SwiftUI
import ManifoldKit

/// "What can Claude see?" toolbar popover.
/// Shows file count, email count, auto-hidden count, run duration.
struct AccessSummaryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            Text("What Claude can see")
                .font(.system(size: 13, weight: .semibold))

            Divider()

            // Files
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("\(appState.sources.filter { $0.type != .email }.count) file sources")
                    .font(.system(size: 12))
                Spacer()
                let totalFiles = appState.sources.filter { $0.type != .email }.reduce(0) { $0 + $1.fileCount }
                Text("\(totalFiles) files")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Emails
            HStack {
                Image(systemName: "envelope")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                if let result = appState.emailClassification {
                    Text("\(result.shared) emails shared")
                        .font(.system(size: 12))
                    Spacer()
                    if result.autoHidden > 0 {
                        Text("\(result.autoHidden) hidden")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                    }
                } else {
                    Text("No emails connected")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

            // Sensitive files
            let sensitiveCount = appState.sources.filter { $0.isSensitive }.count
            if sensitiveCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                        .frame(width: 20)
                    Text("\(sensitiveCount) sensitive files exposed")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                    Spacer()
                }
            }

            Divider()

            // Run status
            if case .active(let agent, let runID) = appState.agentStatus {
                HStack {
                    Circle()
                        .fill(.blue)
                        .frame(width: 6, height: 6)
                    Text("\(agent) access active")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(String(runID.prefix(12)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            } else {
                HStack {
                    Circle()
                        .fill(.gray)
                        .frame(width: 6, height: 6)
                    Text("No active access")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
