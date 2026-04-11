import SwiftUI
import ManifoldKit

struct SharedEmailsRow: View {
    @Environment(ManifoldStore.self) var store
    @Bindable var selection: EmailSelectionModel
    @State private var sharedCount: Int = 0

    var body: some View {
        if sharedCount > 0 {
            Section {
                Button {
                    selection.showSharedEmails()
                } label: {
                    Label {
                        HStack {
                            Text("Shared with Claude")
                            Spacer()
                            Text("\(sharedCount)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.purple, in: Capsule())
                        }
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.purple)
                    }
                }
                .buttonStyle(.plain)
                .fontWeight(selection.showingSharedEmails ? .semibold : .regular)
            }
            .task {
                sharedCount = await store.emailAccounts.sharedEmailCount()
            }
        }
    }
}
