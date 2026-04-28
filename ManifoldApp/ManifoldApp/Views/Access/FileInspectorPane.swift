// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FileInspectorPane — inspector content for the Files tab.
//
// Renders an inline Quick Look preview, per-agent access chips that round-
// trip through the runtime, metadata, Open / Reveal buttons, and the
// existing tracked-versions timeline with Restore. When multiple files
// are selected, collapses to an aggregate summary.

import SwiftUI
import UniformTypeIdentifiers
import ManifoldKit

struct FileInspectorPane: View {
    @Environment(ManifoldStore.self) private var store
    let file: SourceFile?
    let selectionCount: Int
    let activity: [SnapshotRecord]
    let connectedAgents: [TargetApp]
    let visibleAgents: Set<TargetApp>
    let onToggleAgent: (TargetApp, Bool) -> Void
    let onSetAllAgents: (Bool) -> Void
    let onReset: () -> Void

    var body: some View {
        ScrollView {
            if selectionCount > 1 {
                multiSelectionSummary
                    .padding(Spacing.s4)
            } else if let file {
                singleFileContent(file)
                    .padding(Spacing.s4)
            } else {
                empty
            }
        }
    }

    // MARK: - Single file

    @ViewBuilder
    private func singleFileContent(_ file: SourceFile) -> some View {
        let url = URL(fileURLWithPath: file.path)
        let visible = visibleAgents

        VStack(alignment: .leading, spacing: Spacing.s4) {
            QuickLookPreview(url: url)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .background(ManifoldPalette.surface3)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(alignment: .top, spacing: Spacing.s2) {
                FileTypeIcon(filename: file.name, size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(ManifoldType.heading)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Text(file.relativePath)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            accessSection(file: file, visible: visible)

            HStack(spacing: Spacing.s2) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            metadata(file: file)

            Divider()

            versions(file: file)
        }
    }

    @ViewBuilder
    private func accessSection(file: SourceFile, visible: Set<TargetApp>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("Sharing")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)

            InspectorSharingSelector(
                connectedAgents: connectedAgents,
                visibleAgents: visible,
                onToggleAgent: { agent, wasVisible in
                    onToggleAgent(agent, wasVisible)
                },
                onSetAllAgents: onSetAllAgents
            )
            .accessibilityIdentifier(
                "access.inspector.file.\(file.sourceID.manifoldAccessIdentifierComponent).\(file.relativePath.manifoldAccessIdentifierComponent).selector"
            )

            Button("Reset to inherited", action: onReset)
                .buttonStyle(.borderless)
                .font(ManifoldType.caption)
        }
    }

    @ViewBuilder
    private func metadata(file: SourceFile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            row("Source", file.sourceName)
            row("Kind", kindLabel(for: file))
            row("Size", ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
            row("Modified", Self.relativeFormatter.localizedString(for: file.modifiedDate, relativeTo: .now))
        }
    }

    @ViewBuilder
    private func versions(file: SourceFile) -> some View {
        Text("Tracked versions")
            .font(ManifoldType.captionMedium)

        if activity.isEmpty {
            Text("No tracked versions yet.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                ForEach(activity.prefix(8), id: \.id) { snapshot in
                    HStack(spacing: Spacing.s2) {
                        Circle()
                            .fill(snapshot.isBaseline ? ManifoldPalette.selection : ManifoldPalette.active)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.source.capitalized)
                                .font(ManifoldType.captionMedium)
                            Text(MailDisplayFormatter.relativeTimestamp(snapshot.timestamp))
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            Task {
                                _ = await store.restoreFile(snapshotID: snapshot.id, filePath: file.path)
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Multi selection

    private var multiSelectionSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("\(selectionCount) files selected")
                .font(ManifoldType.heading)
            Text("Use the bulk bar at the bottom of the list to share, unshare, or reset overrides for the selection.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Empty

    private var empty: some View {
        ContentUnavailableView(
            "No file selected",
            systemImage: "sidebar.right",
            description: Text("Pick a file to inspect visibility, overrides, and tracked versions.")
        )
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text(title)
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(ManifoldType.caption)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func kindLabel(for file: SourceFile) -> String {
        let ext = file.fileExtension.isEmpty
            ? (file.path as NSString).pathExtension
            : file.fileExtension
        if ext.isEmpty { return "File" }
        if let type = UTType(filenameExtension: ext), let desc = type.localizedDescription {
            return desc
        }
        return ext.uppercased()
    }

    static let relativeFormatter = RelativeDateTimeFormatter()
}
