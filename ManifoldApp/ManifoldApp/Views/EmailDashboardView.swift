import SwiftUI
import ManifoldKit

/// Email Permission Dashboard. Tab inside Sources view.
/// Shows all emails with green/yellow/red status indicators.
/// Inline category badges + click to expand actions.
struct EmailDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var expandedEmail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.isLoadingMail {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading emails...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("This may take a moment for large mailboxes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = appState.mailError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Try again") {
                        Task { await appState.connectAppleMail() }
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.cachedEmails.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "envelope.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("Connect Apple Mail to see emails here")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Button("Connect Apple Mail") {
                        Task { await appState.connectAndFetchEmails() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Summary bar
                HStack {
                    if let result = appState.emailClassification {
                        Text("\(result.shared) shared")
                            .foregroundStyle(.green)
                        Text("\u{00B7}")
                            .foregroundStyle(.quaternary)
                        Text("\(result.autoHidden) auto-hidden")
                            .foregroundStyle(.yellow)
                        if !result.reasonBreakdown.isEmpty {
                            Text("(\(result.reasonBreakdown.map { "\($0.value) \($0.key.lowercased())" }.joined(separator: ", ")))")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("Refresh") {
                        Task { await appState.refreshEmails() }
                    }
                    .controlSize(.small)
                    .disabled(appState.isLoadingMail)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                // Email list
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(appState.cachedEmails) { email in
                            EmailRow(
                                email: email,
                                isExpanded: expandedEmail == email.messageID,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        expandedEmail = expandedEmail == email.messageID ? nil : email.messageID
                                    }
                                },
                                onOverride: {
                                    Task { await appState.overrideEmailToShared(email) }
                                },
                                onHide: {
                                    Task { await appState.hideEmail(email) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
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

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Status indicator
                Image(systemName: statusIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                    .frame(width: 14)

                // Sender + subject
                VStack(alignment: .leading, spacing: 1) {
                    Text(email.sender)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(email.subject)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Category badge (inline, always visible)
                if let reason = email.hiddenReason {
                    Text(reason)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background { Capsule().fill(statusColor.opacity(0.12)) }
                        .foregroundStyle(statusColor)
                }

                // Date
                Text(email.dateReceived)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { isHovered = $0 }

            // Expanded actions
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let preview = email.bodyPreview, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(3)
                    }

                    HStack(spacing: 12) {
                        if email.isAutoHidden || email.isUserHidden {
                            Button("Include anyway") {
                                onOverride()
                            }
                            .controlSize(.small)
                        }
                        if email.isShared {
                            Button("Hide this email") {
                                onHide()
                            }
                            .controlSize(.small)
                        }
                        Text("from \(email.senderDomain)")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            }
        }
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.03))
            }
        }
    }

    private var statusIcon: String {
        if email.isShared { return "circle.fill" }
        if email.isAutoHidden { return "circle" }
        return "xmark.circle"
    }

    private var statusColor: Color {
        if email.isShared { return .green }
        if email.isAutoHidden { return .yellow }
        return .red
    }
}
