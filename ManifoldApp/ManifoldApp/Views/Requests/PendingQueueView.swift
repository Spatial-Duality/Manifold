// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RequestsQueueView — vertical stack of approval request cards, newest at top.
// Each card is self-contained: agent avatar, headline, target, context,
// and the CommitLadder.

import SwiftUI
import ManifoldKit

struct RequestsQueueView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s3) {
                ForEach(store.pendingRequests) { request in
                    ApprovalRequestCard(request: request, store: store)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .push(from: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .padding(Spacing.s4)
        }
        .animation(ManifoldMotion.state, value: store.pendingRequests)
        .accessibilityIdentifier("requests.queue")
    }
}

struct ApprovalRequestCard: View {
    let request: ApprovalRequest
    let store: ManifoldStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s2) {
                GradientAvatar(agent: request.agent, size: .medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.headline)
                        .font(ManifoldType.bodyMedium)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(request.createdAt.formatted(.relative(presentation: .named)))
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                operationPill
            }

            Label {
                Text(request.target)
                    .font(ManifoldType.mono)
                    .padding(.horizontal, Spacing.s1)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
            }

            Text(request.context)
                .font(ManifoldType.caption)
                .foregroundStyle(.tertiary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)

            CommitLadder(
                agent: request.agent,
                showsSessionScope: request.supportsSessionScope && store.activeSession != nil,
                onNotThisTime: { Task { await store.answer(request, with: .notThisTime) } },
                onOnce:        { Task { await store.answer(request, with: .once) } },
                onSession:     { Task {
                    guard let sid = store.activeSession?.id else { return }
                    await store.answer(request, with: .forSession(sessionID: sid))
                } },
                onDefault:     { Task { await store.answer(request, with: .addToDefault) } }
            )
        }
        .padding(Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
        .accessibilityIdentifier("requests.card.\(request.id)")
    }

    private var operationPill: some View {
        Pill(text: operationLabel, variant: operationVariant)
    }

    private var operationLabel: String {
        switch request.operation {
        case .readFile, .readFolder: return "read"
        case .write:                 return "write"
        case .searchContent:         return "search"
        case .listDirectory:         return "list"
        case .mailboxRead:           return "mail"
        }
    }

    private var operationVariant: Pill.Variant {
        switch request.operation {
        case .write:        return .attention
        case .mailboxRead:  return .agent(.codex)
        default:            return .agent(request.agent)
        }
    }
}
