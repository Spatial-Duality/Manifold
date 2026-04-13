// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct VersionsView: View {
    @Environment(ManifoldStore.self) var store
    @State private var searchText = ""
    @State private var filteredFiles: [String] = []
    @State private var filterTask: Task<Void, Never>?

    private func refilter() {
        filteredFiles = searchText.isEmpty
            ? store.allTrackedFiles
            : store.allTrackedFiles.filter { $0.localizedStandardContains(searchText) }
    }

    private func scheduleRefilter() {
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            refilter()
        }
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
                .listStyle(.inset)
            }
        }
        .navigationTitle("Versions")
        .navigationSubtitle(store.storageUsed > 0 ? ByteCountFormatter.string(fromByteCount: store.storageUsed, countStyle: .file) : "")
        .task { await store.loadTrackedFiles(); await store.loadStorageStats(); refilter() }
        .onChange(of: store.allTrackedFiles.count) { _, _ in Task { @MainActor in refilter() } }
        .onChange(of: searchText) { _, _ in scheduleRefilter() }
    }
}
