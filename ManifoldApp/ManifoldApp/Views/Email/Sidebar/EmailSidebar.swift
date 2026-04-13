import SwiftUI
import ManifoldKit

/// Synology Active Backup–style sidebar for the Messages view.
/// Agent Access smart filters are the PRIMARY navigation (not IMAP folders).
enum MessagesSidebarFilter: Hashable {
    case allMail
    case inbox
    case sharedWithClaude
    case sharedWithCodex
    case notShared
    case folder(String)
}

struct EmailSidebar: View {
    @Environment(ManifoldStore.self) var store
    @Binding var sidebarFilter: MessagesSidebarFilter
    @Binding var showAddAccount: Bool

    @State private var favoritesExpanded = true
    @State private var agentAccessExpanded = true
    @State private var accountExpanded = true

    var body: some View {
        List {
            // Favorites
            DisclosureGroup(isExpanded: $favoritesExpanded) {
                sidebarRow(icon: "envelope", label: "All Mail", filter: .allMail)
                sidebarRow(icon: "tray", label: "INBOX", filter: .inbox)
            } label: {
                Text("Favorites")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
            }

            // Agent Access — THE PRIMARY NAVIGATION
            DisclosureGroup(isExpanded: $agentAccessExpanded) {
                agentFilterRow(dot: .claudeBlue, label: "Shared with Claude", filter: .sharedWithClaude)
                agentFilterRow(dot: .codexPurple, label: "Shared with Codex", filter: .sharedWithCodex)
                agentFilterRow(dot: Color.gray, label: "Not Shared", filter: .notShared)
            } label: {
                Text("Agent Access")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
            }

            // Account folders
            if let account = store.emailAccounts.accounts.first {
                DisclosureGroup(isExpanded: $accountExpanded) {
                    sidebarRow(icon: "paperplane", label: "Sent", filter: .folder("Sent"))
                    sidebarRow(icon: "doc", label: "Drafts", filter: .folder("Drafts"))
                    sidebarRow(icon: "trash", label: "Trash", filter: .folder("Trash"))
                    sidebarRow(icon: "archivebox", label: "Archive", filter: .folder("Archive"))
                } label: {
                    Text(account.username ?? account.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Messages")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Add Email Account", systemImage: "plus") {
                    showAddAccount = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Add Email Account\u{2026}")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func sidebarRow(icon: String, label: String, filter: MessagesSidebarFilter) -> some View {
        Button {
            sidebarFilter = filter
        } label: {
            Label(label, systemImage: icon)
        }
        .buttonStyle(.plain)
        .fontWeight(sidebarFilter == filter ? .medium : .regular)
    }

    private func agentFilterRow(dot: Color, label: String, filter: MessagesSidebarFilter) -> some View {
        Button {
            sidebarFilter = filter
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                Text(label)
            }
        }
        .buttonStyle(.plain)
        .fontWeight(sidebarFilter == filter ? .medium : .regular)
    }
}
