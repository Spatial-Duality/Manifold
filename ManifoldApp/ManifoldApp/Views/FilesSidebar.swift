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
            // Sources section
            Section("Sources") {
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
                    Label("Add Folder...", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Versions section
            Section("Versions") {
                Label("Recently Modified", systemImage: "clock")
                    .tag(FilesSidebarSelection.recentlyModified)
                Label("AI-Touched Files", systemImage: "sparkles")
                    .tag(FilesSidebarSelection.aiTouched)
            }

            // Activity link
            Section {
                Button {
                    store.showActivityDrawer = true
                } label: {
                    Label("View Activity", systemImage: "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Files")
    }

    private var visibleSources: [SourceRecord] {
        store.sources.filter { !$0.isRemoved }
    }
}
