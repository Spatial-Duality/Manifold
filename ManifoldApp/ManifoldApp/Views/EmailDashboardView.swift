import SwiftUI
import ManifoldKit

/// Email permission dashboard. Shows all emails with status indicators.
/// Toolbar is provided by the parent EmailsView.
struct EmailDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var expandedEmail: String?

    var body: some View {
        Group {
            if appState.isLoadingMail {
                ProgressView("Loading emails...")
            } else if let error = appState.mailError {
                ContentUnavailableView(
                    "Connection Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if appState.cachedEmails.isEmpty {
                ContentUnavailableView(
                    "No Emails",
                    systemImage: "envelope",
                    description: Text("Connect Apple Mail using the toolbar button.")
                )
            } else {
                List {
                    // Summary
                    if let result = appState.emailClassification {
                        Section {
                            HStack {
                                Label("\(result.shared) shared", systemImage: "checkmark.circle")
                                    .foregroundStyle(.green)
                                Spacer()
                                Label("\(result.autoHidden) auto-hidden", systemImage: "eye.slash")
                                    .foregroundStyle(.yellow)
                            }
                            .font(.caption)
                        }
                    }

                    // Emails
                    Section {
                        ForEach(appState.cachedEmails) { email in
                            EmailRow(
                                email: email,
                                isExpanded: expandedEmail == email.messageID,
                                onToggle: {
                                    withAnimation {
                                        expandedEmail = expandedEmail == email.messageID ? nil : email.messageID
                                    }
                                },
                                onOverride: { Task { await appState.overrideEmailToShared(email) } },
                                onHide: { Task { await appState.hideEmail(email) } }
                            )
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Email Row

struct EmailRow: View {
    let email: CachedEmail
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOverride: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .imageScale(.small)

                VStack(alignment: .leading, spacing: 1) {
                    Text(email.sender)
                        .lineLimit(1)
                    Text(email.subject)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let reason = email.hiddenReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }

                Text(email.dateReceived)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if isExpanded {
                if let preview = email.bodyPreview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .padding(.leading, 24)
                }

                HStack(spacing: 8) {
                    if email.isAutoHidden || email.isUserHidden {
                        Button("Include anyway") { onOverride() }
                            .controlSize(.small)
                    }
                    if email.isShared {
                        Button("Hide") { onHide() }
                            .controlSize(.small)
                    }
                    Spacer()
                    Text(email.senderDomain)
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .padding(.leading, 24)
            }
        }
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

#Preview("Emails") {
    NavigationStack {
        EmailsView()
            .environmentObject(AppState())
    }
    .frame(width: 600, height: 500)
}
