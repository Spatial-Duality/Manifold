// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LedgerView — the single Manifold window.
//
// Per Stage 2, Manifold is a daemon with two visible surfaces: the menu
// bar panel (primary) and this Ledger window (secondary). The Ledger is
// NavigationSplitView with 4 live evidence-oriented destinations.
//
// Every destination renders live runtime state or an honest empty state.

import SwiftUI
import ManifoldKit

/// Sidebar destinations — read as "the kind of evidence you want to see",
/// not "the tabs of an app" (Principle 10, Stage 2).
enum LedgerDestination: String, Hashable, CaseIterable, Identifiable {
    case activity
    case access
    case mail
    case requests
    case rules
    case provenance
    case agentOS

    var id: String { rawValue }

    var keyboardIndex: Int {
        switch self {
        case .activity: return 1
        case .access: return 2
        case .mail: return 3
        case .requests: return 4
        case .rules: return 5
        case .provenance: return 6
        case .agentOS: return 7
        }
    }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .access:   return "Access"
        case .mail:     return "Mail"
        case .requests: return "Requests"
        case .rules:    return "Rules"
        case .provenance: return "Provenance"
        case .agentOS: return "Agent OS"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return "list.bullet.rectangle"
        case .access:   return "folder.badge.gearshape"
        case .mail:     return "envelope"
        case .requests: return "hand.raised"
        case .rules:    return "checklist"
        case .provenance: return "checkmark.seal"
        case .agentOS: return "cpu"
        }
    }

    var emptyTitle: String {
        switch self {
        case .activity: return "No activity yet"
        case .access:   return "Nothing shared yet"
        case .mail:     return "No mailboxes connected"
        case .requests: return "Nothing is waiting on you"
        case .rules:    return "No rules configured"
        case .provenance: return "No ledger entries yet"
        case .agentOS: return "No agent runtime artifacts yet"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .activity: return "As agents read files or write changes inside a session, an evidence ledger of every operation will appear here."
        case .access:   return "Nothing is shared until you share it. Add a folder to let an agent read from it inside a session."
        case .mail:     return "Connect a mailbox to share mail with an agent. Subjects and senders are visible by default; message bodies require an explicit grant."
        case .requests: return "When an agent asks for standing write access it lands here. Requests are answered in a ladder — not this time, once, or add to default."
        case .rules:    return "Rules control what agents can read, write, or redact. Seeded rules block secrets out of the box; add custom rules for anything else."
        case .provenance: return "Manifold records a hash-chained ledger for access decisions, exposures, memory changes, and tool cost metrics."
        case .agentOS: return "Skills, capability handles, graph nodes, ManifoldExec runs, and claim checks appear here when agents use late-phase primitives."
        }
    }
}

struct LedgerView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var destination: LedgerDestination = .activity
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LedgerSidebar(selection: $destination)
        } detail: {
            // Title ownership: the DETAIL column owns the window title on
            // macOS `NavigationSplitView`. Setting `.navigationTitle` on
            // the sidebar as well causes the sidebar `List` to start
            // drawing from Y=0 (the first rows land behind the traffic
            // lights). So: the sidebar sets no title, the detail sets a
            // single canonical title — `destination.title` — and that's
            // it. No `.navigationSubtitle` (two-level titles on a
            // destination-switching split view add nothing but another
            // chrome collision surface).
            //
            // `.frame(minWidth:)` guards the detail pane from being
            // squeezed to zero width when the user drags the sidebar
            // divider aggressively; without it a very narrow detail
            // column caused the ambient banner and toolbar to overlap.
            content
                .frame(minWidth: 640, minHeight: 480)
                .navigationTitle(destination.title)
                .toolbar { LedgerToolbar(destination: destination) }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            columnVisibility = .all
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowActivityLedger)) { _ in
            destination = .activity
            columnVisibility = .all
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowLedgerDestination)) { notification in
            guard let rawValue = notification.object as? String,
                  let requestedDestination = LedgerDestination(rawValue: rawValue) else {
                return
            }
            destination = requestedDestination
            columnVisibility = .all
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .activity:
            ActivityView()
        case .access:
            AccessView()
        case .mail:
            MailView()
        case .requests:
            RequestsView()
        case .rules:
            RulesView()
        case .provenance:
            ProvenanceLedgerView()
        case .agentOS:
            AgentOSView()
        }
    }
}

