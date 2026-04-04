import SwiftUI
import ManifoldKit

/// Shown when "Add a source..." is selected in sidebar with no workspaces.
struct SourcesView: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        ContentUnavailableView {
            Label("No Sources", systemImage: "folder.badge.plus")
        } description: {
            Text("Add a folder to give AI agents access to your files.\nManifold will version every change they make.")
        } actions: {
            Button("Add Source") { store.addSourceFromPicker() }
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Sources")
    }
}
