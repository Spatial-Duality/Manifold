import SwiftUI
import ManifoldKit

// String wrapper for navigationDestination(item:)
extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct VersionsView: View {
    @EnvironmentObject var store: ManifoldStore
    @Binding var selectedFile: String?
    @State private var searchText = ""

    private var filteredFiles: [String] {
        if searchText.isEmpty { return store.allTrackedFiles }
        return store.allTrackedFiles.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if store.allTrackedFiles.isEmpty {
                ContentUnavailableView(
                    "No Versions",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("File versions will appear here once agents modify files through Manifold.")
                )
            } else {
                List {
                    ForEach(filteredFiles, id: \.self) { filePath in
                        Button {
                            selectedFile = filePath
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(filePath)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Search files")
            }
        }
        .navigationTitle("Versions")
        .toolbar {
            if store.storageUsed > 0 {
                ToolbarItem(placement: .automatic) {
                    Text(formatBytes(store.storageUsed) + " in \(store.blobCount) versions")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .task {
            await store.loadTrackedFiles()
            await store.loadStorageStats()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
