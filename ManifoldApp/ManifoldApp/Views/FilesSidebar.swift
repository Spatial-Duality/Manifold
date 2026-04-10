import SwiftUI
import ManifoldKit

/// Files tab sidebar: source navigation with agent-colored dots,
/// version filters, and activity link. Pure navigation — no settings.
struct FilesSidebar: View {
    @Environment(ManifoldStore.self) var store
    @Binding var selectedSource: String?

    var body: some View {
        List(selection: $selectedSource) {
            // Sources section
            Section("Sources") {
                ForEach(visibleSources) { source in
                    Label {
                        Text(source.displayName)
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(source.isAccessible ? .blue : .gray)
                    }
                    .tag(source.sourceID)
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
                NavigationLink(value: "recently-modified") {
                    Label("Recently Modified", systemImage: "clock")
                }
                NavigationLink(value: "ai-touched") {
                    Label("AI-Touched Files", systemImage: "sparkles")
                }
            }

            // Activity link
            Section {
                Button {
                    // TODO: Phase 10 — open Activity drawer
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
