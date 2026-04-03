import SwiftUI
import ManifoldKit

struct SourcesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with tab picker
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sources")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Files and emails your agents can work with")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("Files").tag(0)
                    Text("Emails").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if selectedTab == 0 {
                // Files tab
                FilesTabView()
                    .environmentObject(appState)
            } else {
                // Emails tab (Permission Dashboard)
                EmailDashboardView()
                    .environmentObject(appState)
            }
        }
    }
}

struct FilesTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(appState.sources.filter { $0.type != .email }) { source in
                    SourceRow(source: source) {
                        appState.removeSource(source)
                    }
                }

                AddSourceButton(icon: "folder.badge.plus", label: "Add files or folders") {
                    appState.addFileSources()
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Mailbox Picker

struct MailboxPickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select mailbox")
                    .font(.headline)
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }
            .padding(16)

            Divider()

            if appState.isLoadingMail {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to Mail...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            } else if appState.mailboxes.isEmpty {
                Text("No mailboxes found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(appState.mailboxes.enumerated()), id: \.offset) { _, mailbox in
                        Button {
                            Task {
                                await appState.addMailbox(mailbox)
                                isPresented = false
                            }
                        } label: {
                            HStack {
                                Image(systemName: "envelope")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mailbox.name)
                                        .font(.system(size: 13))
                                    Text("\(mailbox.account) \u{00B7} \(mailbox.messageCount) messages")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text("Last 30 days")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 400, height: 350)
    }
}

// MARK: - Source Row

struct SourceRow: View {
    let source: SourceItem
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: source.icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if source.isSensitive {
                SensitiveBadge()
            }

            StatusBadge(status: source.status)

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02))
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .onHover { isHovered = $0 }
    }

    private var fileCountText: String {
        switch source.type {
        case .file: return "1 file"
        case .directory: return "\(source.fileCount) files"
        case .email: return "\(source.fileCount) emails"
        }
    }
}

// MARK: - Badges

struct StatusBadge: View {
    let status: SourceItem.SyncStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background { Capsule().fill(backgroundColor) }
            .foregroundStyle(foregroundColor)
    }

    private var backgroundColor: Color {
        switch status {
        case .synced: return .green.opacity(0.12)
        case .syncing: return .blue.opacity(0.12)
        case .error: return .red.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .synced: return .green
        case .syncing: return .blue
        case .error: return .red
        }
    }
}

struct SensitiveBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text("Sensitive")
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background { Capsule().fill(Color.yellow.opacity(0.15)) }
        .foregroundStyle(.yellow)
    }
}

// MARK: - Add Source Button

struct AddSourceButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                    )
                    .foregroundStyle(Color.primary.opacity(isHovered ? 0.15 : 0.08))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Previews

#Preview("Sources - Files Tab") {
    SourcesView()
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
