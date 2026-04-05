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
    @State private var searchIncludeArchived = false

    // Filters
    @State private var filterSource = "All"
    @State private var filterType = "All"
    @State private var sortBy: SortOption = .name

    // Selection for bulk operations
    @State private var selectedFiles: Set<UUID> = []

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
            HStack(spacing: 12) {
                Picker("Source", selection: $filterSource) {
                    ForEach(sourceNames, id: \.self) { Text($0) }
                }
                .frame(maxWidth: 160)

                Picker("Type", selection: $filterType) {
                    ForEach(fileTypes, id: \.self) { name in
                        Text(name == "All" ? "All Types" : ".\(name)")
                    }
                }
                .frame(maxWidth: 120)

                Picker("Sort", selection: $sortBy) {
                    ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue) }
                }
                .frame(maxWidth: 120)

                Spacer()

                Text("\(filteredFiles.count) files")
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
            .padding(.horizontal).padding(.vertical, 8)

            Divider()

            // Content search bar
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
                TextField("Search inside files...", text: $contentSearchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { searchContent() }
                Toggle("Include paused", isOn: $searchIncludeArchived)
                    .toggleStyle(.checkbox)
                    .font(.caption)
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
            .padding(.horizontal).padding(.vertical, 6)

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
                    description: Text(store.workspaces.isEmpty ? "Add a source folder first." : "No files match your filters.")
                )
            } else {
                Table(filteredFiles, selection: $selectedFiles) {
                    TableColumn("Name") { file in
                        HStack(spacing: 6) {
                            Image(systemName: iconFor(file.fileExtension))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).font(.callout).lineLimit(1)
                                Text(file.relativePath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .contextMenu { fileContextMenu(file: file) }
                    }
                    .width(min: 200, ideal: 300)

                    TableColumn("Source") { file in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(file.isGrantedToClaude ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            Text(file.sourceName).font(.caption)
                        }
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Size") { file in
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Modified") { file in
                        Text(file.modifiedDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("Type") { file in
                        Text(file.fileExtension.isEmpty ? "—" : ".\(file.fileExtension)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .width(min: 50, ideal: 60)
                }
            }
        }
        .navigationTitle("Files")
        .navigationSubtitle("\(allFiles.count) files across \(store.workspaces.filter { $0.status != "archived" }.count) sources")
        .searchable(text: $searchText, prompt: "Filter by name...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Source", systemImage: "folder.badge.plus") {
                    store.addSourceFromPicker()
                    reloadFiles()
                }
            }
            if !selectedFiles.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Button("Open \(selectedFiles.count) in Finder") {
                        for id in selectedFiles {
                            if let file = allFiles.first(where: { $0.id == id }) {
                                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .task { reloadFiles() }
        .onChange(of: store.workspaces.count) { _, _ in reloadFiles() }
        .onChange(of: searchText) { _, _ in applyFilters() }
        .onChange(of: filterSource) { _, _ in applyFilters() }
        .onChange(of: filterType) { _, _ in applyFilters() }
        .onChange(of: sortBy) { _, _ in applyFilters() }
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
            .padding(.horizontal).padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(contentSearchResults) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(result.isGranted ? Color.green : Color.gray)
                                    .frame(width: 5, height: 5)
                                Text(result.fileName).font(.caption.weight(.medium)).lineLimit(1)
                                Text("[\(result.sourceName)]").font(.caption2).foregroundStyle(.tertiary)
                            }
                            ForEach(result.matches) { match in
                                HStack(spacing: 4) {
                                    Text("L\(match.lineNumber)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 30)
                                    Text(match.lineText).font(.caption2.monospaced()).lineLimit(1)
                                }
                            }
                        }
                        .padding(8)
                        .frame(width: 280, alignment: .leading)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                .padding(.horizontal).padding(.vertical, 8)
            }
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
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.relativePath.localizedCaseInsensitiveContains(searchText) }
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
        isSearchingContent = true
        contentSearchResults = store.searchFileContents(query: contentSearchText, includeArchived: searchIncludeArchived)
        isSearchingContent = false
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
