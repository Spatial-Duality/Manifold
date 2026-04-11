import SwiftUI
import AppKit
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
    @State private var nameFilterTask: Task<Void, Never>?
    @State private var reloadTask: Task<Void, Never>?

    // Filters
    @State private var filterSource = "All"
    @State private var filterType = "All"
    @State private var sortBy: SortOption = .name

    private enum SortOption: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case modified = "Modified"
        case type = "Type"
    }

    private var sourceNames: [String] {
        ["All"] + Array(Set(allFiles.map(\.sourceName))).sorted()
    }

    private var fileTypes: [String] {
        ["All"] + Array(Set(allFiles.map(\.fileExtension).filter { !$0.isEmpty })).sorted()
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
                    ForEach(sourceNames, id: \.self) { Text($0) }
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
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
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
        .onChange(of: searchText) { _, _ in
            nameFilterTask?.cancel()
            nameFilterTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                applyFilters()
            }
        }
        .onChange(of: filterSource) { _, _ in applyFilters() }
        .onChange(of: filterType) { _, _ in applyFilters() }
        .onChange(of: sortBy) { _, _ in applyFilters() }
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

    private func reloadFiles() {
        Task {
            if store.hasActiveSession {
                allFiles = await store.enumerateAllFiles()
            } else {
                allFiles = await store.enumerateSourceFiles()
            }
            applyFilters()
        }
    }

    private func applyFilters() {
        var result = allFiles

        if let selectedSourceID {
            result = result.filter { $0.sourceID == selectedSourceID }
        } else if filterSource != "All" {
            result = result.filter { $0.sourceName == filterSource }
        }
        if filterType != "All" {
            result = result.filter { $0.fileExtension == filterType }
        }
        if isAITouchedSelection {
            result = result.filter(\.hasAIActivity)
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedStandardContains(searchText) || $0.relativePath.localizedStandardContains(searchText) }
        }

        switch sortBy {
        case .name: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size: result.sort { $0.sizeBytes > $1.sizeBytes }
        case .modified: result.sort { $0.modifiedDate > $1.modifiedDate }
        case .type: result.sort { $0.fileExtension < $1.fileExtension }
        }

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
        isSearchingContent = true
        let query = contentSearchText
        Task {
            let results = store.searchFileContents(query: query)
            contentSearchResults = results
            isSearchingContent = false
        }
    }

    private func iconFor(_ ext: String) -> String {
        switch ext {
        case "swift", "py", "js", "ts", "rb", "go", "rs", "c", "cpp", "h": "doc.text"
        case "html", "css", "xml", "json", "yaml", "yml", "toml": "doc.text"
        case "md", "txt", "rtf": "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": "photo"
        case "pdf": "doc.richtext"
        case "zip", "tar", "gz": "doc.zipper"
        case "mp4", "mov": "film"
        case "mp3", "wav": "music.note"
        case "ttf", "otf", "woff", "woff2": "textformat"
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
