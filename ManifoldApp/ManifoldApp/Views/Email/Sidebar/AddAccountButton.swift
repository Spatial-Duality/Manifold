import SwiftUI

/// 4.6: Icon-only "+" button with tooltip, like Mail.app sidebar footer.
struct AddAccountButton: View {
    @Binding var showAddAccount: Bool

    var body: some View {
        Button("Add Email Account", systemImage: "plus") {
            showAddAccount = true
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Add Email Account\u{2026}")
    }
}
