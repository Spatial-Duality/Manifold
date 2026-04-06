import SwiftUI

struct VersionsView: View {
    @Environment(ManifoldStore.self) var store
    @State private var searchText = ""
    @State private var filteredFiles: [String] = []

    private func refilter() {
        filteredFiles = searchText.isEmpty
            ? store.allTrackedFiles
            : store.allTrackedFiles.filter { $0.localizedStandardContains(searchText) }
    }

    var body: some View {
        Group {
            if store.allTrackedFiles.isEmpty {
                ContentUnavailableView(
                    "No Versions",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("File versions appear here once agents modify files through Manifold.")
                )
            } else {
                List {
                    TextField("Search files...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .listRowSeparator(.hidden)

                    ForEach(filteredFiles, id: \.self) { filePath in
                        Button { store.inspectedFilePath = filePath } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text").foregroundStyle(.secondary)
                                Text(filePath)
                                    .font(.callout.monospaced())
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Image(systemName: "sidebar.right")
                                    .foregroundStyle(.quaternary).imageScale(.small)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("Versions")
        .navigationSubtitle(store.storageUsed > 0 ? ByteCountFormatter.string(fromByteCount: store.storageUsed, countStyle: .file) : "")
        .task { await store.loadTrackedFiles(); await store.loadStorageStats(); refilter() }
        .onChange(of: store.allTrackedFiles.count) { _, _ in Task { @MainActor in refilter() } }
        .onChange(of: searchText) { _, _ in Task { @MainActor in refilter() } }
    }
}
