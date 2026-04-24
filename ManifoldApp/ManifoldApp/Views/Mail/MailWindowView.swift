// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MailView — the mail surface.
//
// Per Stage 8: this is Active-Backup, not a Mail client. No reading pane,
// no compose, no reply. The primary surface is now a dense review browser:
// account/mailbox rail, sortable message table, and a narrow metadata
// inspector for atomic allow / hide decisions.

import SwiftUI
import ManifoldKit

struct MailView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var hasLoadedMailAccounts = false

    enum MailSection: String, Hashable, CaseIterable {
        case review
        case session
        case history

        var label: String {
            switch self {
            case .review:    return "Review"
            case .session:   return "Session"
            case .history:   return "History"
            }
        }

        var systemImage: String {
            switch self {
            case .review:    return "text.bubble"
            case .session:   return "play.fill"
            case .history:   return "clock.arrow.circlepath"
            }
        }
    }

    @State private var selectedSection: MailSection = .review

    var body: some View {
        VStack(spacing: 0) {
            SegmentedTabBar(
                selection: $selectedSection,
                items: MailSection.allCases.map { item in
                    SegmentedTabItem(
                        value: item,
                        title: item.label,
                        systemImage: item.systemImage,
                        isEnabled: item != .session || store.activeSession != nil,
                        accessibilityIdentifier: "mail.tab.\(item.rawValue)"
                    )
                }
            )
            Divider()

            if !hasLoadedMailAccounts {
                ProgressView("Loading mail backup…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ManifoldPalette.surface)
            } else if store.mailAccounts.accounts.isEmpty {
                EmptyMailView()
            } else {
                switch selectedSection {
                case .review:
                    MailReviewView()
                case .session:   MailSessionView()
                case .history:   MailHistoryView()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .environment(store.mailAccounts)
        .environment(store.mailReview)
        .task {
            await store.mailAccounts.loadAccounts()
            await store.mailReview.prepare(force: true)
            hasLoadedMailAccounts = true
        }
        .task(id: selectedSection) {
            guard hasLoadedMailAccounts, selectedSection == .review else { return }
            await store.mailReview.prepare(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldFocusCurrentSearch)) { _ in
            guard selectedSection != .review else { return }
            selectedSection = .review
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .manifoldFocusCurrentSearch, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldCycleCurrentSubtab)) { notification in
            guard let delta = notification.object as? Int else { return }
            cycleTab(by: delta)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.surface.mail")
    }

    private func cycleTab(by delta: Int) {
        let enabledSections = MailSection.allCases.filter { $0 != .session || store.activeSession != nil }
        guard let currentIndex = enabledSections.firstIndex(of: selectedSection), !enabledSections.isEmpty else { return }
        let nextIndex = (currentIndex + delta + enabledSections.count) % enabledSections.count
        withAnimation(ManifoldMotion.micro) {
            selectedSection = enabledSections[nextIndex]
        }
    }
}
