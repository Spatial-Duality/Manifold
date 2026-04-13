import SwiftUI
import ManifoldKit

struct FilesView: View {
    @Environment(ManifoldStore.self) var store
    let sidebarSelection: FilesSidebarSelection?

    @State private var allFiles: [SourceFile] = []
    @State private var filteredFiles: [SourceFile] = []
    @State private var searchText = ""
    @State private var contentSearchText = ""
    @State private var contentSearchResults: [SearchResult] = []
    @State private var isSearchingContent = false
    @State private var filterTask: Task<Void, Never>?
    @State private var reloadTask: Task<Void, Never>?
    @State private var contentSearchTask: Task<Void, Never>?
    @State private var filterSource = "All"
    @State private var cachedSourceNames: [String] = ["All"]

    private var selectedSourceID: String? {
        guard case let .source(sourceID)? = sidebarSelection else { return nil }
        return sourceID
    }

    private var selectedSourceName: String? {
        guard let selectedSourceID else { return nil }
        return store.sources.first(where: { $0.sourceID == selectedSourceID })?.displayName
    }

    private var isRecentlyModifiedSelection: Bool {
        if case .recentlyModified? = sidebarSelection { return true }
        return false
    }

    private var isAITouchedSelection: Bool {
        if case .aiTouched? = sidebarSelection { return true }
        return false
    }

    private var isAllFilesSelection: Bool {
        if case .allFiles? = sidebarSelection { return true }
        return false
    }

    private var navigationTitleText: String {
        if let selectedSourceName { return selectedSourceName }
        if isRecentlyModifiedSelection { return "Recently Modified" }
        if isAITouchedSelection { return "AI-Touched Files" }
        if isAllFilesSelection { return "All Files" }
        return "Files"
    }

    private var navigationSubtitleText: String {
        let sourceCount = selectedSourceID == nil ? store.sources.filter { !$0.isRemoved }.count : 1
        return "\(filteredFiles.count) of \(allFiles.count) files across \(sourceCount) source\(sourceCount == 1 ? "" : "s")"
    }

