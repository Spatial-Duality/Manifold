import SwiftUI

/// 4.2: Distinguish syncing from empty. Never hedge with "or."
struct MessageListEmpty: View {
    let hasAccount: Bool
    let isSyncing: Bool

    var body: some View {
        if isSyncing {
            VStack(spacing: Spacing.standard) {
                ProgressView()
                Text("Syncing messages\u{2026}")
                    .font(Typ.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hasAccount {
            ContentUnavailableView {
                Label("No Messages", systemImage: "envelope")
            } description: {
                Text("All caught up. Select another mailbox to browse.")
            }
        } else {
            ContentUnavailableView {
                Label("No Account Selected", systemImage: "envelope")
            } description: {
                Text("Select an account in the sidebar to view backed-up emails.")
            }
        }
    }
}
