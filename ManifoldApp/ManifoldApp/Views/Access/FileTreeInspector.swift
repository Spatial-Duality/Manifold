// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FileTreeInspector — the right-pane file tree for a selected source.
//
// Shows the folder's descendants as an indented DisclosureGroup tree with
// TriStateCheckbox per node. Inclusion state is currently derived from
// whether the parent source is in the selected agent's scope — Phase 3
// scaffold; real per-file policy rollup lands when ScopeStore materializes
// file-level inclusions.

import SwiftUI
import ManifoldKit

struct FileTreeInspector: View {
    @Environment(ManifoldStore.self) private var store
    let source: SourceRecord?

    @State private var root: TreeNode?
    @State private var isLoading = false
    @State private var targetAgent: TargetApp = .cowork

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let source {
                header(for: source)
                Divider()
                content
            } else {
                VStack(spacing: Spacing.s2) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select a folder to see its file tree.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.s4)
            }
        }
        .task(id: source?.sourceID) {
            guard let source else { root = nil; return }
            await loadTree(for: source)
        }
    }

    private func header(for source: SourceRecord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                FileTypeIcon(filename: source.displayName, isFolder: true, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.displayName)
                        .font(ManifoldType.bodyMedium)
                    Text(source.originalRootPath.shortenedPath)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            SegmentedToggle(
                selection: $targetAgent,
                options: [
                    .init(value: TargetApp.cowork, label: "Claude", tint: ManifoldPalette.claude,
                          systemImage: "sparkle"),
                    .init(value: TargetApp.codex,  label: "Codex",  tint: ManifoldPalette.codex,
                          systemImage: "chevron.left.forwardslash.chevron.right"),
                ]
            )
        }
        .padding(Spacing.s4)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView().progressViewStyle(.circular)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let root {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    TreeRow(
                        node: root,
                        depth: 0,
                        agent: targetAgent,
                        sourceInScope: sourceInScope(for: targetAgent),
                        store: store
                    )
                }
                .padding(Spacing.s2)
            }
        } else {
            Spacer()
            Text("No files indexed yet.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .padding(Spacing.s4)
            Spacer()
        }
    }

    private func sourceInScope(for agent: TargetApp) -> Bool {
        guard let source else { return false }
        let policy = agent == .codex ? store.policy.codexPolicy : store.policy.claudePolicy
        return policy?.allowedSourceIDs.contains(source.sourceID) == true
    }

    private func loadTree(for source: SourceRecord) async {
        isLoading = true
        let node = await TreeNode.load(from: source)
        root = node
        isLoading = false
    }
}

/// One row in the file-tree. Recursive — its children build themselves.
/// Disclosure is preserved per-node via its own @State so expansion is
/// independent of the rest of the tree.
private struct TreeRow: View {
    @State private var isExpanded: Bool
    let node: TreeNode
    let depth: Int
    let agent: TargetApp
    let sourceInScope: Bool
    let store: ManifoldStore
    @State private var overrideState: TriStateCheckbox.State?

    init(node: TreeNode,
         depth: Int,
         agent: TargetApp,
         sourceInScope: Bool,
         store: ManifoldStore) {
        self.node = node
        self.depth = depth
        self.agent = agent
        self.sourceInScope = sourceInScope
        self.store = store
        _isExpanded = State(initialValue: depth < 1)
    }

    private var effectiveState: TriStateCheckbox.State {
        if let overrideState { return overrideState }
        return sourceInScope ? .on : .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s1) {
                Rectangle()
                    .fill(ManifoldPalette.border)
                    .frame(width: 1)
                    .padding(.leading, CGFloat(depth) * 12)
                    .opacity(depth > 0 ? 0.5 : 0)

                TriStateCheckbox(
                    state: Binding(
                        get: { effectiveState },
                        set: { overrideState = $0 }
                    ),
                    override: overrideState != nil,
                    color: ManifoldPalette.agent(agent),
                    size: 14
                )

                if node.isDirectory {
                    Button {
                        withAnimation(ManifoldMotion.micro) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12)
                }

                FileTypeIcon(filename: node.name, isFolder: node.isDirectory, size: 12)
                Text(node.name)
                    .font(ManifoldType.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if node.isDirectory && !node.children.isEmpty {
                    Text("\(node.children.count)")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, Spacing.s1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(overrideState != nil ? ManifoldPalette.attentionSoft : .clear)
            )

            if node.isDirectory && isExpanded {
                ForEach(node.children) { child in
                    TreeRow(
                        node: child,
                        depth: depth + 1,
                        agent: agent,
                        sourceInScope: sourceInScope,
                        store: store
                    )
                }
            }
        }
    }
}

/// Materialized on demand from a SourceRecord; bounded to the first two
/// levels to stay responsive. Deeper levels load when a directory is
/// expanded (future work — current scaffold loads 2 levels eagerly).
private struct TreeNode: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [TreeNode]

    static func load(from source: SourceRecord) async -> TreeNode? {
        let root = URL(fileURLWithPath: source.originalRootPath)
        return await Task.detached(priority: .userInitiated) {
            walk(root: root, depth: 0, maxDepth: 2)
        }.value
    }

    private static func walk(root: URL, depth: Int, maxDepth: Int) -> TreeNode? {
        let name = root.lastPathComponent
        let id = root.path
        let isDir = (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        var children: [TreeNode] = []

        if isDir && depth < maxDepth {
            let skip: Set<String> = [".git", "node_modules", ".build", "Build",
                                      "DerivedData", "Pods", "__pycache__", ".DS_Store"]
            if let urls = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if skip.contains(url.lastPathComponent) { continue }
                    if let child = walk(root: url, depth: depth + 1, maxDepth: maxDepth) {
                        children.append(child)
                    }
                }
            }
        }
        return TreeNode(id: id, name: name, path: root.path,
                        isDirectory: isDir, children: children)
    }
}
