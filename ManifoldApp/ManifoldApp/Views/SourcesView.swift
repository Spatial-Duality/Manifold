import SwiftUI
import ManifoldKit

struct SourcesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Inline content filter (not toolbar — this is navigation, not an action)
                Picker("Source type", selection: $selectedTab) {
                    Text("Files").tag(0)
                    Text("Emails").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Content
                if selectedTab == 0 {
                    FilesListView()
                } else {
                    EmailDashboardView()
                }
            }
            .navigationTitle("Sources")
            .toolbar {
                // Only actions in toolbar
                ToolbarItem(placement: .primaryAction) {
                    if selectedTab == 0 {
                        Button("Add Files", systemImage: "folder.badge.plus") {
                            appState.addFileSources()
                        }
                    } else {
                        Button("Connect Mail", systemImage: "envelope.badge.plus") {
                            Task { await appState.connectAndFetchEmails() }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Files List

struct FilesListView: View {
    @EnvironmentObject var appState: AppState

    private var fileSources: [SourceItem] {
        appState.sources.filter { $0.type != .email }
    }

    var body: some View {
        if fileSources.isEmpty {
            ContentUnavailableView(
                "No Files",
                systemImage: "folder",
                description: Text("Add files or folders for your agents to work with. Use the + button in the toolbar.")
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

#Preview("Sources") {
    SourcesView()
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
