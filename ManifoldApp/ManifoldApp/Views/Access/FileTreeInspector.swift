// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FileTreeInspector — the right-pane file tree for a selected source.
//
// Shows the folder's descendants as an indented DisclosureGroup tree with
// TriStateCheckbox per node. Inclusion state is the source-level membership
// for the selected agent, with any persisted per-node override layered on
// top. Clicking a node records an `include` / `exclude` override against
// the runtime's PolicyStore; clicking again to match the inherited state
// clears the override and the node resumes inheriting.

import SwiftUI
import ManifoldKit

struct FileTreeInspector: View {
    @Environment(ManifoldStore.self) private var store
    let source: SourceRecord?

    @State private var root: TreeNode?
    @State private var isLoading = false
    @State private var targetAgent: TargetApp = .cowork
    /// Per-node overrides for the current source, keyed by (agent,
    /// relativePath). Repopulated on source change and after every mutation
    /// so the tree reflects the store honestly.
    @State private var overrides: [OverrideKey: NodeOverrideState] = [:]

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
            guard let source else { root = nil; overrides = [:]; return }
            await loadTree(for: source)
            await loadOverrides(for: source)
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

            // Native `Picker.segmented` — the agent picker doesn't carry
            // enough semantic per-option tint to justify a bespoke control
            // (unlike the mail sensitivity picker). Stays within the macOS
            // vocabulary the rest of the app speaks.
            Picker("Agent", selection: $targetAgent) {
                Text("Claude").tag(TargetApp.cowork)
                Text("Codex").tag(TargetApp.codex)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Tree shows what \(targetAgent == .codex ? "Codex" : "Claude") sees. Click a node to set a per-file exception; click again to clear and resume inheriting.")
                .font(ManifoldType.tiny)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
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
        } else if let root, let source {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    TreeRow(
                        node: root,
                        depth: 0,
                        agent: targetAgent,
                        sourceInScope: sourceInScope(for: targetAgent),
                        sourceRootPath: source.originalRootPath,
                        overrides: overrides,
                        onSetOverride: { relativePath, nextState in
                            Task {
                                await applyOverride(
                                    source: source,
                                    relativePath: relativePath,
                                    state: nextState
                                )
                            }
                        }
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

    private func loadOverrides(for source: SourceRecord) async {
        let records = await store.policy.nodeOverrides(sourceID: source.sourceID)
        var map: [OverrideKey: NodeOverrideState] = [:]
        for record in records {
            map[OverrideKey(agent: record.agent, relativePath: record.relativePath)] = record.state
        }
        overrides = map
    }

    private func applyOverride(
        source: SourceRecord,
        relativePath: String,
        state: NodeOverrideState
    ) async {
        await store.policy.setNodeOverride(
            sourceID: source.sourceID,
            relativePath: relativePath,
            agent: targetAgent,
            state: state
        )
        await loadOverrides(for: source)
    }
}

/// Composite key for the overrides dictionary — (agent, relativePath) is
/// the natural unit, matching how PolicyStore persists them.
struct OverrideKey: Hashable {
    let agent: TargetApp
    let relativePath: String
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
    let sourceRootPath: String
    let overrides: [OverrideKey: NodeOverrideState]
    let onSetOverride: (String, NodeOverrideState) -> Void

    init(node: TreeNode,
         depth: Int,
         agent: TargetApp,
         sourceInScope: Bool,
         sourceRootPath: String,
         overrides: [OverrideKey: NodeOverrideState],
         onSetOverride: @escaping (String, NodeOverrideState) -> Void) {
        self.node = node
        self.depth = depth
        self.agent = agent
        self.sourceInScope = sourceInScope
        self.sourceRootPath = sourceRootPath
        self.overrides = overrides
        self.onSetOverride = onSetOverride
        _isExpanded = State(initialValue: depth < 1)
    }

    /// Path relative to the source root — empty string for the root node
    /// itself, otherwise the portion after `sourceRootPath/`. Matches
    /// PolicyStore's normalization.
    private var relativePath: String {
        let root = URL(fileURLWithPath: sourceRootPath).standardizedFileURL.path
        let here = URL(fileURLWithPath: node.path).standardizedFileURL.path
        guard here.hasPrefix(root) else { return here }
        var rel = String(here.dropFirst(root.count))
        while rel.hasPrefix("/") { rel.removeFirst() }
        return rel
    }

    private var overrideState: NodeOverrideState? {
        overrides[OverrideKey(agent: agent, relativePath: relativePath)]
    }

    private var hasOverride: Bool {
        guard let s = overrideState else { return false }
        return s != .inherit
    }

    /// Inherited state: source-level membership. The root node and any
    /// node without an override resolve to this.
    private var inheritedState: TriStateCheckbox.State {
        sourceInScope ? .on : .off
    }

    /// Visible state: override if present, else inherited.
    private var effectiveState: TriStateCheckbox.State {
        switch overrideState {
        case .include: return .on
        case .exclude: return .off
        case .inherit, .none: return inheritedState
        }
    }

    /// Root node is read-only — its state is the source membership itself,
    /// which is edited in the Scope columns, not here.
    private var isRoot: Bool { relativePath.isEmpty }

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
                        set: { newState in
                            guard !isRoot else { return }
                            // If the user's click matches the inherited state
                            // while an override is in place, clear the override
                            // so the node resumes inheriting. Otherwise write
                            // the explicit include/exclude override.
                            let matchesInherited = newState == inheritedState
                            let next: NodeOverrideState
                            if matchesInherited {
                                next = .inherit
                            } else {
                                next = (newState == .on) ? .include : .exclude
                            }
                            onSetOverride(relativePath, next)
                        }
                    ),
                    override: hasOverride,
                    color: ManifoldPalette.agent(agent),
                    size: 14
                )
                .allowsHitTesting(!isRoot)
                .opacity(isRoot ? 0.55 : 1.0)

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

            if node.isDirectory && isExpanded {
                ForEach(node.children) { child in
                    TreeRow(
                        node: child,
                        depth: depth + 1,
                        agent: agent,
                        sourceInScope: sourceInScope,
                        sourceRootPath: sourceRootPath,
                        overrides: overrides,
                        onSetOverride: onSetOverride
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
