import SwiftUI

struct SourcesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Sources")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Files and emails your agents can work with")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Source list
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(appState.sources) { source in
                        SourceRow(source: source) {
                            appState.removeSource(source)
                        }
                    }

                    AddSourceButton {
                        appState.addFileSources()
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }
}

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

struct StatusBadge: View {
    let status: SourceItem.SyncStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(backgroundColor)
            }
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
        .background {
            Capsule()
                .fill(Color.yellow.opacity(0.15))
        }
        .foregroundStyle(.yellow)
    }
}

struct AddSourceButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                Text("Add files, folders, or connect email")
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
