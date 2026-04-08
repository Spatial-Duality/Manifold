import SwiftUI

struct AddAccountButton: View {
    @Binding var showAddAccount: Bool

    var body: some View {
        Button {
            showAddAccount = true
        } label: {
            Label("Add Account", systemImage: "plus.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
