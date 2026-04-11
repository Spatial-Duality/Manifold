import SwiftUI
import ManifoldKit

/// A computed domain aggregate for the domains table.
struct DomainAggregate: Identifiable, Hashable, Sendable {
    let domain: String
    let emailCount: Int
    let category: DomainCategory
    let isHiddenBySensitivity: Bool
    let hiddenReason: String?

    var id: String { domain }
}

enum DomainCategory: String, CaseIterable, Sendable {
    case work = "Work"
    case automated = "Automated"
    case personal = "Personal"
    case hidden = "Hidden by sensitivity"
}

/// Emails tab Domains overview — the primary access management surface for email.
/// Shows domains grouped by category with per-agent access checkboxes.
/// Sensitivity dropdown in toolbar, scoped to focused agent.
struct DomainsTableView: View {
    @Environment(ManifoldStore.self) var store
    @State private var searchText = ""
    @State private var domains: [DomainAggregate] = []
    @State private var showUndoToast = false
    @State private var undoDomain: String?
    @State private var undoTimerTask: Task<Void, Never>?
    @State private var broadenDomain: String?

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if domains.isEmpty {
                domainsEmptyState
            } else {
                domainsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NOTE: .searchable() removed — collides with EmailView's .searchable()
        //       when both views exist in the same window toolbar.
        .toolbar {
            ToolbarItem(placement: .automatic) {
                AgentFocusControl(focus: $store.agentFocus)
            }
            ToolbarItem(placement: .automatic) {
                TextField("Search domains", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            ToolbarItem(placement: .automatic) {
                HStack(spacing: Spacing.tight) {
                    Text("Sensitivity:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("Sensitivity", selection: sensitivityBinding) {
                        Text("Strict").tag(EmailSensitivityLevel.strict)
                        Text("Moderate").tag(EmailSensitivityLevel.moderate)
                        Text("Open").tag(EmailSensitivityLevel.open)
                    }
                    .frame(width: 110)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showUndoToast, let domain = undoDomain {
                undoToastView(domain: domain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: showUndoToast)
        .background {
            // Hidden ⌘Z handler for undo
            if showUndoToast {
                Button("") {
                    guard let domain = undoDomain else { return }
                    Task { await store.policy.addEmailDomain(domain, to: focusedAgent) }
                    showUndoToast = false
                    undoTimerTask?.cancel()
                }
                .keyboardShortcut("z", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
            }
        }
        .sheet(item: broadenBinding) { change in
            ReviewAccessSheet(pendingChange: change)
                .environment(store)
                .frame(minWidth: 560, minHeight: 500)
        }
        .task(id: domainsRefreshKey) {
            await store.policy.loadPolicies()
            await computeDomains()
        }
    }

    // MARK: - Domains List (grouped by category)

    @ViewBuilder
    private var domainsList: some View {
        let filtered = filteredDomains
        let grouped = Dictionary(grouping: filtered) { $0.category }

        List {
            ForEach(DomainCategory.allCases, id: \.self) { category in
                if let categoryDomains = grouped[category], !categoryDomains.isEmpty {
                    Section(category.rawValue) {
                        ForEach(categoryDomains) { domain in
                            domainRow(domain)
                        }
                    }
                }
            }

            // Footer
            Section {
                HStack {
                    Text("\(filtered.count) domains")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .font(.caption)
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Domain Row

    @ViewBuilder
    private func domainRow(_ domain: DomainAggregate) -> some View {
        HStack(spacing: Spacing.section) {
            // Domain name
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(domain.domain)")
                    .font(.body)
                    .foregroundStyle(domain.isHiddenBySensitivity ? .secondary : .primary)
                HStack(spacing: Spacing.tight) {
                    Text("\(domain.emailCount) emails")
                        .monospacedDigit()
                    if !domain.isHiddenBySensitivity {
                        Text("+ future")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Hidden reason
            if let reason = domain.hiddenReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }

            // Access checkbox — reads per-agent policy
            if domain.isHiddenBySensitivity {
                Toggle(isOn: .constant(false)) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(true)
                    .accessibilityLabel("@\(domain.domain) — hidden by sensitivity")
            } else {
                let isGranted = isDomainGranted(domain.domain)
                Toggle(isOn: Binding(
                    get: { isGranted },
                    set: { newValue in
                        if newValue {
                            broadenDomain = domain.domain
                        } else {
                            handleNarrow(domain: domain.domain)
                        }
                    }
                )) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("@\(domain.domain) access for \(focusedAgentName)")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Per-Agent Policy Helpers

    private var focusedAgent: TargetApp {
        store.agentFocus == .codex ? .codex : .cowork
    }

    private var focusedAgentName: String {
        focusedAgent == .codex ? "Codex" : "Claude"
    }

    private var focusedPolicy: AgentAccessPolicy? {
        store.policy.policy(for: focusedAgent)
    }

    private var currentSensitivity: EmailSensitivityLevel {
        focusedPolicy?.emailSensitivity ?? .moderate
    }

    private var domainsRefreshKey: String {
        let policy = focusedPolicy
        let allowedDomains = policy?.allowedEmailDomains.sorted().joined(separator: ",") ?? ""
        return [
            store.agentFocus.rawValue,
            policy?.updatedAt ?? "no-policy",
            currentSensitivity.rawValue,
            allowedDomains,
            "\(store.emailAccounts.totalMessageCount)",
        ].joined(separator: "|")
    }

    private func isDomainGranted(_ domain: String) -> Bool {
        focusedPolicy?.allowedEmailDomains.contains(domain.lowercased()) ?? false
    }

    /// Sensitivity binding — broadening (looser) opens Review sheet, tightening is inline.
    private var sensitivityBinding: Binding<EmailSensitivityLevel> {
        Binding(
            get: { currentSensitivity },
            set: { newLevel in
                let current = currentSensitivity
                let isBroadening = newLevel.isLooserThan(current)
                if isBroadening {
                    // Broadening → open Review sheet
                    broadenDomain = "__sensitivity_\(newLevel.rawValue)"
                } else {
                    // Tightening → immediate + undo toast
                    Task {
                        await store.policy.updateSensitivity(newLevel, for: focusedAgent)
                        await computeDomains()
                    }
                }
            }
        )
    }

    // MARK: - Narrowing (inline + undo)

    private func handleNarrow(domain: String) {
        Task { await store.policy.removeEmailDomain(domain, from: focusedAgent) }
        undoDomain = domain
        showUndoToast = true
        undoTimerTask?.cancel()
        undoTimerTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { showUndoToast = false }
        }
    }

    // MARK: - Undo Toast

    private func undoToastView(domain: String) -> some View {
        HStack(spacing: Spacing.standard) {
            Text("Removed \(focusedAgentName) access to @\(domain)")
                .font(.callout)
            Button("Undo") {
                Task { await store.policy.addEmailDomain(domain, to: focusedAgent) }
                showUndoToast = false
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, Spacing.edge)
        .padding(.vertical, Spacing.standard)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, Spacing.edge)
    }

    private var broadenBinding: Binding<ReviewAccessChange?> {
        Binding(
            get: {
                guard let domain = broadenDomain else { return nil }
                if domain.hasPrefix("__sensitivity_") {
                    let level = String(domain.dropFirst("__sensitivity_".count))
                    return ReviewAccessChange(
                        description: "Loosening \(focusedAgentName) sensitivity to \(level)",
                        kind: .loosenSensitivity(from: currentSensitivity, to: EmailSensitivityLevel(rawValue: level) ?? .moderate)
                    )
                }
                let count = domains.first(where: { $0.domain == domain })?.emailCount ?? 0
                return ReviewAccessChange(
                    description: "Adding @\(domain) to \(focusedAgentName) (\(count) emails + future mail)",
                    kind: .addDomain(domain: domain, emailCount: count)
                )
            },
            set: { if $0 == nil { broadenDomain = nil } }
        )
    }

    // MARK: - Empty State

    private var domainsEmptyState: some View {
        ContentUnavailableView {
            Label("No Email Domains", systemImage: "envelope.badge.shield.half.filled")
        } description: {
            Text("Add an email account in Settings to manage domain-level access for AI agents.")
        }
    }

    // MARK: - Computed Properties

    private var filteredDomains: [DomainAggregate] {
        if searchText.isEmpty { return domains }
        return domains.filter { $0.domain.localizedStandardContains(searchText) }
    }

    /// Compute domain aggregates using SQL GROUP BY instead of loading all messages.
    /// Saves ~10MB memory and ~50-200ms for 10K messages.
    private func computeDomains() async {
        guard let emailStore = store.emailStore else { return }
        let sensitivity = currentSensitivity

        let result = await Task.detached(priority: .userInitiated) {
            () -> [DomainAggregate] in
            // SQL GROUP BY: O(1) in Swift, database does the aggregation
            guard let counts = try? emailStore.domainCounts() else { return [] }

            return counts.map { domain, count in
                let reason = Self.hiddenReason(for: domain, sensitivity: sensitivity)
                let isHidden = reason != nil
                let category = Self.categorize(domain: domain, isHidden: isHidden)
                return DomainAggregate(
                    domain: domain,
                    emailCount: count,
                    category: category,
                    isHiddenBySensitivity: isHidden,
                    hiddenReason: reason
                )
            }
        }.value

        domains = result
    }

    nonisolated private static func categorize(domain: String, isHidden: Bool) -> DomainCategory {
        if isHidden { return .hidden }
        let automated = ["github.com", "circleci.com", "gitlab.com", "bitbucket.org",
                         "linear.app", "notion.so", "slack.com", "vercel.com"]
        if automated.contains(where: { domain.hasSuffix($0) }) { return .automated }
        let personal = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "icloud.com",
                         "protonmail.com", "fastmail.com"]
        if personal.contains(domain) { return .personal }
        return .work
    }

    nonisolated private static func hiddenReason(for domain: String, sensitivity: EmailSensitivityLevel) -> String? {
        // Always hidden regardless of sensitivity
        if domain.hasPrefix("noreply.") || domain.hasPrefix("no-reply.") { return "2FA" }

        let banking = ["bankofamerica.com", "chase.com", "wellsfargo.com", "fidelity.com",
                       "schwab.com", "vanguard.com", "citi.com"]
        let health = ["mychart.com", "myhealth.com", "anthem.com", "cigna.com",
                      "unitedhealthcare.com"]

        switch sensitivity {
        case .strict:
            // Everything is hidden in strict mode (only shared emails visible)
            return "strict mode"
        case .moderate:
            if banking.contains(where: { domain.hasSuffix($0) }) { return "banking" }
            if health.contains(where: { domain.hasSuffix($0) }) { return "health" }
        case .open:
            // Only always-hidden patterns (2FA above)
            break
        }
        return nil
    }
}
