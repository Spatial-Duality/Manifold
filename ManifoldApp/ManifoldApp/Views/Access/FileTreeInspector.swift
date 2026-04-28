// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FileTreeInspector — the right-pane file tree for a selected source.
//
// Shows the folder's descendants as an indented DisclosureGroup tree with
// persisted folder/file overrides per node. Each row resolves inherited
// visibility through the same override store used by the flat file browser,
// so subfolders can be allowed, hidden, or reset back to inherited scope.

import AppKit
import SwiftUI
import ManifoldKit

struct FileTreeInspector: View {
    @Environment(ManifoldStore.self) private var store
    let source: SourceRecord?

    @State private var root: TreeNode?
    @State private var isLoading = false
    @State private var targetAgent: TargetApp = .cowork
    @State private var overrides: [FileVisibilityOverrideRecord] = []

    private var connectedAgents: [TargetApp] {
        AgentMeta.connected(from: store.connectedAgents)
    }

    private var effectiveAgent: TargetApp {
        if connectedAgents.contains(targetAgent) { return targetAgent }
        return connectedAgents.first ?? .cowork
    }

    private var agentsWithScope: Set<TargetApp> {
        guard let source else { return [] }
        var set: Set<TargetApp> = []
        for agent in connectedAgents {
            if let governance = store.governance.policy(for: agent),
               governance.allowedSourceIDs.contains(source.sourceID) {
                set.insert(agent)
            }
        }
        return set
    }

