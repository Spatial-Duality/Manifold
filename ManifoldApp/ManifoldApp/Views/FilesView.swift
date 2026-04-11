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
    @State private var filterType = "All"
    @State private var cachedSourceNames: [String] = ["All"]
    @State private var cachedFileTypes: [String] = ["All"]
    @SceneStorage("filesSortBy") private var sortBy: SortOption = .name

    private enum SortOption: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case modified = "Modified"
        case type = "Type"
    }

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

    private var navigationTitleText: String {
        if let selectedSourceName { return selectedSourceName }
        if isRecentlyModifiedSelection { return "Recently Modified" }
        if isAITouchedSelection { return "AI-Touched Files" }
        return "Files"
    }

    private var navigationSubtitleText: String {
        let sourceCount = selectedSourceID == nil ? store.sources.filter { !$0.isRemoved }.count : 1
        return "\(filteredFiles.count) of \(allFiles.count) files across \(sourceCount) source\(sourceCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: Spacing.section) {
                Picker("Source", selection: $filterSource) {
                    ForEach(cachedSourceNames, id: \.self) { Text($0) }
                }
                .frame(maxWidth: 160)
                .disabled(selectedSourceID != nil)

                Picker("Sort", selection: $sortBy) {
                    ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue) }
                }
                .frame(maxWidth: 120)

                TextField("Filter by name...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)

                Text("\(filteredFiles.count) files")
                    .font(Typ.numericCaption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.edge).padding(.vertical, Spacing.standard)

            Divider()

            // Content search bar
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
                TextField("Search inside files...", text: $contentSearchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { searchContent() }
                if isSearchingContent {
                    ProgressView().controlSize(.small)
                }
                if !contentSearchText.isEmpty {
                    Button("Search") { searchContent() }
                        .controlSize(.small)
                    Button("Clear") { contentSearchText = ""; contentSearchResults = [] }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Spacing.edge).padding(.vertical, Spacing.standard)

            Divider()

            // Content search results
            if !contentSearchResults.isEmpty {
                ContentSearchResultsSection(
                    results: contentSearchResults,
                    onDismiss: { contentSearchResults = [] }
                )
            }

            // File list
            if filteredFiles.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "doc",
                    description: Text(allFiles.isEmpty
                        ? "Add a source folder from the Files sidebar to browse files."
                        : "No files match your filters.")
                )
            } else {
                List(filteredFiles) { file in
                    HStack(spacing: 8) {
                        Image(systemName: iconFor(file.fileExtension))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name).font(.callout).lineLimit(1)
                            Text(file.relativePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Circle()
                                .fill(file.isGrantedToClaude ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel(file.isGrantedToClaude ? "Shared with AI" : "Not shared")
                            Text(file.sourceName).font(.caption)
                        }
                        .frame(width: 100, alignment: .leading)

                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)

                        Text(file.modifiedDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)

                        Text(file.fileExtension.isEmpty ? "" : ".\(file.fileExtension)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .frame(width: 45, alignment: .trailing)
                    }
                    .contextMenu { fileContextMenu(file: file) }
                }
                .listStyle(.inset)
            }
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
        .onChange(of: filterType) { _, _ in scheduleFilter() }
        .onChange(of: sortBy) { _, _ in scheduleFilter() }
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
        cachedFileTypes = ["All"] + Array(Set(allFiles.map(\.fileExtension).filter { !$0.isEmpty })).sorted()
    }

    /// Runs filtering and sorting off the main thread, then assigns results back.
    private func applyFilters() async {
        let snapshot = allFiles
        let source = selectedSourceID
        let sourceName = filterSource
        let fileType = filterType
        let aiTouched = isAITouchedSelection
        let query = searchText
        let sort = sortBy

        let result = await Task.detached(priority: .userInitiated) {
            var items = snapshot

            if let source {
                items = items.filter { $0.sourceID == source }
            } else if sourceName != "All" {
                items = items.filter { $0.sourceName == sourceName }
            }
            if fileType != "All" {
                items = items.filter { $0.fileExtension == fileType }
            }
            if aiTouched {
                items = items.filter(\.hasAIActivity)
            }
            if !query.isEmpty {
                items = items.filter { $0.name.localizedStandardContains(query) || $0.relativePath.localizedStandardContains(query) }
            }

            switch sort {
            case .name: items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .size: items.sort { $0.sizeBytes > $1.sizeBytes }
            case .modified: items.sort { $0.modifiedDate > $1.modifiedDate }
            case .type: items.sort { $0.fileExtension < $1.fileExtension }
            }

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
            sortBy = .modified
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
