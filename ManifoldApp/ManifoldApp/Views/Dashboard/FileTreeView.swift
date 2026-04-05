import SwiftUI
import AppKit

/// Lazy-loaded file tree browser. Children loaded on expand.
struct FileTreeView: View {
    let rootPath: String
    @State private var rootNodes: [FileNode] = []

    var body: some View {
        Group {
            if rootNodes.isEmpty {
                Text("Loading...").foregroundStyle(.tertiary)
            } else {
                ForEach(rootNodes) { node in
                    FileNodeRow(node: node)
                }
            }
        }
        .task { rootNodes = FileNode.loadChildren(at: rootPath) }
    }
}

struct FileNodeRow: View {
    let node: FileNode
    @State private var isExpanded = false
    @State private var children: [FileNode]?

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let children {
                    ForEach(children) { child in
                        FileNodeRow(node: child)
                    }
                } else {
                    Text("Loading...").foregroundStyle(.tertiary).font(.caption)
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .font(.callout)
            }
            .onChange(of: isExpanded) { _, expanded in
                if expanded && children == nil {
                    children = FileNode.loadChildren(at: node.path)
                }
            }
            .contextMenu { fileContextMenu(path: node.path, isDirectory: true) }
        } else {
            HStack {
                Label(node.name, systemImage: node.iconName)
                    .font(.callout)
                Spacer()
                if node.fileSize > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(node.fileSize), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .contextMenu { fileContextMenu(path: node.path, isDirectory: false) }
        }
    }

    @ViewBuilder
    private func fileContextMenu(path: String, isDirectory: Bool) -> some View {
        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }
        if !isDirectory {
            Button("Open") {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }
}
