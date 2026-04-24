// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RequestsView — the approval queue surface.
//
// Replaces the old modal approval sheet (Stage 2 §2, Principle 2).
// Requests accumulate here silently; the user answers when they return.
// "Not this time" is the focused default (Principle 3).
//
// Layout rules:
//   - The page always answers "what is waiting and how will it be handled?"
//   - Empty queue still shows policy, last exposure, and the decision ladder.
//   - Active queue keeps the cards primary, with a compact trust rail.

import SwiftUI
import ManifoldKit

struct RequestsView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            RequestsStatusHeader()
            Divider()
            HStack(spacing: 0) {
                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                RequestsInsightRail()
                    .frame(width: 320)
                    .background(.regularMaterial)
            }
        }
        .background(ManifoldPalette.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.surface.requests")
    }

    @ViewBuilder
    private var mainPane: some View {
        if store.pendingRequests.isEmpty {
            EmptyRequestsView()
        } else {
            RequestsQueueView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RequestsStatusHeader: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(ManifoldType.bodyMedium)
                Text(statusSubtitle)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Spacing.s4)
            if store.pendingRequests.isEmpty {
                Pill(text: "Clear", variant: .session)
            } else {
                Pill(text: "\(store.pendingRequests.count) waiting", variant: .attention)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(.thinMaterial)
    }

    private var statusTitle: String {
        store.pendingRequests.isEmpty ? "No requests need an answer" : "Requests waiting for your decision"
    }

    private var statusSubtitle: String {
        if !store.isRuntimeConnected {
            return "Runtime is offline, so new requests cannot be verified until Manifold reconnects."
        }
        if let exposure = store.dataControlSummary?.lastExposure {
            return "Last exposure: \(exposureSummary(exposure))."
        }
        return "Manifold defaults to not sharing more data until you choose a narrower or broader grant."
    }

    private func exposureSummary(_ exposure: DataControlSummary.Exposure) -> String {
        let agent = exposure.agent.map(AgentMeta.label) ?? "an agent"
        let target = exposure.resourcePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? exposure.action
        return "\(agent) \(exposure.action) \(target) \(relativeTime(exposure.timestamp))"
    }
}

private struct RequestsInsightRail: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                RequestsRailSection(title: "Decision ladder", systemImage: "arrow.up.arrow.down") {
                    ShortcutsCard()
                }

                RequestsRailSection(title: "Privacy filter", systemImage: "sparkles.rectangle.stack") {
                    PrivacyFilterRequestCard(status: store.governance.privacyRuntimeStatus)
                }

                RequestsRailSection(title: "Recent answers", systemImage: "clock.arrow.circlepath") {
                    RecentAnswersView()
                }

                RequestsRailSection(title: "Patterns", systemImage: "chart.bar.xaxis") {
                    PatternDetectionInspector()
                }
            }
            .padding(Spacing.s4)
        }
    }
}

private struct RequestsRailSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Label(title, systemImage: systemImage)
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            content
        }
    }
}

private struct PrivacyFilterRequestCard: View {
    let status: PrivacyRuntimeStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: status?.modelLoaded == true ? "checkmark.shield.fill" : "shield")
                    .foregroundStyle(status?.modelLoaded == true ? ManifoldPalette.active : ManifoldPalette.text3)
                Text(title)
                    .font(ManifoldType.captionMedium)
            }
            Text(message)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }

    private var title: String {
        guard let status else { return "Privacy status loading" }
        if status.effectiveBackend == .officialCLI {
            return status.modelLoaded ? "OpenAI privacy filter ready" : "OpenAI privacy filter paused"
        }
        return status.modelLoaded ? "\(status.effectiveBackend.displayName) ready" : "\(status.effectiveBackend.displayName) paused"
    }

    private var message: String {
        guard let status else {
            return "Sensitive-content decisions use the configured privacy backend before a request reaches Claude or Codex."
        }
        if status.modelLoaded {
            return "Requests with secrets, identity matches, or high severity findings can be denied, redacted, shared once, or saved as Rules."
        }
        return "Install or enable the privacy model before relying on category and severity decisions."
    }
}

private func relativeTime(_ isoString: String) -> String {
    guard let date = ISO8601DateFormatter.shared.date(from: isoString) else { return "" }
    return date.formatted(.relative(presentation: .named))
}