private struct AgentOSView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                header
                AgentOSControlMap()
                summary

                if isEmpty {
                    EmptyStateIllustration(
                        systemImage: "cpu",
                        title: "No agent runtime artifacts yet",
                        subtitle: "ManifoldExec runs, skills, capability handles, graph nodes, and claim checks appear here after agents use those tools."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s7)
                    .accessibilityIdentifier("ledger.agentOS.empty")
                } else {
                    skillSection
                    execSection
                    capabilitySection
                    graphSection
                    verificationSection
                }
            }
            .padding(Spacing.s5)
        }
        .task { await store.personalDataOS.loadAgentOS() }
        .accessibilityIdentifier("ledger.surface.agentOS")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Agent OS Controls", systemImage: "cpu")
                    .font(ManifoldType.title)
                    .accessibilityIdentifier("ledger.agentOS")
                Text("Advanced MCP primitives that manage reusable skills, scoped data handles, deterministic plans, graph context, and claim proof.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task { await store.personalDataOS.loadAgentOS() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("ledger.agentOS.refresh")
        }
    }

    private var summary: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.s3)],
            alignment: .leading,
            spacing: Spacing.s3
        ) {
            LedgerMetricTile(title: "Skills", value: "\(store.personalDataOS.skills.count)", systemImage: "wand.and.sparkles", variant: .preview)
            LedgerMetricTile(title: "Exec runs", value: "\(store.personalDataOS.execRuns.count)", systemImage: "play.rectangle", variant: .scope)
            LedgerMetricTile(title: "Blocked", value: "\(store.personalDataOS.blockedExecRunCount)", systemImage: "hand.raised", variant: store.personalDataOS.blockedExecRunCount > 0 ? .attention : .neutral)
            LedgerMetricTile(title: "Graph", value: "\(store.personalDataOS.graphNodes.count)", systemImage: "point.3.connected.trianglepath.dotted", variant: .defaultScope)
            LedgerMetricTile(title: "Verified", value: "\(store.personalDataOS.supportedFindingCount)", systemImage: "checkmark.seal", variant: .defaultScope)
        }
        .accessibilityIdentifier("ledger.agentOS.summary")
    }

    @ViewBuilder
    private var skillSection: some View {
        if !store.personalDataOS.skills.isEmpty {
            AgentOSSection(title: "Executable Skills", systemImage: "wand.and.sparkles", identifier: "ledger.agentOS.skills") {
                ForEach(store.personalDataOS.skills) { skill in
                    SkillRuntimeRow(skill: skill)
                        .accessibilityIdentifier("ledger.agentOS.skill.\(skill.skillID)")
                }
            }
        }
    }

    @ViewBuilder
    private var execSection: some View {
        if !store.personalDataOS.execRuns.isEmpty {
            AgentOSSection(title: "ManifoldExec Runs", systemImage: "play.rectangle", identifier: "ledger.agentOS.execRuns") {
                ForEach(store.personalDataOS.execRuns) { run in
                    ExecRunRuntimeRow(run: run)
                        .accessibilityIdentifier("ledger.agentOS.exec.\(run.runID)")
                }
            }
        }
    }

    @ViewBuilder
    private var capabilitySection: some View {
        if !store.personalDataOS.capabilityHandles.isEmpty {
            AgentOSSection(title: "Capability Handles", systemImage: "number", identifier: "ledger.agentOS.handles") {
                ForEach(store.personalDataOS.capabilityHandles) { handle in
                    ValueHandleRuntimeRow(handle: handle)
                        .accessibilityIdentifier("ledger.agentOS.handle.\(handle.handleID)")
                }
            }
        }
    }

    @ViewBuilder
    private var graphSection: some View {
        if !store.personalDataOS.graphNodes.isEmpty {
            AgentOSSection(title: "Scoped Knowledge Graph", systemImage: "point.3.connected.trianglepath.dotted", identifier: "ledger.agentOS.graph") {
                ForEach(store.personalDataOS.graphNodes) { node in
                    GraphNodeRuntimeRow(node: node)
                        .accessibilityIdentifier("ledger.agentOS.node.\(node.nodeID)")
                }
            }
        }
    }

    @ViewBuilder
    private var verificationSection: some View {
        if !store.personalDataOS.fabricationFindings.isEmpty {
            AgentOSSection(title: "Claim Verification", systemImage: "exclamationmark.bubble", identifier: "ledger.agentOS.findings") {
                ForEach(store.personalDataOS.fabricationFindings) { finding in
                    FabricationFindingRuntimeRow(finding: finding)
                        .accessibilityIdentifier("ledger.agentOS.finding.\(finding.findingID)")
                }
            }
        }
    }

    private var isEmpty: Bool {
        store.personalDataOS.skills.isEmpty
            && store.personalDataOS.execRuns.isEmpty
            && store.personalDataOS.capabilityHandles.isEmpty
            && store.personalDataOS.graphNodes.isEmpty
            && store.personalDataOS.fabricationFindings.isEmpty
            && !store.personalDataOS.isLoadingAgentOS
    }
}

