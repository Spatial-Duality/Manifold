// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FileDropTarget — single source of truth for the Finder-drop UX
// shared by FoldersMatrixView and FilesFlatView. Folders dropped on
// either surface get added straight through; files raise a confirmation
// dialog asking whether to add the whole containing folder or only
    // that file (with the containing folder default-denied and the selected
    // file explicitly allowed).

import SwiftUI

extension View {
    /// Attach a Manifold source-drop target to the view. Owns the
    /// drop-target border, the queue of pending file drops, and the
    /// confirmation dialog. Folders dispatch into `store.addSourceFromURL`
    /// immediately; files queue and await the user's choice.
    func manifoldFileDropTarget(store: ManifoldStore) -> some View {
        modifier(FileDropTargetModifier(store: store))
    }
}

private struct FileDropTargetModifier: ViewModifier {
    let store: ManifoldStore

    @State private var pendingFileDrops: [URL] = []
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { items, _ in
                handleDroppedURLs(items)
                return !items.isEmpty
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            ManifoldPalette.selection,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                        .padding(2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .confirmationDialog(
                title,
                isPresented: Binding(
                    get: { !pendingFileDrops.isEmpty },
                    set: { if !$0 { pendingFileDrops = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button("Add the whole folder") {
                    let drops = pendingFileDrops
                    pendingFileDrops = []
                    Task {
                        for url in drops { await store.addSourceFromURL(url) }
                    }
                }
                Button("Add only \(pendingFileDrops.count == 1 ? "this file" : "these files")") {
                    let drops = pendingFileDrops
                    pendingFileDrops = []
                    Task {
                        for url in drops { await store.addSourceForSingleFile(url) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingFileDrops = []
                }
            } message: {
                Text(message)
            }
    }

    private var title: String {
        pendingFileDrops.count == 1
            ? "Add \(pendingFileDrops[0].lastPathComponent)?"
            : "Add \(pendingFileDrops.count) files?"
    }

    private var message: String {
        pendingFileDrops.count == 1
            ? "Add the whole folder so every file in it is visible, or add only this file so new and existing siblings stay hidden."
            : "Add the containing folders, or add only the dropped files so new and existing siblings stay hidden."
    }

    private func handleDroppedURLs(_ urls: [URL]) {
        var folders: [URL] = []
        var files: [URL] = []
        for url in urls.map(\.standardizedFileURL) {
            if store.dropTargetIsFile(url) { files.append(url) } else { folders.append(url) }
        }
        if !folders.isEmpty {
            Task {
                for url in folders { await store.addSourceFromURL(url) }
            }
        }
        if !files.isEmpty {
            pendingFileDrops.append(contentsOf: files)
        }
    }
}
