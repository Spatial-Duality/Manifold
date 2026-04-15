// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AccessWindowView — the "who can see what" surface.
//
// Per design/html/access.html: 4-tab router — Folders / Files / Session
// / History — plus an empty state when no sources exist. Each sub-view
// is a dense matrix or list with its own inspector on the right.

import SwiftUI
import ManifoldKit

struct AccessWindowView: View {
    @Environment(ManifoldStore.self) private var store

    enum Tab: String, Hashable, CaseIterable {
        case folders, files, session, history

        var label: String {
            switch self {
            case .folders: return "Folders"
            case .files:   return "Files"
            case .session: return "Session"
            case .history: return "History"
            }
        }

        var systemImage: String {
            switch self {
            case .folders: return "folder.fill"
            case .files:   return "doc.on.doc"
            case .session: return "play.fill"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    @State private var tab: Tab = .folders

    var body: some View {
        VStack(spacing: 0) {
            AccessTabBar(selection: $tab, hasSession: store.activeSession != nil)
            Divider()

            if store.sources.isEmpty {
                EmptyFoldersView()
            } else {
                switch tab {
                case .folders: FoldersMatrixView()
                case .files:   FilesFlatView()
                case .session: SessionDiffView()
                case .history: AccessHistoryView()
                }
            }
        }
        .task { await store.refreshAll(force: false) }
    }
}

private struct AccessTabBar: View {
    @Binding var selection: AccessWindowView.Tab
    let hasSession: Bool

    var body: some View {
        HStack(spacing: Spacing.s1) {
            ForEach(AccessWindowView.Tab.allCases, id: \.self) { tab in
                let enabled = (tab != .session || hasSession)
                Button {
                    if enabled { selection = tab }
                } label: {
                    Label(tab.label, systemImage: tab.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(ManifoldType.captionMedium)
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == tab
                                      ? ManifoldPalette.claudeSoft
                                      : ManifoldPalette.surface3)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    selection == tab
                                        ? ManifoldPalette.claude.opacity(0.35)
                                        : ManifoldPalette.border,
                                    lineWidth: 0.6
                                )
                        )
                        .foregroundStyle(selection == tab
                                         ? ManifoldPalette.claude
                                         : ManifoldPalette.text2)
                        .opacity(enabled ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
    }
}