private struct AgentOSControlMap: View {
    private let controls: [(String, String, String, Pill.Variant)] = [
        ("lock.doc", "Deterministic Plans", "No shell, network, raw filesystem, or hidden state changes.", .scope),
        ("number", "Capability Handles", "Sensitive values carry origin, trust level, and allowed sinks.", .attention),
        ("point.3.connected.trianglepath.dotted", "Scoped Graph", "Searchable context stays tied to available source lineage.", .defaultScope),
        ("checkmark.seal", "Claim Proof", "Agent claims are checked against recorded exposure evidence.", .preview),
    ]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.s3)],
            alignment: .leading,
            spacing: Spacing.s3
        ) {
            ForEach(controls, id: \.1) { control in
                HStack(alignment: .top, spacing: Spacing.s2) {
                    Image(systemName: control.0)
                        .foregroundStyle(control.3.color)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(control.1)
                            .font(ManifoldType.captionMedium)
                        Text(control.2)
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                        .fill(ManifoldPalette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                        .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
                )
            }
        }
        .accessibilityIdentifier("ledger.agentOS.controlMap")
    }
}

private struct AgentOSSection<Content: View>: View {
    let title: String
    let systemImage: String
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label(title, systemImage: systemImage)
                .font(ManifoldType.bodyMedium)
            LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                content
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

private struct SkillRuntimeRow: View {
    let skill: SkillRecord

