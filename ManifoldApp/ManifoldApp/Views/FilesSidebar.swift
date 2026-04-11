import SwiftUI
import ManifoldKit

enum FilesSidebarSelection: Hashable {
    case source(String)
    case recentlyModified
    case aiTouched
}

/// Files tab sidebar: source navigation with agent-colored dots,
/// version filters, and activity link. Pure navigation — no settings.
struct FilesSidebar: View {
    @Environment(ManifoldStore.self) var store
    @Binding var selection: FilesSidebarSelection?

    var body: some View {
        List(selection: $selection) {
            // 2.4: Section headers with prominence
            Section {
                ForEach(visibleSources) { source in
                    Label {
                        Text(source.displayName)
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(source.isAccessible ? .blue : .gray)
                    }
                    .tag(FilesSidebarSelection.source(source.sourceID))
                }

                Button {
                    store.addSourceFromPicker()
                } label: {
                    Label("Add Folder\u{2026}", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Sources (\(visibleSources.count))")
            }
            .headerProminence(.increased)

            Section {
                Label("Recently Modified", systemImage: "clock")
                    .tag(FilesSidebarSelection.recentlyModified)
                Label("AI-Touched Files", systemImage: "sparkles")
                    .tag(FilesSidebarSelection.aiTouched)
            } header: {
                Text("Versions")
            }
            .headerProminence(.increased)
        }
        .listStyle(.sidebar)
        .navigationTitle("Files")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.hasDirectoryPath else { return }
                    Task { @MainActor in
                        store.addSource(path: url.path)
                    }
                }
            }
            return true
        }
    }

    private var visibleSources: [SourceRecord] {
        store.sources.filter { !$0.isRemoved }
    }
}
