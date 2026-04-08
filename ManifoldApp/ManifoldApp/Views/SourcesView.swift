import SwiftUI
import ManifoldKit

struct SourcesView: View {
    @Environment(ManifoldStore.self) var store
    @State private var selectedSourceIDs: Set<String> = []
    @State private var confirmBulkRemove = false

    private var visibleSources: [SourceRecord] {
        store.sources.filter { !$0.isRemoved }
    }

    private var selectedSources: [SourceRecord] {
        visibleSources.filter { selectedSourceIDs.contains($0.sourceID) }
    }

    private var allSelectedActive: Bool {
        !selectedSources.isEmpty && selectedSources.allSatisfy(\.isAccessible)
    }

    var body: some View {
        Group {
            if visibleSources.isEmpty {
                SourcesEmptyState()
            } else {
                SourceListContent(
                    visibleSources: visibleSources,
                    selectedSourceIDs: $selectedSourceIDs,
                    confirmBulkRemove: $confirmBulkRemove
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Sources")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Folder", systemImage: "folder.badge.plus") {
                    store.addSourceFromPicker()
                }
            }
        }
        .alert("Remove \(selectedSources.count) Source\(selectedSources.count == 1 ? "" : "s")?", isPresented: $confirmBulkRemove) {
            Button("Remove", role: .destructive) {
                for source in selectedSources {
                    store.removeSource(path: source.originalRootPath)
                }
                selectedSourceIDs.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("File history will be preserved. You can re-add these folders later.")
        }
    }

    private var subtitle: String {
        let active = visibleSources.filter(\.isAccessible).count
        let total = visibleSources.count
        if total == 0 { return "No sources" }
        if selectedSourceIDs.count > 0 {
            return "\(selectedSourceIDs.count) selected"
        }
        if active == total { return "\(total) source\(total == 1 ? "" : "s")" }
        return "\(active) active, \(total - active) paused"
    }
}

// MARK: - Source List

private struct SourceListContent: View {
    @Environment(ManifoldStore.self) var store
    let visibleSources: [SourceRecord]
    @Binding var selectedSourceIDs: Set<String>
    @Binding var confirmBulkRemove: Bool

    var body: some View {
        List(visibleSources, selection: $selectedSourceIDs) { source in
            SourceCardRow(source: source)
                .tag(source.sourceID)
                .contextMenu {
                    sourceContextMenu(for: source)
                }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count > 1 {
                bulkContextMenu(for: ids)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
    }

    // MARK: - Context Menus (Apple Mail pattern)

    @ViewBuilder
    private func sourceContextMenu(for source: SourceRecord) -> some View {
        if source.isAccessible {
            Button("Pause Access") {
                Task { await store.pauseSource(sourceID: source.sourceID) }
            }
        } else {
            Button("Resume Access") {
                Task { await store.resumeSource(sourceID: source.sourceID) }
            }
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(source.originalRootPath, inFileViewerRootedAtPath: "")
        }
        Divider()
        Button("Remove from Manifold...", role: .destructive) {
            selectedSourceIDs = [source.sourceID]
            confirmBulkRemove = true
        }
    }

    @ViewBuilder
    private func bulkContextMenu(for ids: Set<String>) -> some View {
        let sources = visibleSources.filter { ids.contains($0.sourceID) }
        let allActive = sources.allSatisfy(\.isAccessible)

        if allActive {
            Button("Pause \(sources.count) Sources") {
                Task {
                    for s in sources { await store.pauseSource(sourceID: s.sourceID) }
                }
            }
        } else {
            Button("Activate \(sources.count) Sources") {
                Task {
                    for s in sources { await store.resumeSource(sourceID: s.sourceID) }
                }
            }
        }
        Divider()
        Button("Remove \(sources.count) Sources...", role: .destructive) {
            selectedSourceIDs = ids
            confirmBulkRemove = true
        }
    }
}

// MARK: - Empty State

private struct SourcesEmptyState: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        ContentUnavailableView {
            Label("No Sources", systemImage: "folder.badge.plus")
        } description: {
            Text("Add a folder to let AI agents access your files.\nEverything they touch gets automatic version history.")
        } actions: {
            Button("Add Folder") {
                store.addSourceFromPicker()
            }
            .glassProminentButton()
        }
    }
}
