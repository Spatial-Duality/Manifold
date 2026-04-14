// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FilesFlatView — flat, sortable list of every file under every shared
// source. Columns: name, path, size, source, modified. Phase 3 scaffold
// without the version timeline — version chips land once snapshot
// tracking is wired through ManifoldCommands.

import SwiftUI
import ManifoldKit

struct FilesFlatView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var files: [SourceFile] = []
    @State private var isLoading = false

    var body: some View {
        Table(of: SourceFile.self) {
            TableColumn("Name") { file in
                HStack(spacing: Spacing.s2) {
                    FileTypeIcon(filename: file.name, size: 13)
                    Text(file.name)
                        .font(ManifoldType.body)
                }
            }
            .width(min: 160)
            TableColumn("Path") { file in
                Text(file.relativePath)
                    .font(ManifoldType.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("Source") { file in
                Text(file.sourceName)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            .width(120)
            TableColumn("Size") { file in
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
            }
            .width(72)
            TableColumn("Modified") { file in
                Text(Self.relativeFormatter.localizedString(for: file.modifiedDate, relativeTo: .now))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
            }
            .width(140)
        } rows: {
            ForEach(files, id: \.path) { file in
                TableRow(file)
            }
        }
        .tableStyle(.inset)
        .overlay {
            if isLoading && files.isEmpty {
                ProgressView().progressViewStyle(.circular)
            } else if files.isEmpty {
                VStack(spacing: Spacing.s2) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No files visible yet.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            isLoading = true
            files = await store.enumerateSourceFiles()
            isLoading = false
        }
    }

    private static let relativeFormatter = RelativeDateTimeFormatter()
}
