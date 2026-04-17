// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// QuickLookPreview — inline QLPreviewView for embedded inspector previews.
//
// Distinct from SwiftUI's `.quickLookPreview(_:)` modifier (which presents
// the system floating Quick Look panel like pressing Space in Finder).
// This wraps AppKit's QLPreviewView so the inspector can render the
// selected file inline alongside metadata and access chips.

import SwiftUI
import AppKit
import Quartz

struct QuickLookPreview: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.previewItem = url as (QLPreviewItem)?
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? URL) != url {
            nsView.previewItem = url as (QLPreviewItem)?
        }
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        nsView.close()
    }
}
