import SwiftUI
import ManifoldKit

private enum HistoryMode: String, CaseIterable {
    case sessions = "Sessions"
    case timeline = "Timeline"
    case files = "Files"
}

struct HistoryView: View {
    @Environment(ManifoldStore.self) var store
    @State private var selectedSession: Session?
    @State private var searchText = ""
    @State private var mode: HistoryMode = .sessions
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HistoryToolbar(mode: $mode, searchText: $searchText)
            Divider()

            Group {
                switch mode {
                case .sessions:
                    SessionListContent(
                        isLoading: isLoading,
                        filteredSessions: filteredSessions,
                        selectedSession: $selectedSession
                    )
                case .timeline:
                    ActivityView()
                case .files:
                    VersionsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("History")
        .navigationSubtitle(subtitle)
        .task {
            await store.loadSessions()
            isLoading = false
        }
    }

    private var subtitle: String {
        "\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s")"
    }

    private var filteredSessions: [Session] {
        guard !searchText.isEmpty else { return store.sessions }
        return store.sessions.filter {
            $0.agent.localizedStandardContains(searchText) ||
            $0.id.localizedStandardContains(searchText)
        }
    }
}

// MARK: - Toolbar

private struct HistoryToolbar: View {
    @Binding var mode: HistoryMode
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: Spacing.section) {
            Picker("View", selection: $mode) {
                ForEach(HistoryMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Spacer()

            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, Spacing.edge)
        .padding(.vertical, Spacing.standard)
    }
}

// MARK: - Session List Content

private struct SessionListContent: View {
    @Environment(ManifoldStore.self) var store
    let isLoading: Bool
    let filteredSessions: [Session]
    @Binding var selectedSession: Session?

    var body: some View {
        Group {
            if isLoading && store.sessions.isEmpty {
                ProgressView("Loading sessions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSessions.isEmpty {
                ContentUnavailableView("No Sessions", systemImage: "rectangle.stack",
                    description: Text("Sessions appear here after an AI agent connects and works."))
            } else {
                List(filteredSessions, selection: $selectedSession) { session in
                    SessionHistoryRow(session: session, isSelected: selectedSession == session)
                        .tag(session)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onChange(of: selectedSession) { _, newValue in
                    if let session = newValue {
                        Task { await store.loadSessionEvents(sessionID: session.id) }
                    }
                }
            }
        }
    }
}

// MARK: - Session Row (expandable detail inline)

private struct SessionHistoryRow: View {
    @Environment(ManifoldStore.self) var store
    let session: Session
    let isSelected: Bool

    private static let isoFormatter = ISO8601DateFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            // Header
            HStack {
                Image(systemName: "person.circle")
                    .foregroundStyle(Color(nsColor: .systemBlue))
                Text(session.agent)
                    .font(.body.weight(.medium))
                Spacer()
                if let date = Self.isoFormatter.date(from: session.startTime) {
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Stats
            HStack(spacing: Spacing.section) {
                StatChip(icon: "eye", value: session.readCount, label: "reads")
                StatChip(icon: "pencil", value: session.writeCount, label: "writes")
                StatChip(icon: "magnifyingglass", value: session.searchCount, label: "searches")
                Spacer()
                Text(session.id.prefix(8))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.quaternary)
            }

            // Expanded events when selected
            if isSelected && !store.sessionEvents.isEmpty {
                Divider()
                    .padding(.vertical, Spacing.tight)

                ForEach(store.sessionEvents.prefix(20)) { event in
                    HStack(spacing: Spacing.standard) {
                        Image(systemName: ActionFormatting.icon(for: event.action))
                            .foregroundStyle(ActionFormatting.color(for: event.action))
                            .imageScale(.small)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.action.replacingOccurrences(of: "_", with: " "))
                                .font(.callout)
                            if let path = event.filePath {
                                Text(path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                        TimeLabel(iso8601: event.timestamp)
                    }
                    .padding(.vertical, 1)
                }

                if store.sessionEvents.count > 20 {
                    Text("\(store.sessionEvents.count - 20) more events...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, Spacing.tight)
    }
}

private struct StatChip: View {
    let icon: String
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
