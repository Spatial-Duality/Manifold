import SwiftUI

struct SessionView: View {
    @Environment(ManifoldStore.self) var store
    @State private var files: [SourceFile] = []
    @State private var selectedFileIDs: Set<UUID> = []
    @State private var sortOrder = [KeyPathComparator(\SourceFile.name)]
    @State private var searchText = ""
    @State private var isLoading = true

    private var activeSources: [SourceRecord] {
        store.sources.filter { $0.isAccessible && !$0.isRemoved }
    }

    private var sortedFiles: [SourceFile] {
        var result = files
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedStandardContains(searchText) ||
                $0.sourceName.localizedStandardContains(searchText) ||
                $0.fileExtension.localizedStandardContains(searchText)
            }
        }
        result.sort(using: sortOrder)
        return result
    }

    var body: some View {
        Group {
            if activeSources.isEmpty {
                SessionEmptyState()
            } else if isLoading && files.isEmpty {
                ProgressView("Scanning sources...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sortedFiles.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView("No Files Found", systemImage: "doc",
                        description: Text("The selected sources appear to be empty."))
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                SessionFileTable(
                    sortedFiles: sortedFiles,
                    files: files,
                    selectedFileIDs: $selectedFileIDs,
                    sortOrder: $sortOrder,
                    onReload: { Task { await loadFiles() } }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Files")
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter files")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await loadFiles() }
                }
            }
        }
        .task { await loadFiles() }
        .onChange(of: store.sources) {
            Task { await loadFiles() }
        }
        .onChange(of: selectedFileIDs) {
            if let id = selectedFileIDs.first, let file = files.first(where: { $0.id == id }) {
                store.inspectedFilePath = file.path
            } else {
                store.inspectedFilePath = nil
            }
        }
    }

    private var subtitle: String {
        let count = files.count
        let sourceCount = activeSources.count
        if activeSources.isEmpty { return "No sources" }
        if isLoading { return "Scanning..." }
        return "\(count) file\(count == 1 ? "" : "s") across \(sourceCount) source\(sourceCount == 1 ? "" : "s")"
    }

    // MARK: - Loading

    private func loadFiles() async {
        isLoading = files.isEmpty
        files = await store.enumerateSourceFiles()
        isLoading = false
    }
}

// MARK: - File Table

private struct SessionFileTable: View {
    @Environment(ManifoldStore.self) var store
    let sortedFiles: [SourceFile]
    let files: [SourceFile]
    @Binding var selectedFileIDs: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<SourceFile>]
    var onReload: () -> Void

    @State private var renamingFileID: UUID?
    @State private var renameText = ""

    var body: some View {
        Table(sortedFiles, selection: $selectedFileIDs, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { file in
                Label {
                    Text(file.name)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: iconName(for: file))
                        .foregroundStyle(iconColor(for: file))
                }
            }
            .width(min: 140, ideal: 220)

            TableColumn("Source", value: \.sourceName) { file in
                Text(file.sourceName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 100)

            TableColumn("Size") { file in
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 70)

            TableColumn("Modified") { file in
                Text(file.modifiedDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Versions") { file in
                if file.versionCount > 0 {
                    HStack(spacing: 3) {
                        if file.hasAIActivity {
                            Image(systemName: "sparkle")
                                .font(.caption2)
                                .foregroundStyle(Color(nsColor: .systemBlue))
                                .accessibilityLabel("AI accessed")
                        }
                        Text("\(file.versionCount)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .foregroundStyle(.quaternary)
                }
            }
            .width(min: 50, ideal: 65)

            TableColumn("Kind") { file in
                Text(file.fileExtension.isEmpty ? "—" : file.fileExtension.uppercased())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .width(min: 40, ideal: 55)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            fileContextMenu(for: ids)
        }
        .alert("Rename File", isPresented: Binding(
            get: { renamingFileID != nil },
            set: { if !$0 { renamingFileID = nil } }
        )) {
            TextField("New name", text: $renameText)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) { renamingFileID = nil }
        }
    }

    // MARK: - Context Menu (Finder-like)

    @ViewBuilder
    private func fileContextMenu(for ids: Set<UUID>) -> some View {
        let selected = files.filter { ids.contains($0.id) }

        if selected.count == 1, let file = selected.first {
            Button("Quick Look") {
                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
            }

            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
            }

            if file.versionCount > 0 {
                Button("View History") {
                    store.inspectedFilePath = file.path
                }
            }

            Divider()

            Button("Rename...") {
                renameText = file.name
                renamingFileID = file.id
            }

            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }

            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.name, forType: .string)
            }

            Divider()

            Button("Open with Default App") {
                NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
            }
        } else if selected.count > 1 {
            Button("Reveal \(selected.count) Items in Finder") {
                let urls = selected.map { URL(fileURLWithPath: $0.path) }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }

            Button("Copy \(selected.count) Paths") {
                let paths = selected.map(\.path).joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths, forType: .string)
            }
        }
    }

    private func performRename() {
        guard let id = renamingFileID,
              let file = files.first(where: { $0.id == id }),
              !renameText.isEmpty,
              renameText != file.name else {
            renamingFileID = nil
            return
        }
        let dir = URL(fileURLWithPath: file.path).deletingLastPathComponent()
        let newPath = dir.appendingPathComponent(renameText)
        do {
            try FileManager.default.moveItem(
                at: URL(fileURLWithPath: file.path),
                to: newPath
            )
            onReload()
        } catch {
            store.lastError = "Rename failed: \(error.localizedDescription)"
        }
        renamingFileID = nil
    }

    // MARK: - File Appearance

    private func iconName(for file: SourceFile) -> String {
        let ext = file.fileExtension
        return switch ext {
        case "swift", "py", "js", "ts", "rb", "go", "rs": "doc.text"
        case "html", "css", "xml", "json", "yaml", "yml", "toml": "doc.text"
        case "md", "txt", "rtf": "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico": "photo"
        case "pdf": "doc.richtext"
        case "zip", "tar", "gz", "rar": "doc.zipper"
        case "mp4", "mov", "avi": "film"
        case "mp3", "wav", "aac": "music.note"
        default: "doc"
        }
    }

    private func iconColor(for file: SourceFile) -> Color {
        let ext = file.fileExtension
        return switch ext {
        case "swift": Color(nsColor: .systemOrange)
        case "py": Color(nsColor: .systemBlue)
        case "js", "ts": Color(nsColor: .systemYellow)
        case "md", "txt": Color(nsColor: .systemGray)
        case "json", "yaml", "yml", "toml": Color(nsColor: .systemPurple)
        case "png", "jpg", "jpeg", "gif", "webp", "svg": Color(nsColor: .systemTeal)
        default: .secondary
        }
    }
}

// MARK: - Empty State

private struct SessionEmptyState: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        ContentUnavailableView {
            Label("No Sources", systemImage: "folder.badge.plus")
        } description: {
            Text("Add a folder in Sources to browse files here.")
        } actions: {
            Button("Go to Sources") {
                store.selectedSidebarItem = .sources
            }
            .glassProminentButton()
        }
    }
}
