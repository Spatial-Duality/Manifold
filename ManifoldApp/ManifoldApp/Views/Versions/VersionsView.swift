import SwiftUI
import ManifoldKit

struct VersionsView: View {
    @Environment(ManifoldStore.self) var store
    @State private var searchText = ""
    @State private var filteredFiles: [String] = []

    private func refilter() {
        filteredFiles = searchText.isEmpty
            ? store.allTrackedFiles
            : store.allTrackedFiles.filter { $0.localizedCaseInsensitiveContains(searchText) }
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
                    ForEach(filteredFiles, id: \.self) { filePath in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text").foregroundStyle(.secondary)
                            Text(filePath)
                                .font(.callout.monospaced())
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Image(systemName: "sidebar.right")
                                .foregroundStyle(.quaternary).imageScale(.small)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { store.inspectedFilePath = filePath }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .searchable(text: $searchText, prompt: "Search files")
            }
        }
        .navigationTitle("Versions")
        .navigationSubtitle(store.storageUsed > 0 ? ByteCountFormatter.string(fromByteCount: store.storageUsed, countStyle: .file) : "")
        .task { await store.loadTrackedFiles(); await store.loadStorageStats(); refilter() }
        .onChange(of: store.allTrackedFiles.count) { _, _ in refilter() }
        .onChange(of: searchText) { _, _ in refilter() }
    }
}
