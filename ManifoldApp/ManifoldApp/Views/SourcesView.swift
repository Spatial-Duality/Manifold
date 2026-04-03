import SwiftUI
import ManifoldKit

struct SourcesView: View {
    @EnvironmentObject var store: ManifoldStore
    @Binding var selectedWorkspace: WorkspaceRecord?

    var body: some View {
        Group {
            if store.workspaces.isEmpty {
                ContentUnavailableView(
                    "No Sources",
                    systemImage: "folder.badge.plus",
                    description: Text("Add a folder to give AI agents access to your files.")
                )
            } else {
                List {
                    ForEach(store.workspaces) { workspace in
                        Button {
                            selectedWorkspace = workspace
                        } label: {
                            SourceRow(workspace: workspace)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeSource(path: workspace.rootPath)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Sources")
        .toolbar {
            Button("Add Source", systemImage: "folder.badge.plus") {
                store.addSourceFromPicker()
            }
        }
        .task { await store.loadWorkspaces() }
    }
}

struct SourceRow: View {
    let workspace: WorkspaceRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(workspace.status == "active" ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(shortenPath(workspace.rootPath))
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    StatusBadge(
                        text: workspace.status.uppercased(),
                        color: workspace.status == "active" ? .green : .gray
                    )
                    AgentBadge(agent: workspace.agent)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 2)
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
