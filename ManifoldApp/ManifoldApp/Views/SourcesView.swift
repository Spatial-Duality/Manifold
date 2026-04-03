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
                        .font(.title2.weight(.semibold))
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
                FilesTabView()
                    .environmentObject(appState)
            } else {
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

                Button {
                    appState.addFileSources()
                } label: {
                    Label("Add files or folders", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Source Row

struct SourceRow: View {
    let source: SourceItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: source.icon)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileCountText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if source.isSensitive {
                Label("Sensitive", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }

            Text(source.status.rawValue)
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusColor)

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var fileCountText: String {
        switch source.type {
        case .file: return "1 file"
        case .directory: return "\(source.fileCount) files"
        case .email: return "\(source.fileCount) emails"
        }
    }

    private var statusColor: Color {
        switch source.status {
        case .synced: return .green
        case .syncing: return .blue
        case .error: return .red
        }
    }
}

#Preview("Sources - Files Tab") {
    SourcesView()
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
