import SwiftUI
import ManifoldKit

enum FilesSidebarSelection: Hashable {
    case dashboard
    case allFiles
    case allSources
    case source(String)
    case recentlyModified
    case aiTouched
}

/// Files tab sidebar matching the prototype layout:
/// Overview (Dashboard), Browse (All Files, All Sources), Sources, Versions.
struct FilesSidebar: View {
    @Environment(ManifoldStore.self) var store
    @Binding var selection: FilesSidebarSelection?

    var body: some View {
        List(selection: $selection) {
            // Overview
            Section {
                Label("Dashboard", systemImage: "chart.bar")
                    .tag(FilesSidebarSelection.dashboard)
            } header: {
                Text("Overview")
            }
            .headerProminence(.increased)

            // Browse
            Section {
                Label {
                    HStack {
                        Text("All Files")
                        Spacer()
                        Text("\(store.sources.filter { !$0.isRemoved }.count)")
                            .font(Typ.numericCaption)
                            .foregroundStyle(.tertiary)
                    }
                } icon: {
                    Image(systemName: "doc.text")
                }
                .tag(FilesSidebarSelection.allFiles)

                Label("All Sources", systemImage: "folder")
                    .tag(FilesSidebarSelection.allSources)
            } header: {
                Text("Browse")
            }
            .headerProminence(.increased)

            // Sources
            Section {
                ForEach(visibleSources) { source in
                    Label {
                        HStack {
                            Text(source.displayName)
                            Spacer()
                            Text("\(store.sources.count)")
                                .font(Typ.numericCaption)
                                .foregroundStyle(.tertiary)
                        }
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
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Sources (\(visibleSources.count))")
            }
            .headerProminence(.increased)

            // Versions
            Section {
                Label("Recently Modified", systemImage: "clock")
                    .tag(FilesSidebarSelection.recentlyModified)
                Label("AI-Touched Files", systemImage: "eye")
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
