import SwiftUI

struct SourcesSection: View {
    @Environment(ManifoldStore.self) var store

    private var visibleSources: [SourceRecord] {
        store.sources.filter { !$0.isRemoved }
    }

    var body: some View {
        Section {
            if visibleSources.isEmpty {
                Text("No sources added yet. Click + in toolbar.")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(visibleSources) { source in
                    SourceCardRow(source: source)
                }
            }
        } header: {
            HStack {
                Text("Sources")
                Spacer()
                Text("\(visibleSources.count) folders")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
