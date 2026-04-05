import SwiftUI
import ManifoldKit

struct EmailView: View {
    @Environment(ManifoldStore.self) var store
    @State private var filter = "all"
    @State private var searchText = ""

    private var filteredEmails: [CachedEmail] {
        var emails = store.cachedEmails
        switch filter {
        case "shared": emails = emails.filter { $0.status == "shared" }
        case "hidden": emails = emails.filter { $0.status == "hidden" || $0.status == "auto_hidden" }
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
            List {
                // Filter + search
                VStack(spacing: Spacing.standard) {
                    HStack(spacing: Spacing.section) {
                        Picker("Show", selection: $filter) {
                            Text("All Emails").tag("all")
                            Text("Shared with AI").tag("shared")
                            Text("Hidden").tag("hidden")
                        }
                        .pickerStyle(.segmented)
                    }

                    TextField("Search emails...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
                .listRowSeparator(.hidden)

                if store.mailAccessStatus != .available {
                    mailSetupPrompt
                } else if filteredEmails.isEmpty {
                    emptyState
                } else {
                    emailList
                }

                // Rules section
                if !store.emailRules.isEmpty {
                    rulesSection
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
        }
        .navigationTitle("Emails")
        .navigationSubtitle(emailSubtitle)
        .task {
            await store.checkMailAccess()
            await store.loadCachedEmails()
            await store.loadEmailRules()
        }
    }

    private var emailSubtitle: String {
        if let c = store.emailClassification {
            return "\(c.shared) shared, \(c.autoHidden) hidden"
        }
        return "Not configured"
    }

    // MARK: - Mail Setup Prompt

    @ViewBuilder
    private var mailSetupPrompt: some View {
        Section {
            VStack(spacing: Spacing.section) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Connect Apple Mail")
                    .font(.headline)
                Text("Share emails with AI agents. Manifold auto-hides sensitive ones\n(banking, 2FA, healthcare) and you control what's shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                switch store.mailAccessStatus {
                case .mailNotRunning:
                    HStack(spacing: Spacing.standard) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                        Text("Mail.app is not running").font(.callout)
                    }
                    Button("Check Again") { Task { await store.checkMailAccess() } }
                        .controlSize(.small)
                case .accessDenied:
                    HStack(spacing: Spacing.standard) {
                        Image(systemName: "xmark.circle").foregroundStyle(.red)
                        Text("Automation permission needed").font(.callout)
                    }
                    Text("System Settings → Privacy & Security → Automation → enable for Mail")
                        .font(.caption).foregroundStyle(.tertiary)
                    Button("Check Again") { Task { await store.checkMailAccess() } }
                        .controlSize(.small)
                default:
                    Button("Connect Apple Mail") { Task { await store.checkMailAccess() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.large)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            "No Emails",
            systemImage: "envelope",
            description: Text(filter == "all"
                ? "Fetch emails from a mailbox to share them with AI agents."
                : "No emails match this filter.")
        )
        .listRowSeparator(.hidden)
    }

    // MARK: - Email List

    @ViewBuilder
    private var emailList: some View {
        ForEach(filteredEmails, id: \.messageID) { email in
            EmailRow(email: email)
        }
    }

    // MARK: - Rules Section

    @ViewBuilder
    private var rulesSection: some View {
        Section {
            ForEach(store.emailRules, id: \.id) { rule in
                HStack(spacing: Spacing.standard) {
                    Image(systemName: "shield")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(rule.pattern)
                        .font(.callout.monospaced())
                    Spacer()
                    Text(rule.category ?? "hidden")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await store.removeEmailRule(id: rule.id) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } header: {
            Text("Auto-Hide Rules")
        }
    }
}

// MARK: - Email Row

struct EmailRow: View {
    @Environment(ManifoldStore.self) var store
    let email: CachedEmail

    private var isShared: Bool { email.status == "shared" }

    var body: some View {
        HStack(spacing: Spacing.section) {
            // Shared/hidden indicator
            ColorIndicator(color: isShared ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(email.sender)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(email.dateReceived)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(email.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Toggle shared/hidden
            Button {
                Task {
                    if isShared {
                        await store.hideEmail(messageID: email.messageID)
                    } else {
                        await store.overrideEmailToShared(messageID: email.messageID)
                    }
                    await store.loadCachedEmails()
                    await store.reclassifyEmails()
                }
            } label: {
                Text(isShared ? "Shared" : "Hidden")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isShared ? .green : .orange)
                    .padding(.horizontal, Spacing.standard)
                    .padding(.vertical, Spacing.tight)
                    .background(isShared ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.tight)
    }
}