    private var visibilityResolver: FileVisibilityResolver {
        FileVisibilityResolver(overrides: overrides)
    }

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
            guard let source else {
                root = nil
                return
            }
            await loadTree(for: source)
        }
        .task(id: effectiveAgent) {
            overrides = await store.fileVisibilityOverrides(agent: effectiveAgent)
        }
    }

    private func header(for source: SourceRecord) -> some View {
        // Title row carries the folder name + the per-agent share chips.
        // Inspector is only ~320pt wide, so the chip strip dominates if
        // we lay it inline with the name. Stack title above chips so
        // both have full width and the header stays compact.
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: Spacing.s2) {
                FileTypeIcon(filename: source.displayName, isFolder: true, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.displayName)
                        .font(ManifoldType.bodyMedium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(source.originalRootPath.shortenedPath)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }

            AccessCheckboxStrip(
                agents: connectedAgents,
                visibleAgents: agentsWithScope,
                accessibilityIDPrefix: "access.inspector.folder.\(source.sourceID.manifoldAccessIdentifierComponent)",
                onToggleAgent: { agent, wasVisible in
                    Task {
                        await store.setSourceScope(
                            sourceID: source.sourceID,
                            agent: agent,
                            inScope: !wasVisible
                        )
                    }
                },
                onSetAll: { inScope in
                    Task {
                        await setSourceScope(agents: connectedAgents, inScope: inScope)
                    }
                }
            )

            // Agent picker only when there's a real choice. Single-agent
            // setups don't need a row to "select" the only AI — the
            // chips already tell the whole story. The "No agents
            // connected" hint also drops out: the chips render as
            // disabled when no AI is wired up.
            if connectedAgents.count > 1 {
                Picker("Agent", selection: Binding(
                    get: { effectiveAgent },
                    set: { targetAgent = $0 }
                )) {
                    ForEach(connectedAgents, id: \.self) { agent in
                        Text(AgentMeta.label(agent)).tag(agent)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
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
                        source: source,
                        agent: effectiveAgent,
                        sourceInScope: sourceInScope(for: effectiveAgent),
                        resolver: visibilityResolver,
                        onSetSourceScope: { inScope in await setSourceScope(inScope) },
                        onAllow: { node in await setOverride(.allow, for: node) },
                        onHide: { node in await setOverride(.deny, for: node) },
                        onReset: { node in await clearOverride(for: node) }
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
        return store.governance.policy(for: agent)?.allowedSourceIDs.contains(source.sourceID) == true
    }

    private func loadTree(for source: SourceRecord) async {
        isLoading = true
        let node = await TreeNode.load(from: source)
        root = node
        isLoading = false
    }

    private func setOverride(_ decision: FileVisibilityOverrideDecision, for node: TreeNode) async {
        guard let source, !node.relativePath.isEmpty else { return }
        await store.setFileVisibilityOverride(
            agent: effectiveAgent,
            sourceID: source.sourceID,
            relativePath: node.relativePath,
            isDirectory: node.isDirectory,
            decision: decision
        )
        overrides = await store.fileVisibilityOverrides(agent: effectiveAgent)
    }

    private func clearOverride(for node: TreeNode) async {
        guard let source, !node.relativePath.isEmpty else { return }
        await store.clearFileVisibilityOverride(
            agent: effectiveAgent,
            sourceID: source.sourceID,
            relativePath: node.relativePath,
            isDirectory: node.isDirectory
        )
        overrides = await store.fileVisibilityOverrides(agent: effectiveAgent)
    }

    private func setSourceScope(_ inScope: Bool) async {
        guard let source else { return }
        await store.setSourceScope(sourceID: source.sourceID, agent: effectiveAgent, inScope: inScope)
        overrides = await store.fileVisibilityOverrides(agent: effectiveAgent)
    }

    private func setSourceScope(agents: [TargetApp], inScope: Bool) async {
        guard let source else { return }
        for agent in agents {
            await store.setSourceScope(sourceID: source.sourceID, agent: agent, inScope: inScope)
        }
        overrides = await store.fileVisibilityOverrides(agent: effectiveAgent)
    }
}

private struct TreeRow: View {
    @State private var isExpanded: Bool

    let node: TreeNode
    let depth: Int
    let source: SourceRecord?
    let agent: TargetApp
    let sourceInScope: Bool
    let resolver: FileVisibilityResolver
    let onSetSourceScope: @Sendable (Bool) async -> Void
    let onAllow: @Sendable (TreeNode) async -> Void
    let onHide: @Sendable (TreeNode) async -> Void
    let onReset: @Sendable (TreeNode) async -> Void

    init(
        node: TreeNode,
        depth: Int,
        source: SourceRecord?,
        agent: TargetApp,
        sourceInScope: Bool,
        resolver: FileVisibilityResolver,
        onSetSourceScope: @escaping @Sendable (Bool) async -> Void,
        onAllow: @escaping @Sendable (TreeNode) async -> Void,
        onHide: @escaping @Sendable (TreeNode) async -> Void,
        onReset: @escaping @Sendable (TreeNode) async -> Void
    ) {
        self.node = node
        self.depth = depth
        self.source = source
        self.agent = agent
        self.sourceInScope = sourceInScope
        self.resolver = resolver
        self.onSetSourceScope = onSetSourceScope
        self.onAllow = onAllow
        self.onHide = onHide
        self.onReset = onReset
        _isExpanded = State(initialValue: depth < 1)
    }

    private var visibilityState: VisibilityState {
        resolvedVisibilityState(for: node)
    }

    private var checkboxState: TriStateCheckbox.State {
        switch visibilityState.effective {
        case .allowed:
            return .on
        case .hidden:
            return .off
        case .mixed:
            return .mixed
        }
    }

    private var canOverride: Bool {
        source != nil
    }

    private var hasExplicitOverride: Bool {
        guard let source else { return false }
        let evaluation = resolver.evaluate(
            sourceID: source.sourceID,
            relativePath: node.relativePath,
            defaultVisible: sourceInScope
        )
        return evaluation.origin == .explicitAllow || evaluation.origin == .explicitDeny
    }

    private var agentLabel: String {
        agent == .cowork ? "Claude" : "Codex"
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
                        get: { checkboxState },
                        set: { newValue in
                            guard canOverride else { return }
                            if node.relativePath.isEmpty {
                                Task { await onSetSourceScope(newValue != .off) }
                                return
                            }
                            switch newValue {
                            case .on, .mixed:
                                Task { await onAllow(node) }
                            case .off:
                                Task { await onHide(node) }
                            }
                        }
                    ),
                    override: hasExplicitOverride,
                    color: ManifoldPalette.agent(agent),
                    size: 14
                )
                .disabled(!canOverride)

                if node.isDirectory {
                    Button {
                        withAnimation(ManifoldMotion.micro) {
                            isExpanded.toggle()
                        }
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

                Spacer(minLength: Spacing.s2)

                VisibilityChip(state: visibilityState)

                if hasExplicitOverride {
                    Button {
                        Task { await onReset(node) }
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundStyle(ManifoldPalette.text2)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to inherited visibility")
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, Spacing.s1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hasExplicitOverride ? ManifoldPalette.attentionSoft : .clear)
            )
            .contextMenu {
                if canOverride {
                    if node.relativePath.isEmpty {
                        Button("Share folder with \(agentLabel)") {
                            Task { await onSetSourceScope(true) }
                        }
                        Button("Hide folder from \(agentLabel)") {
                            Task { await onSetSourceScope(false) }
                        }
                    } else {
                        Button("Allow for \(agentLabel)") {
                            Task { await onAllow(node) }
                        }
                        Button("Hide for \(agentLabel)") {
                            Task { await onHide(node) }
                        }
                        Button("Reset to inherited") {
                            Task { await onReset(node) }
                        }
                    }
                    Divider()
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.path, forType: .string)
                }
            }

            if node.isDirectory && isExpanded {
                ForEach(node.children) { child in
                    TreeRow(
                        node: child,
                        depth: depth + 1,
                        source: source,
                        agent: agent,
                        sourceInScope: sourceInScope,
                        resolver: resolver,
                        onSetSourceScope: onSetSourceScope,
                        onAllow: onAllow,
                        onHide: onHide,
                        onReset: onReset
                    )
                }
            }
        }
    }

    private func resolvedVisibilityState(for node: TreeNode) -> VisibilityState {
        guard let source else {
            return VisibilityState(effective: .hidden, origin: .defaultScope)
        }

        let evaluation = resolver.evaluate(
            sourceID: source.sourceID,
            relativePath: node.relativePath,
            defaultVisible: sourceInScope
        )
        let ownState = visibilityState(from: evaluation)

        guard node.isDirectory, !node.children.isEmpty else {
            return ownState
        }

        let childStates = node.children.map(resolvedVisibilityState(for:))
        let allAllowed = childStates.allSatisfy { $0.effective == .allowed }
        let allHidden = childStates.allSatisfy { $0.effective == .hidden }

        if allAllowed {
            return VisibilityState(effective: .allowed, origin: ownState.origin)
        }
        if allHidden {
            return VisibilityState(effective: .hidden, origin: ownState.origin)
        }

        let hasExplicitChild = childStates.contains { $0.origin == .explicit }
        return VisibilityState(
            effective: .mixed,
            origin: ownState.origin == .explicit || hasExplicitChild ? .explicit : .defaultScope
        )
    }

    private func visibilityState(from evaluation: FileVisibilityEvaluation) -> VisibilityState {
        switch evaluation.origin {
        case .explicitAllow:
            return VisibilityState(effective: .allowed, origin: .explicit)
        case .explicitDeny:
            return VisibilityState(effective: .hidden, origin: .explicit)
        case .inheritedAllow:
            return VisibilityState(effective: .allowed, origin: .defaultScope)
        case .inheritedHidden:
            return VisibilityState(effective: .hidden, origin: .defaultScope)
        }
    }
}

