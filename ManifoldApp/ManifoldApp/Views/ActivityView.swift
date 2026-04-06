import SwiftUI

struct ActivityView: View {
    @Environment(ManifoldStore.self) var store
    @State private var actionFilter = "all"
    @State private var searchText = ""
    @State private var filteredEntries: [AuditEntry] = []
    @State private var copiedSummary = false
    @State private var searchDebounceTask: Task<Void, Never>?

    private static let isoFormatter = ISO8601DateFormatter()

    private func refilter() {
        var entries = store.activityEntries
        if actionFilter != "all" { entries = entries.filter { $0.action == actionFilter } }
        if !searchText.isEmpty {
            entries = entries.filter {
                ($0.filePath ?? "").localizedStandardContains(searchText) ||
                $0.action.localizedStandardContains(searchText)
            }
        }
        filteredEntries = entries
    }

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            List {
                // Filter + search
                VStack(spacing: Spacing.standard) {
                    HStack(spacing: Spacing.section) {
                        Menu {
                            Button("All") { actionFilter = "all" }
                            Divider()
                            Button("Reads") { actionFilter = "file_read" }
                            Button("Writes") { actionFilter = "file_modified" }
                            Button("Tool Calls") { actionFilter = "tool_call" }
                            Button("Connections") { actionFilter = "mcp_connection" }
                            Button("Restores") { actionFilter = "restore" }
                        } label: {
                            HStack(spacing: Spacing.tight) {
                                Text("Filter: \(filterLabel)")
                                    .font(.callout)
                                Image(systemName: "chevron.down")
                                    .imageScale(.small)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .menuStyle(.borderlessButton)

                        TextField("Search files...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }
                }
                .listRowSeparator(.hidden)

                if store.showSessionGrouping && !store.sessions.isEmpty {
                    sessionGroupedContent
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No Activity",
                        systemImage: "waveform.path",
                        description: Text(store.mcpInstalled
                            ? "Activity will appear when agents connect."
                            : "Install the MCP server in Settings first.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    flatContent
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            // Contextual bottom bar — only when session grouping is on and a session is selected
            if store.showSessionGrouping && store.selectedSession != nil {
                sessionBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: store.showSessionGrouping)
        .navigationTitle("Activity")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle("Group by Session", isOn: $store.showSessionGrouping)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .task { refilter(); await store.loadSessions() }
        .onChange(of: store.activityEntries.count) { _, _ in Task { @MainActor in refilter(); await store.loadSessions() } }
        .onChange(of: actionFilter) { _, _ in Task { @MainActor in refilter() } }
        .onChange(of: searchText) { _, _ in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                refilter()
            }
        }
    }

    private var filterLabel: String {
        switch actionFilter {
        case "file_read": "Reads"
        case "file_modified": "Writes"
        case "tool_call": "Tool Calls"
        case "mcp_connection": "Connections"
        case "restore": "Restores"
        default: "All"
        }
    }

    private var subtitle: String {
        if store.showSessionGrouping {
            "\(store.sessions.count) sessions"
        } else {
            "\(filteredEntries.count) events"
        }
    }

    // MARK: - Session Grouped Content

    @ViewBuilder
    private var sessionGroupedContent: some View {
        ForEach(Array(store.sessions.enumerated()), id: \.element.id) { index, session in
            Section {
                if store.selectedSession?.id == session.id {
                    ForEach(store.sessionEvents) { event in
                        SessionEventRow(event: event)
                    }
                }
            } header: {
                SessionHeaderButton(session: session, isActive: isActiveSession(session), isExpanded: store.selectedSession?.id == session.id) {
                    Task { @MainActor in
                        if store.selectedSession?.id == session.id {
                            await store.selectSession(nil)
                        } else {
                            await store.selectSession(session)
                        }
                    }
                }
            }
        }
    }

    private func isActiveSession(_ session: Session) -> Bool {
        guard let endDate = Self.isoFormatter.date(from: session.endTime) else { return false }
        return Date().timeIntervalSince(endDate) < 300
    }

    // MARK: - Flat Content

    @ViewBuilder
    private var flatContent: some View {
        ForEach(filteredEntries) { entry in
            Button {
                if let path = entry.filePath {
                    store.inspectedFilePath = path
                }
            } label: {
                ActivityRow(entry: entry)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bottom Bar

    private var sessionBottomBar: some View {
        HStack {
            if let session = store.selectedSession {
                Text("\(session.readCount) reads")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(session.writeCount) writes")
                    .font(.caption).foregroundStyle(.secondary)
                if session.searchCount > 0 {
                    Text("\(session.searchCount) searches")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if let session = store.selectedSession {
                    let summary = store.sessionSummary(session: session, events: store.sessionEvents)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary, forType: .string)
                    copiedSummary = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        copiedSummary = false
                    }
                }
            } label: {
                Label(copiedSummary ? "Copied!" : "Copy Summary", systemImage: copiedSummary ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                exportSession()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.edge)
        .padding(.vertical, Spacing.standard)
        .background(.ultraThinMaterial)
    }

    private func exportSession() {
        guard let session = store.selectedSession else { return }
        let summary = store.sessionSummary(session: session, events: store.sessionEvents)
        let panel = NSSavePanel()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "session-\(session.agent)-\(dateFormatter.string(from: Date())).md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? summary.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Session Header Button

struct SessionHeaderButton: View {
    let session: Session
    let isActive: Bool
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                    .frame(width: 12)

                Circle()
                    .fill(isActive ? Color.green : agentColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(isActive ? "Active session" : "Past session")

                Text(session.agent)
                    .font(.callout).fontWeight(.medium)

                Text(formattedTime)
                    .font(.caption).foregroundStyle(.secondary)

                Text("|")
                    .font(.caption).foregroundStyle(.quaternary)

                Text("\(session.readCount) reads, \(session.writeCount) writes")
                    .font(.caption).foregroundStyle(.secondary)

                Spacer()

                Text("\(session.actionCount)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var agentColor: Color {
        session.agent.lowercased().contains("codex") ? .purple : .blue
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var formattedTime: String {
        guard let start = Self.isoFormatter.date(from: session.startTime) else { return session.startTime }
        return Self.timeFormatter.string(from: start)
    }
}

// MARK: - Session Event Row

struct SessionEventRow: View {
    @Environment(ManifoldStore.self) var store
    let event: SessionEvent
    @State private var showDiff = false
    @State private var diffLines: [DiffLine]?
    @State private var diffLoading = false
    @State private var diffUnavailable = false
    @State private var showRevertConfirm = false
    @State private var showDriftConfirm = false
    @State private var revertSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main event row
            HStack(spacing: 8) {
                Image(systemName: ActionFormatting.icon(for: event.action))
                    .foregroundStyle(ActionFormatting.color(for: event.action))
                    .imageScale(.small)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? event.action)
                        .font(.callout).lineLimit(1)
                    Text(event.action.replacingOccurrences(of: "_", with: " "))
                        .font(.caption2)
                        .foregroundStyle(ActionFormatting.color(for: event.action))
                }

                Spacer()
                TimeLabel(iso8601: event.timestamp)

                if event.isWriteEvent {
                    Button {
                        showDiff.toggle()
                        if showDiff && diffLines == nil && !diffLoading && !diffUnavailable {
                            Task { await loadDiff() }
                        }
                    } label: {
                        Image(systemName: showDiff ? "chevron.down" : "chevron.right")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(revertSuccess ? Color.green.opacity(0.1) : Color.clear)
            .animation(.easeOut(duration: 1.0), value: revertSuccess)

            // Expandable diff for write events
            if showDiff && event.isWriteEvent {
                expandedDiffSection
            }
        }
        .confirmationDialog("Revert File", isPresented: $showRevertConfirm) {
            Button("Revert to Before", role: .destructive) {
                Task { await performRevert(force: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Revert this file to the state before the agent changed it?")
        }
        .confirmationDialog("File Modified Outside Agent", isPresented: $showDriftConfirm) {
            Button("Revert Anyway", role: .destructive) {
                Task { await performRevert(force: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This file was modified outside the agent since this change. Revert anyway?")
        }
    }

    @ViewBuilder
    private var expandedDiffSection: some View {
        if diffLoading {
            HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                .padding(.vertical, Spacing.tight)
        } else if diffUnavailable {
            Text("Snapshot unavailable")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.vertical, Spacing.tight)
        } else if let lines = diffLines {
            VStack(alignment: .leading, spacing: 4) {
                DiffView(lines: lines)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if event.beforeHash != nil {
                    Button(role: .destructive) {
                        showRevertConfirm = true
                    } label: {
                        Label("Revert to Before", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .padding(.vertical, Spacing.tight)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Binary file changed")
                    .font(.caption).foregroundStyle(.secondary)

                if event.beforeHash != nil {
                    Button(role: .destructive) {
                        showRevertConfirm = true
                    } label: {
                        Label("Revert to Before", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .padding(.vertical, Spacing.tight)
        }
    }

    private func loadDiff() async {
        guard event.isWriteEvent else { return }
        diffLoading = true
        defer { diffLoading = false }

        guard let beforeHash = event.beforeHash,
              let afterHash = event.afterHash else {
            diffUnavailable = true
            return
        }

        guard let beforeData = try? await store.contentStore?.retrieve(hash: beforeHash),
              let afterData = try? await store.contentStore?.retrieve(hash: afterHash) else {
            diffUnavailable = true
            return
        }

        let engine = DiffEngine()
        diffLines = engine.diff(beforeData: beforeData, afterData: afterData)
        // nil means binary — diffLines stays nil, which triggers "Binary file changed"
    }

    private func performRevert(force: Bool) async {
        let result: RevertResult
        if force {
            result = await store.forceRevertFile(event: event)
        } else {
            result = await store.revertFile(event: event)
        }
        switch result {
        case .success:
            revertSuccess = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                revertSuccess = false
            }
        case .blobPruned:
            diffUnavailable = true
        case .contentDrift:
            showDriftConfirm = true
        case .error:
            break
        }
    }
}
