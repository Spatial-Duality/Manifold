// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct MailHistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "No mail sessions yet",
            systemImage: "clock.arrow.circlepath",
            description: Text("Finished mail sessions show up here with the mailboxes they touched and how many threads they read.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