private struct TreeNode: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let relativePath: String
    let isDirectory: Bool
    let children: [TreeNode]

    static func load(from source: SourceRecord) async -> TreeNode? {
        let root = URL(fileURLWithPath: source.originalRootPath)
        return await Task.detached(priority: .userInitiated) {
            walk(root: root, baseRoot: root, depth: 0, maxDepth: 2)
        }.value
    }

    private static func walk(root: URL, baseRoot: URL, depth: Int, maxDepth: Int) -> TreeNode? {
        let name = root.lastPathComponent
        let id = root.path
        let relativePath: String
        if root.path == baseRoot.path {
            relativePath = ""
        } else {
            relativePath = String(root.path.dropFirst(baseRoot.path.count + 1))
        }
        let isDirectory = (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        var children: [TreeNode] = []

        if isDirectory && depth < maxDepth {
            let skip: Set<String> = [".git", "node_modules", ".build", "Build", "DerivedData", "Pods", "__pycache__", ".DS_Store"]
            if let urls = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if skip.contains(url.lastPathComponent) { continue }
                    if let child = walk(root: url, baseRoot: baseRoot, depth: depth + 1, maxDepth: maxDepth) {
                        children.append(child)
                    }
                }
            }
        }

        return TreeNode(
            id: id,
            name: name,
            path: root.path,
            relativePath: relativePath,
            isDirectory: isDirectory,
            children: children
        )
    }
}
