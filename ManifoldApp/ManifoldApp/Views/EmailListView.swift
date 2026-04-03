import SwiftUI
import ManifoldKit

struct EmailListView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var filter = "all"
    @State private var searchText = ""

    private var filteredEmails: [CachedEmail] {
        var emails = store.cachedEmails
        switch filter {
        case "shared": emails = emails.filter { $0.isShared }
        case "hidden": emails = emails.filter { $0.isAutoHidden || $0.isUserHidden }
        default: break
        }
        if !searchText.isEmpty {
            emails = emails.filter {
                $0.sender.localizedCaseInsensitiveContains(searchText) ||
                $0.subject.localizedCaseInsensitiveContains(searchText)
            }
        }
        return emails
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Picker("", selection: $filter) {
                    Text("All (\(store.cachedEmails.count))").tag("all")
                    Text("Shared").tag("shared")
                    Text("Hidden").tag("hidden")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            if filteredEmails.isEmpty {
                ContentUnavailableView(
                    "No Emails",
                    systemImage: "envelope",
                    description: Text("Fetch emails from the Overview tab to see them here.")
                )
            } else {
                List {
                    ForEach(filteredEmails) { email in
                        EmailRow(email: email)
                            .contextMenu {
                                if email.isShared {
                                    Button("Hide from Agent") {
                                        Task { await store.hideEmail(messageID: email.messageID) }
                                    }
                                } else {
                                    Button("Share with Agent") {
                                        Task { await store.overrideEmailToShared(messageID: email.messageID) }
                                    }
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Search emails")
            }
        }
    }
}

struct EmailRow: View {
    let email: CachedEmail

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(email.sender)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(email.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(email.dateReceived.prefix(10))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            statusBadge
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if email.isShared {
            StatusBadge(text: "SHARED", color: .green)
        } else if email.isAutoHidden {
            StatusBadge(text: email.hiddenReason?.uppercased() ?? "HIDDEN", color: .yellow)
        } else {
            StatusBadge(text: "HIDDEN", color: .gray)
        }
    }
}
