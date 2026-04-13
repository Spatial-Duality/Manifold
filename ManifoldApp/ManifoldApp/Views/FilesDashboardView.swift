// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Files Dashboard — shown when "Dashboard" is selected in the Files sidebar.
/// Mirrors the prototype's dashboard pattern: summary, per-agent stats, sources panel,
/// file types panel, recent modifications.
struct FilesDashboardView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Files Dashboard")
                        .font(Typ.sectionTitle)
                    Text(summaryLine)
                        .font(Typ.body)
                        .foregroundStyle(.secondary)
                }

                // Per-agent stats cards
                HStack(spacing: 12) {
                    agentStatCard(
                        name: "Claude",
                        color: .claudeBlue,
                        sharedCount: claudeSharedCount,
                        totalCount: activeSources.count
                    )
                    agentStatCard(
                        name: "Codex",
                        color: .codexPurple,
                        sharedCount: codexSharedCount,
                        totalCount: activeSources.count
                    )
                }

                // Sources panel
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sources")
                        .font(Typ.heading)

                    ForEach(activeSources) { source in
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(sourceIsShared(source) ? Color.statusActive : Color.gray)
                                    .frame(width: 6, height: 6)
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(source.displayName)
                                    .font(Typ.body)
                            }
                            Spacer()
                            Text(source.originalRootPath.shortenedPath)
                                .font(Typ.mono)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator, lineWidth: 0.5)
                }

                // Footer callout
                if notSharedCount > 0 {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("^[\(notSharedCount) source](inflect: true) not shared with any agent")
                            .font(Typ.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 740, alignment: .leading)
        }
        .navigationTitle("Files")
    }

    // MARK: - Data

    private var activeSources: [SourceRecord] {
        store.sources.filter { !$0.isRemoved }
    }

    private var claudeSharedCount: Int {
        store.policy.claudePolicy?.allowedSourceIDs.count ?? 0
    }

    private var codexSharedCount: Int {
        store.policy.codexPolicy?.allowedSourceIDs.count ?? 0
    }

    private var notSharedCount: Int {
        let claudeIDs = store.policy.claudePolicy?.allowedSourceIDs ?? []
        let codexIDs = store.policy.codexPolicy?.allowedSourceIDs ?? []
        let allShared = claudeIDs.union(codexIDs)
        return activeSources.filter { !allShared.contains($0.sourceID) }.count
    }

    private var summaryLine: String {
        let shared = activeSources.filter { sourceIsShared($0) }.count
        return "\(activeSources.count) sources \u{00B7} \(shared) shared with agents"
    }

    private func sourceIsShared(_ source: SourceRecord) -> Bool {
        let claudeIDs = store.policy.claudePolicy?.allowedSourceIDs ?? []
        let codexIDs = store.policy.codexPolicy?.allowedSourceIDs ?? []
        return claudeIDs.contains(source.sourceID) || codexIDs.contains(source.sourceID)
    }

    // MARK: - Agent Stat Card

    private func agentStatCard(name: String, color: Color, sharedCount: Int, totalCount: Int) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                Text(name)
                    .font(Typ.heading)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(sharedCount)")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(color)
                        Text("shared")
                            .font(Typ.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(totalCount - sharedCount)")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text("not shared")
                            .font(Typ.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Progress bar
                    GeometryReader { geo in
                        let fraction = totalCount > 0 ? Double(sharedCount) / Double(totalCount) : 0
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.quaternary)
                            Capsule()
                                .fill(color)
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(height: 6)
                    .frame(maxWidth: 80)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}
