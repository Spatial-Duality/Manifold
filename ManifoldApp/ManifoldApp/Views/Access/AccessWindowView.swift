// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AccessWindowView — the "who can see what" surface.
//
// After the Stage-11 redesign: one canonical Scope view (three columns)
// with two secondary view modes — Files (flat listing) and History
// (past grants). The old "Folders" matrix and "Session" sub-tab are
// gone; Session state is surfaced on Scope as an overlay when live
// (temporal axis, not a sibling destination).
//
// Mode switching uses the native segmented picker per
// APPLE-DESIGN-EXCELLENCE-GUIDE §3 — no custom capsule bars.

import SwiftUI
import ManifoldKit

struct AccessWindowView: View {
    @Environment(ManifoldStore.self) private var store

    enum Mode: String, Hashable, CaseIterable, Identifiable {
        case scope, files, history

        var id: String { rawValue }

        var label: String {
            switch self {
            case .scope:   return "Scope"
            case .files:   return "Files"
            case .history: return "History"
            }
        }
    }

    @State private var mode: Mode = .scope

    var body: some View {
        VStack(spacing: 0) {
            if !store.sources.isEmpty {
                ModeBar(mode: $mode)
                Divider()
            }

            if store.sources.isEmpty {
                EmptyFoldersView()
            } else {
                switch mode {
                case .scope:   ScopeColumnsView()
                case .files:   FilesFlatView()
                case .history: AccessHistoryView()
                }
            }
        }
        .task { await store.refreshAll(force: false) }
    }
}

/// Native segmented picker, centered, with light vertical padding.
/// Replaces the previous custom capsule tab bar.
private struct ModeBar: View {
    @Binding var mode: AccessWindowView.Mode

    var body: some View {
        HStack {
            Picker("View", selection: $mode) {
                ForEach(AccessWindowView.Mode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
    }
}
