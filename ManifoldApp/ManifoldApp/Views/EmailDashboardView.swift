import SwiftUI
import ManifoldKit

struct EmailDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var expandedEmail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.isLoadingMail {
                ContentUnavailableView {
                    ProgressView()
                        .controlSize(.large)
                } description: {
                    Text("Loading emails...")
                } actions: {
                    Text("This may take a moment for large mailboxes")
                        .font(.caption)
                }
                .frame(maxHeight: .infinity)
            } else if let error = appState.mailError {
                ContentUnavailableView {
                    Label("Connection Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") {
                        Task { await appState.connectAppleMail() }
                    }
                }
                .frame(maxHeight: .infinity)
            } else if appState.cachedEmails.isEmpty {
                ContentUnavailableView {
                    Label("No Emails", systemImage: "envelope.badge.plus")
                } description: {
                    Text("Connect Apple Mail to see emails here")
                } actions: {
                    Button("Connect Apple Mail") {
                        Task { await appState.connectAndFetchEmails() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Summary bar
                HStack {
                    if let result = appState.emailClassification {
                        Label("\(result.shared) shared", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                        Text("\u{00B7}").foregroundStyle(.quaternary)
                        Label("\(result.autoHidden) auto-hidden", systemImage: "eye.slash")
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                    Button("Refresh") {
                        Task { await appState.refreshEmails() }
                    }
                    .controlSize(.small)
                    .disabled(appState.isLoadingMail)
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                // Email list
                List {
                    ForEach(appState.cachedEmails) { email in
                        EmailRow(
                            email: email,
                            isExpanded: expandedEmail == email.messageID,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    expandedEmail = expandedEmail == email.messageID ? nil : email.messageID
                                }
                            },
                            onOverride: { Task { await appState.overrideEmailToShared(email) } },
                            onHide: { Task { await appState.hideEmail(email) } }
                        )
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

struct EmailRow: View {
    let email: CachedEmail
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOverride: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Status indicator
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .imageScale(.small)

                // Sender + subject
                VStack(alignment: .leading, spacing: 1) {
                    Text(email.sender)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(email.subject)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Category badge
                if let reason = email.hiddenReason {
                    Text(reason)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect()
                        .foregroundStyle(statusColor)
                }

                // Date
                Text(email.dateReceived)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.quaternary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            // Expanded actions
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let preview = email.bodyPreview, !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(3)
                    }

                    HStack(spacing: 12) {
                        if email.isAutoHidden || email.isUserHidden {
                            Button("Include anyway") { onOverride() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        if email.isShared {
                            Button("Hide this email") { onHide() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        Spacer()
                        Text(email.senderDomain)
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        if email.isShared { return "checkmark.circle.fill" }
        if email.isAutoHidden { return "eye.slash.circle" }
        return "xmark.circle"
    }

    private var statusColor: Color {
        if email.isShared { return .green }
        if email.isAutoHidden { return .yellow }
        return .red
    }
}

#Preview("Email Dashboard - Empty") {
    EmailDashboardView()
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
