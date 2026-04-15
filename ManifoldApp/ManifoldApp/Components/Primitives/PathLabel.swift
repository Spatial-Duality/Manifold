// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// PathLabel — mono-styled shortened path + optional Reveal-in-Finder
// action. Extracted from AdvancedSettingsPane so MailSettingsPane,
// StorageSettingsPane, and any future diagnostic surface can reuse it.

import SwiftUI

struct PathLabel: View {
    let path: String
    var revealsInFinder: Bool = true

    init(_ path: String, revealsInFinder: Bool = true) {
        self.path = path
        self.revealsInFinder = revealsInFinder
    }

    var body: some View {
        HStack(spacing: Spacing.s1) {
            Text(path.shortenedPath)
                .font(ManifoldType.mono)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if revealsInFinder {
                Button {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal \(path.shortenedPath) in Finder")
            }
        }
    }
}

#Preview("Path labels") {
    Form {
        LabeledContent("Database") {
            PathLabel("/Users/test/Library/Application Support/Manifold/store")
        }
        LabeledContent("MCP binary") {
            PathLabel("/Users/test/Library/Application Support/Manifold/bin/manifold-mcp")
        }
        LabeledContent("Static") {
            PathLabel("/etc/launchd.plist", revealsInFinder: false)
        }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 200)
}
