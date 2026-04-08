import SwiftUI

struct MessageListEmpty: View {
    let hasAccount: Bool

    var body: some View {
        ContentUnavailableView(
            "No Emails",
            systemImage: "envelope",
            description: Text(hasAccount
                ? "This mailbox is empty or still syncing."
                : "Select an account to view backed up emails.")
        )
    }
}
