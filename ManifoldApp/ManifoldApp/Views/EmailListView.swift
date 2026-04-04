import SwiftUI
import ManifoldKit

struct EmailListView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var filter = "all"
    @State private var searchText = ""
    @State private var filteredEmails: [CachedEmail] = []

    private func refilter() {
        var emails = store.cachedEmails
        switch filter {
        case "shared": emails = emails.filter(\.isShared)
        case "hidden": emails = emails.filter { $0.isAutoHidden || $0.isUserHidden }
        default: break
        }
        if !searchText.isEmpty {
            emails = emails.filter {
                $0.sender.localizedCaseInsensitiveContains(searchText) ||
                $0.subject.localizedCaseInsensitiveContains(searchText)
            }
        }
        filteredEmails = emails
    }

    var body: some View {
        Group {
            if filteredEmails.isEmpty && store.cachedEmails.isEmpty {
                ContentUnavailableView(
                    "No Emails",
                    systemImage: "tray",
                    description: Text("Fetch emails from Email Overview first.")
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
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .searchable(text: $searchText, prompt: "Search emails")
            }
        }
        .navigationTitle("Inbox")
        .navigationSubtitle("\(filteredEmails.count) emails")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Filter", selection: $filter) {
                    Text("All (\(store.cachedEmails.count))").tag("all")
                    Text("Shared").tag("shared")
                    Text("Hidden").tag("hidden")
                }
                .pickerStyle(.segmented)
            }
        }
        .task { await store.loadCachedEmails(); refilter() }
        .onChange(of: store.cachedEmails.count) { _, _ in refilter() }
        .onChange(of: filter) { _, _ in refilter() }
        .onChange(of: searchText) { _, _ in refilter() }
    }
}

struct EmailRow: View {
    let email: CachedEmail

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(email.sender).font(.callout.weight(.medium)).lineLimit(1)
                Text(email.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(email.dateReceived.prefix(10))
                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if email.isShared {
            StatusBadge(text: "SHARED", color: .green)
        } else if email.isAutoHidden {
            StatusBadge(text: email.hiddenReason?.uppercased() ?? "HIDDEN", color: .orange)
        } else {
            StatusBadge(text: "HIDDEN", color: .gray)
        }
    }
}