    @State private var selectedFileIDs: Set<SourceFile.ID> = []
    @State private var tableSortOrder: [KeyPathComparator<SourceFile>] = [
        .init(\.name, order: .forward)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Content search results
            if !contentSearchResults.isEmpty {
                ContentSearchResultsSection(
                    results: contentSearchResults,
                    onDismiss: { contentSearchResults = [] }
                )
            }

            // File table
            if filteredFiles.isEmpty {
                ContentUnavailableView {
                    Label(emptyStateTitle, systemImage: emptyStateIcon)
                } description: {
                    Text(emptyStateDescription)
                }
            } else {
                Table(filteredFiles, selection: $selectedFileIDs, sortOrder: $tableSortOrder) {
                    TableColumn("Name", value: \.name) { file in
                        HStack(spacing: 6) {
                            Image(systemName: iconFor(file.fileExtension))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(file.name)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 140, ideal: 220)

                    TableColumn("Path") { file in
                        Text(file.relativePath)
                            .font(Typ.mono)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Source") { file in
                        Text(file.sourceName)
                            .font(.caption)
                    }
                    .width(min: 60, ideal: 100)

                    TableColumn("Size", value: \.sizeBytes) { file in
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(60)

                    TableColumn("Modified", value: \.modifiedDate) { file in
                        Text(file.modifiedDate, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 70, ideal: 90)

                    TableColumn("Type") { file in
                        Text(file.fileExtension.isEmpty ? "" : ".\(file.fileExtension)")
                            .font(Typ.mono)
                            .foregroundStyle(.tertiary)
                    }
                    .width(50)
                }
                .tableStyle(.inset)
                .contextMenu(forSelectionType: SourceFile.ID.self) { ids in
                    if let id = ids.first, let file = filteredFiles.first(where: { $0.id == id }) {
                        fileContextMenu(file: file)
                    }
                }
                .onChange(of: tableSortOrder) { _, newOrder in
                    filteredFiles.sort(using: newOrder)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: Spacing.section) {
                Picker("Source", selection: $filterSource) {
                    ForEach(cachedSourceNames, id: \.self) { Text($0) }
                }
                .frame(maxWidth: 160)
                .disabled(selectedSourceID != nil)

                TextField("Filter by name\u{2026}", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(minWidth: 100, maxWidth: 200)

                // Content search
                TextField("Search inside files\u{2026}", text: $contentSearchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(minWidth: 100, maxWidth: 200)
                    .onSubmit { searchContent() }

                if isSearchingContent {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Text("\(filteredFiles.count) files")
                    .font(Typ.numericCaption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.section)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .navigationTitle(navigationTitleText)
        .navigationSubtitle(navigationSubtitleText)
        .task(id: sidebarSelection) {
            syncSidebarSelection()
            reloadFiles()
        }
        .onChange(of: store.sources.count) { _, _ in scheduleReload() }
        .onChange(of: store.hasActiveSession) { _, _ in scheduleReload() }
        .onChange(of: store.activeGrantSources.count) { _, _ in scheduleReload() }
        .onChange(of: searchText) { _, _ in scheduleFilter() }
        .onChange(of: filterSource) { _, _ in scheduleFilter() }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func fileContextMenu(file: SourceFile) -> some View {
        Button("Open") {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.path, forType: .string)
        }
        if let inspected = store.inspectedFilePath, inspected == file.relativePath {
            Button("Close Version History") { store.inspectedFilePath = nil }
        } else {
            Button("Version History") { store.inspectedFilePath = file.relativePath }
        }
    }

    // MARK: - Data

    /// Debounced reload — cancels any pending reload and waits 50ms to coalesce
    /// rapid onChange triggers (e.g. session start fires sources + grants + session changes).
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            reloadFiles()
        }
    }

    /// Debounced filter — 100ms delay to coalesce rapid changes (typing, rapid clicks).
    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await applyFilters()
        }
    }

    private func reloadFiles() {
        reloadTask?.cancel()
        reloadTask = Task {
            let files: [SourceFile]
            if store.hasActiveSession {
                files = await store.enumerateAllFiles()
            } else {
                files = await store.enumerateSourceFiles()
            }
            guard !Task.isCancelled else { return }
            allFiles = files
            rebuildPickerCaches()
            await applyFilters()
        }
    }

    private func rebuildPickerCaches() {
        cachedSourceNames = ["All"] + Array(Set(allFiles.map(\.sourceName))).sorted()
    }

    private var emptyStateTitle: String {
        if !store.isRuntimeConnected { return "Runtime Disconnected" }
        if allFiles.isEmpty && store.sources.isEmpty { return "No Sources" }
        if allFiles.isEmpty { return "No Files" }
        return "No Matches"
    }

    private var emptyStateDescription: String {
        if !store.isRuntimeConnected {
            return "Manifold can’t reach its runtime, so the Files view can’t load tracked sources yet."
        }
        if allFiles.isEmpty && store.sources.isEmpty {
            return "Add a source folder from the Files sidebar to browse files."
        }
        if allFiles.isEmpty {
            return "Your current sources do not contain any indexed files yet."
        }
        return "No files match your filters."
    }

    private var emptyStateIcon: String {
        if !store.isRuntimeConnected { return "bolt.horizontal.circle" }
        if allFiles.isEmpty && store.sources.isEmpty { return "folder.badge.plus" }
        return "doc"
    }

    /// Runs filtering off the main thread, then assigns results back.
    /// Sorting is handled by the Table via tableSortOrder.
    private func applyFilters() async {
        let snapshot = allFiles
        let source = selectedSourceID
        let sourceName = filterSource
        let aiTouched = isAITouchedSelection
        let query = searchText
        let sortOrder = tableSortOrder

        let result = await Task.detached(priority: .userInitiated) {
            var items = snapshot

            if let source {
                items = items.filter { $0.sourceID == source }
            } else if sourceName != "All" {
                items = items.filter { $0.sourceName == sourceName }
            }
            if aiTouched {
                items = items.filter(\.hasAIActivity)
            }
            if !query.isEmpty {
                items = items.filter { $0.name.localizedStandardContains(query) || $0.relativePath.localizedStandardContains(query) }
            }

            items.sort(using: sortOrder)
            return items
        }.value

        guard !Task.isCancelled else { return }
        filteredFiles = result
    }

    private func syncSidebarSelection() {
        if let selectedSourceName {
            filterSource = selectedSourceName
        } else {
            filterSource = "All"
        }

        if isRecentlyModifiedSelection {
            tableSortOrder = [.init(\.modifiedDate, order: .reverse)]
        }
    }

    private func searchContent() {
        guard !contentSearchText.isEmpty else { return }
        guard store.hasActiveSession else {
            contentSearchResults = []
            return
        }
        contentSearchTask?.cancel()
        isSearchingContent = true
        let query = contentSearchText
        contentSearchTask = Task {
            let results = await store.searchFileContents(query: query)
            guard !Task.isCancelled else { return }
            contentSearchResults = results
            isSearchingContent = false
        }
    }

    private func iconFor(_ ext: String) -> String {
        switch ext {
        case "swift": "swift"
        case "py": "doc.text"
        case "js", "ts", "jsx", "tsx": "curlybraces"
        case "rb", "go", "rs", "c", "cpp", "h", "m", "mm": "chevron.left.forwardslash.chevron.right"
        case "html", "css": "globe"
        case "xml", "json", "yaml", "yml", "toml", "plist": "curlybraces.square"
        case "md", "txt", "rtf": "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico": "photo"
        case "pdf": "doc.richtext"
        case "zip", "tar", "gz", "bz2", "7z": "doc.zipper"
        case "mp4", "mov", "avi", "mkv": "film"
        case "mp3", "wav", "aac", "flac": "music.note"
        case "ttf", "otf", "woff", "woff2": "textformat"
        case "sh", "zsh", "bash": "terminal"
        case "sql", "db", "sqlite": "cylinder"
        case "xcodeproj", "xcworkspace": "hammer"
        case "log": "text.alignleft"
        default: "doc"
        }
    }
}

// MARK: - Content Search Results Section

private struct ContentSearchResultsSection: View {
    let results: [SearchResult]
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Content matches: \(results.count) files")
                    .font(.caption.weight(.medium))
                Spacer()
                Button("Dismiss") { onDismiss() }
                    .controlSize(.mini)
            }
            .padding(.horizontal, Spacing.edge).padding(.vertical, Spacing.standard)
            .background(Color.accentColor.opacity(0.08))

            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(results) { result in
                        ContentSearchResultCard(result: result)
                    }
                }
                .padding(.horizontal, Spacing.edge).padding(.vertical, Spacing.standard)
            }
            .scrollIndicators(.hidden)
            .frame(height: 120)

            Divider()
        }
    }
}

// MARK: - Content Search Result Card

private struct ContentSearchResultCard: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(result.isGranted ? Color.green : Color.gray)
                    .frame(width: 5, height: 5)
                    .accessibilityLabel(result.isGranted ? "Shared" : "Not shared")
                Text(result.fileName).font(.caption.weight(.medium)).lineLimit(1)
                Text("[\(result.sourceName)]").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(result.matches) { match in
                HStack(spacing: 4) {
                    Text("L\(match.lineNumber)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 30)
                    Text(match.lineText).font(.caption.monospaced()).lineLimit(1)
                }
            }
        }
        .padding(Spacing.standard)
        .frame(width: 280, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 6))
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(result.filePath, inFileViewerRootedAtPath: "")
            }
            Button("Open") {
                NSWorkspace.shared.open(URL(fileURLWithPath: result.filePath))
            }
        }
    }
}
