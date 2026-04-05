import SwiftUI
import ManifoldKit

struct SourcesSection: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Section {
            if store.workspaces.isEmpty {
                Text("No sources added yet. Click + in toolbar.")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(store.workspaces.filter { $0.status != "archived" && $0.status != "removed" }, id: \.workspaceID) { ws in
                    SourceRow(workspace: ws)
                }
            }
        } header: {
            HStack {
                Text("Sources")
                Spacer()
                Text("\(store.workspaces.filter { $0.status != "archived" && $0.status != "removed" }.count) folders")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