    var body: some View {
        runtimeRow(icon: "wand.and.sparkles", variant: .preview) {
            HStack(spacing: Spacing.s2) {
                Text(skill.name)
                    .font(ManifoldType.bodyMedium)
                    .lineLimit(1)
                Pill(text: "json-plan", variant: .scope)
                Spacer()
                Text(relativeDate(skill.updatedAt))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            Text("manifest \(shortHash(skill.manifestHash))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(skill.manifestJSON)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ManifoldPalette.text2)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct ExecRunRuntimeRow: View {
    let run: ExecRunRecord

    var body: some View {
        runtimeRow(icon: icon, variant: variant) {
            HStack(spacing: Spacing.s2) {
                Text(run.reason)
                    .font(ManifoldType.bodyMedium)
                    .lineLimit(1)
                Pill(text: run.status.replacingOccurrences(of: "_", with: " "), variant: variant)
                Spacer()
                Text(relativeDate(run.createdAt))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            if let alternative = run.suggestedAlternative {
                Text(alternative)
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.text2)
                    .lineLimit(2)
            }
            if let output = run.outputPreview {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    private var icon: String {
        switch ExecRunStatus(rawValue: run.status) {
        case .completed: return "checkmark.circle"
        case .needsApproval: return "hand.raised"
        case .refused: return "nosign"
        case .failed, .none: return "exclamationmark.triangle"
        }
    }

    private var variant: Pill.Variant {
        switch ExecRunStatus(rawValue: run.status) {
        case .completed: return .defaultScope
        case .needsApproval: return .attention
        case .refused, .failed, .none: return .neutral
        }
    }
}

private struct ValueHandleRuntimeRow: View {
    let handle: ValueHandle

    var body: some View {
        runtimeRow(icon: "number", variant: handleVariant) {
            HStack(spacing: Spacing.s2) {
                Text(handle.origin)
                    .font(ManifoldType.bodyMedium)
                    .lineLimit(1)
                Pill(text: handle.sensitivity, variant: handleVariant)
                Pill(text: handle.trustLevel, variant: handle.trustLevel == "untrusted" ? .attention : .neutral)
                Spacer()
                Text(relativeDate(handle.createdAt))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.s2) {
                Pill(text: "grant \(handle.grantID ?? "none")", variant: .neutral)
                ForEach(handle.allowedSinks.prefix(3), id: \.self) { sink in
                    Pill(text: sink, variant: .scope)
                }
                if handle.allowedSinks.count > 3 {
                    Pill(text: "+\(handle.allowedSinks.count - 3)", variant: .neutral)
                }
            }
        }
    }

    private var handleVariant: Pill.Variant {
        ["secret", "high", "restricted", "sensitive", "private"].contains(handle.sensitivity.lowercased())
            ? .attention
            : .defaultScope
    }
}

private struct GraphNodeRuntimeRow: View {
    let node: KnowledgeGraphNode

    var body: some View {
        runtimeRow(icon: "point.3.connected.trianglepath.dotted", variant: .defaultScope) {
            HStack(spacing: Spacing.s2) {
                Text(node.label)
                    .font(ManifoldType.bodyMedium)
                    .lineLimit(1)
                Pill(text: node.kind, variant: .scope)
                Spacer()
                Text(relativeDate(node.updatedAt))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            if !node.lineage.isEmpty {
                Text(node.lineage.map { "\($0.kind):\($0.id)" }.joined(separator: " · "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct FabricationFindingRuntimeRow: View {
    let finding: FabricationFinding

    var body: some View {
        runtimeRow(icon: finding.status == "supported" ? "checkmark.seal" : "exclamationmark.bubble", variant: variant) {
            HStack(spacing: Spacing.s2) {
                Text(finding.claimText)
                    .font(ManifoldType.bodyMedium)
                    .lineLimit(1)
                Pill(text: finding.status, variant: variant)
                Spacer()
                Text(relativeDate(finding.createdAt))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            Text(finding.evidenceJSON)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var variant: Pill.Variant {
        finding.status == "supported" ? .defaultScope : .attention
    }
}

@ViewBuilder
private func runtimeRow<Content: View>(
    icon: String,
    variant: Pill.Variant,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(alignment: .top, spacing: Spacing.s3) {
        Image(systemName: icon)
            .frame(width: 28, height: 28)
            .foregroundStyle(variant.color)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(variant.color.opacity(0.12))
            )
        VStack(alignment: .leading, spacing: Spacing.s2) {
            content()
        }
    }
    .padding(Spacing.s3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
            .fill(ManifoldPalette.surface)
    )
    .overlay(
        RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
            .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
    )
}

private func shortHash(_ hash: String) -> String {
    guard hash.count > 14 else { return hash }
    return "\(hash.prefix(10))..."
}

private func relativeDate(_ timestamp: Double) -> String {
    RelativeDateTimeFormatter().localizedString(
        for: Date(timeIntervalSince1970: timestamp),
        relativeTo: Date()
    )
}

private struct ProvenanceLedgerView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var entryFilter: ProvenanceEntryFilter = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                header
                verificationBanner
                proofMap
                toolCostSummary
                entryFilterPicker
                ledgerEntries
            }
            .padding(Spacing.s5)
        }
        .task { await store.personalDataOS.loadLedger() }
        .accessibilityIdentifier("ledger.surface.provenance")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Provenance Ledger", systemImage: "checkmark.seal")
                    .font(ManifoldType.title)
                    .accessibilityIdentifier("ledger.provenance")
                Text("Proof for what was allowed, blocked, redacted, remembered, verified, and handed to agents.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task { await store.personalDataOS.loadLedger() }
            } label: {
                Label("Verify", systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("ledger.provenance.verify")
        }
    }

    private var proofMap: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: Spacing.s3)],
            alignment: .leading,
            spacing: Spacing.s3
        ) {
            ProvenanceProofTile(title: "Decisions", value: "\(count(.decisions))", detail: "Allowed, denied, warned", systemImage: "hand.raised", variant: .attention)
            ProvenanceProofTile(title: "Exposures", value: "\(count(.exposures))", detail: "Content hashes and bytes", systemImage: "eye", variant: .defaultScope)
            ProvenanceProofTile(title: "Memory", value: "\(count(.memory))", detail: "Saved or forgotten context", systemImage: "brain", variant: .preview)
            ProvenanceProofTile(title: "Agent OS", value: "\(count(.agentOS))", detail: "Skills, handles, exec, graph", systemImage: "cpu", variant: .scope)
        }
        .accessibilityIdentifier("ledger.provenance.proofMap")
    }

    @ViewBuilder
    private var verificationBanner: some View {
        if let result = store.personalDataOS.ledgerVerification {
            HStack(spacing: Spacing.s3) {
                Image(systemName: result.verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(result.verified ? ManifoldPalette.active : ManifoldPalette.attention)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.verified ? "Chain verified" : "Chain needs review")
                        .font(ManifoldType.bodyMedium)
                    Text("\(result.checkedEntries) entries checked · \(result.message)")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if let brokenID = result.firstBrokenEntryID {
                    Text(brokenID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(Spacing.s4)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(ManifoldPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder((result.verified ? ManifoldPalette.active : ManifoldPalette.attention).opacity(0.35), lineWidth: 0.8)
            )
            .accessibilityIdentifier("ledger.provenance.verified")
        }
    }

    @ViewBuilder
    private var toolCostSummary: some View {
        if let report = store.personalDataOS.toolCostReport {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Label("Tool Costs", systemImage: "gauge.with.dots.needle.33percent")
                    .font(ManifoldType.bodyMedium)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.s3)],
                    alignment: .leading,
                    spacing: Spacing.s3
                ) {
                    LedgerMetricTile(title: "Calls", value: "\(report.totalCalls)", systemImage: "terminal", variant: .scope)
                    LedgerMetricTile(title: "Output", value: ByteCountFormatter.string(fromByteCount: Int64(report.totalOutputBytes), countStyle: .file), systemImage: "doc.text", variant: .neutral)
                    LedgerMetricTile(title: "Avg latency", value: "\(Int(report.averageDurationMS.rounded())) ms", systemImage: "timer", variant: .defaultScope)
                    LedgerMetricTile(title: "Tools", value: "\(report.callsByTool.count)", systemImage: "wrench.and.screwdriver", variant: .preview)
                }
            }
            .accessibilityIdentifier("ledger.provenance.cost")
        }
    }

    private var entryFilterPicker: some View {
        Picker("Ledger filter", selection: $entryFilter) {
            ForEach(ProvenanceEntryFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("ledger.provenance.filter")
    }

    @ViewBuilder
    private var ledgerEntries: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Entries", systemImage: "list.bullet.rectangle")
                .font(ManifoldType.bodyMedium)

            if store.personalDataOS.isLoadingLedger {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if store.personalDataOS.ledgerEntries.isEmpty {
                EmptyStateIllustration(
                    systemImage: "checkmark.seal",
                    title: "No ledger entries yet",
                    subtitle: "Access decisions, exposures, tool metrics, memory updates, and skill runs will appear here."
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s6)
                .accessibilityIdentifier("ledger.provenance.empty")
            } else if filteredEntries.isEmpty {
                EmptyStateIllustration(
                    systemImage: entryFilter.systemImage,
                    title: "No \(entryFilter.title.lowercased()) entries",
                    subtitle: "Choose another proof filter or wait for new governed activity."
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s6)
                .accessibilityIdentifier("ledger.provenance.filteredEmpty")
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                    ForEach(filteredEntries) { entry in
                        LedgerEntryRow(entry: entry)
                            .accessibilityIdentifier("ledger.provenance.row.\(entry.entryID)")
                    }
                }
            }
        }
    }

    private var filteredEntries: [LedgerEntry] {
        store.personalDataOS.ledgerEntries.filter(entryFilter.includes)
    }

    private func count(_ filter: ProvenanceEntryFilter) -> Int {
        store.personalDataOS.ledgerEntries.filter(filter.includes).count
    }
}

private enum ProvenanceEntryFilter: String, CaseIterable, Identifiable {
    case all
    case decisions
    case exposures
    case memory
    case agentOS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .decisions: return "Decisions"
        case .exposures: return "Exposures"
        case .memory: return "Memory"
        case .agentOS: return "Agent OS"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "list.bullet.rectangle"
        case .decisions: return "hand.raised"
        case .exposures: return "eye"
        case .memory: return "brain"
        case .agentOS: return "cpu"
        }
    }

    func includes(_ entry: LedgerEntry) -> Bool {
        guard self != .all else { return true }
        switch LedgerEntryType(rawValue: entry.entryType) {
        case .accessDecision:
            return self == .decisions
        case .exposure:
            return self == .exposures
        case .memoryItem, .memoryChange:
            return self == .memory
        case .valueHandle, .execRun, .skill, .graph, .fabricationFinding:
            return self == .agentOS
        case .toolMetric:
            return self == .agentOS || self == .decisions
        case .none:
            return false
        }
    }
}

private struct ProvenanceProofTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let variant: Pill.Variant

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(variant.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(ManifoldType.bodyMedium)
                    .monospacedDigit()
                Text(title)
                    .font(ManifoldType.captionMedium)
                Text(detail)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}

private struct LedgerMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let variant: Pill.Variant

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(variant.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(ManifoldType.bodyMedium)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}

private struct LedgerEntryRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Text("#\(entry.sequence)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(spacing: Spacing.s2) {
                    Pill(text: entryTypeLabel, variant: entryVariant, systemImage: entryIcon)
                    if let subject = subjectText {
                        Text(subject)
                            .font(ManifoldType.captionMedium)
                            .foregroundStyle(ManifoldPalette.text2)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(relativeDate)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: Spacing.s3) {
                    hashField("entry", entry.entryHash)
                    hashField("payload", entry.payloadHash)
                    if let previousHash = entry.previousHash {
                        hashField("prev", previousHash)
                    }
                }

                if let metadata = entry.metadataJSON, !metadata.isEmpty {
                    Text(metadata)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }

    private func hashField(_ label: String, _ hash: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(shortHash(hash))
                .textSelection(.enabled)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var subjectText: String? {
        guard let table = entry.subjectTable, let id = entry.subjectID else { return nil }
        return "\(table) · \(id)"
    }

    private var entryTypeLabel: String {
        entry.entryType.replacingOccurrences(of: "_", with: " ")
    }

    private var entryIcon: String {
        switch LedgerEntryType(rawValue: entry.entryType) {
        case .accessDecision: return "hand.raised"
        case .exposure: return "eye"
        case .toolMetric: return "gauge.with.dots.needle.33percent"
        case .memoryItem, .memoryChange: return "brain"
        case .valueHandle: return "number"
        case .execRun: return "play.rectangle"
        case .skill: return "wand.and.sparkles"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .fabricationFinding: return "exclamationmark.bubble"
        case .none: return "checkmark.seal"
        }
    }

    private var entryVariant: Pill.Variant {
        switch LedgerEntryType(rawValue: entry.entryType) {
        case .accessDecision, .exposure: return .defaultScope
        case .memoryItem, .memoryChange: return .preview
        case .toolMetric: return .scope
        case .fabricationFinding: return .attention
        case .valueHandle, .execRun, .skill, .graph, .none: return .neutral
        }
    }

    private var relativeDate: String {
        RelativeDateTimeFormatter().localizedString(
            for: Date(timeIntervalSince1970: entry.timestamp),
            relativeTo: Date()
        )
    }

    private func shortHash(_ hash: String) -> String {
        guard hash.count > 14 else { return hash }
        return "\(hash.prefix(10))..."
    }
}

#Preview("Ledger window — Provenance") {
    LedgerView()
        .environment(ManifoldStore(runtime: FixtureRuntimeClient(profile: .trackedWork), startServices: false))
        .frame(width: 1080, height: 720)
}

#Preview("Ledger window — Activity") {
    LedgerView()
        .environment(ManifoldStore())
        .frame(width: 1080, height: 720)
}
