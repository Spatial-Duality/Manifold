import SwiftUI
import ManifoldKit

/// Files view. Shows file/folder sources. Full-height List, no tabs.
struct FilesView: View {
    @EnvironmentObject var appState: AppState

    private var fileSources: [SourceItem] {
        appState.sources.filter { $0.type != .email }
    }

    var body: some View {
        Group {
            if fileSources.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "folder",
                    description: Text("Add files or folders for your agents to work with.")
                )
            } else {
                List {
                    ForEach(fileSources) { source in
                        SourceRow(source: source)
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            appState.removeSource(fileSources[i])
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Files")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Files", systemImage: "folder.badge.plus") {
                    appState.addFileSources()
                }
            }
        }
    }
}

/// Emails view. Shows the email permission dashboard. Full-height List, no tabs.
struct EmailsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        EmailDashboardView()
            .navigationTitle("Emails")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Connect Mail", systemImage: "envelope.badge.plus") {
                        Task { await appState.connectAndFetchEmails() }
                    }
                    .disabled(appState.isLoadingMail)
                }
            }
    }
}

// MARK: - Source Row

struct SourceRow: View {
    let source: SourceItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(fileCountText)
                        .foregroundStyle(.secondary)

                    if source.isSensitive {
                        Label("Sensitive", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }

                    Text(source.status.rawValue)
                        .foregroundStyle(statusColor)
                }
                .font(.caption)
            }
        } icon: {
            Image(systemName: source.icon)
                .foregroundStyle(.secondary)
        }
    }

    private var fileCountText: String {
        switch source.type {
        case .file: return "1 file"
        case .directory: return "\(source.fileCount) files"
        case .email: return "\(source.fileCount) emails"
        }
    }

    private var statusColor: Color {
        switch source.status {
        case .synced: return .green
        case .syncing: return .accentColor
        case .error: return .red
        }
    }
}

#Preview("Files") {
    NavigationStack {
        FilesView()
            .environmentObject(AppState())
    }
    .frame(width: 600, height: 500)
}
