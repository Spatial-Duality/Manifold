import SwiftUI
import AppKit
import ManifoldKit

struct FilesView: View {
    @Environment(ManifoldStore.self) var store

    @State private var allFiles: [SourceFile] = []
    @State private var filteredFiles: [SourceFile] = []
    @State private var searchText = ""
    @State private var contentSearchText = ""
    @State private var contentSearchResults: [SearchResult] = []
    @State private var isSearchingContent = false
    @State private var nameFilterTask: Task<Void, Never>?

    // Filters
    @State private var filterSource = "All"
    @State private var filterType = "All"
    @State private var sortBy: SortOption = .name

    // (bulk selection removed — List doesn't support Table-style multi-select)

    enum SortOption: String, CaseIterable {
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

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: Spacing.section) {
                Picker("Source", selection: $filterSource) {
                    ForEach(sourceNames, id: \.self) { Text($0) }
                }
                .frame(maxWidth: 160)

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
                contentSearchSection
            }

            // File list
            if filteredFiles.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "doc",
                    description: Text(store.hasActiveSession
                        ? "No files match your filters."
                        : "Start a session to browse the managed workspace.")
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
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("Files")
        .navigationSubtitle(store.hasActiveSession
            ? "\(allFiles.count) files across \(store.activeGrantSources.count) sources"
            : "No active session")
        .task { reloadFiles() }
        .onChange(of: store.sources.count) { _, _ in Task { @MainActor in reloadFiles() } }
        .onChange(of: store.hasActiveSession) { _, _ in Task { @MainActor in reloadFiles() } }
        .onChange(of: store.activeGrantSources.count) { _, _ in Task { @MainActor in reloadFiles() } }
        .onChange(of: searchText) { _, _ in
            nameFilterTask?.cancel()
            nameFilterTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                applyFilters()
            }
        }
        .onChange(of: filterSource) { _, _ in Task { @MainActor in applyFilters() } }
        .onChange(of: filterType) { _, _ in Task { @MainActor in applyFilters() } }
        .onChange(of: sortBy) { _, _ in Task { @MainActor in applyFilters() } }
    }

    // MARK: - Content Search Results

    private var contentSearchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Content matches: \(contentSearchResults.count) files")
                    .font(.caption.weight(.medium))
                Spacer()
                Button("Dismiss") { contentSearchResults = [] }
                    .controlSize(.mini)
            }
            .padding(.horizontal, Spacing.edge).padding(.vertical, Spacing.standard)
            .background(Color.accentColor.opacity(0.08))

            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(contentSearchResults) { result in
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
                .padding(.horizontal, Spacing.edge).padding(.vertical, Spacing.standard)
            }
            .scrollIndicators(.hidden)
            .frame(height: 120)

            Divider()
        }
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

    private func reloadFiles() {
        allFiles = store.enumerateAllFiles()
        applyFilters()
    }

    private func applyFilters() {
        var result = allFiles

        if filterSource != "All" {
            result = result.filter { $0.sourceName == filterSource }
        }
        if filterType != "All" {
            result = result.filter { $0.fileExtension == filterType }
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
        case "swift", "py", "js", "ts", "rb", "go", "rs", "c", "cpp", "h": return "doc.text"
        case "html", "css", "xml", "json", "yaml", "yml", "toml": return "doc.text"
        case "md", "txt", "rtf": return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz": return "doc.zipper"
        case "mp4", "mov": return "film"
        case "mp3", "wav": return "music.note"
        case "ttf", "otf", "woff", "woff2": return "textformat"
        default: return "doc"
        }
    }
}
