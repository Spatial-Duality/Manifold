import SwiftUI
import ManifoldKit

/// A computed domain aggregate for the domains table.
struct DomainAggregate: Identifiable, Hashable {
    let domain: String
    let emailCount: Int
    let category: DomainCategory
    let isHiddenBySensitivity: Bool
    let hiddenReason: String?

    var id: String { domain }
}

enum DomainCategory: String, CaseIterable {
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
    @State private var sensitivity: EmailSensitivityLevel = .moderate
    @State private var domains: [DomainAggregate] = []
    @State private var showUndoToast = false
    @State private var undoDomain: String?

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
        .searchable(text: $searchText, prompt: "Search domains...")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                AgentFocusControl(focus: $store.agentFocus)
            }
            ToolbarItem(placement: .automatic) {
                HStack(spacing: Spacing.tight) {
                    Text("Sensitivity:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("Sensitivity", selection: $sensitivity) {
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
        .task {
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
        .listStyle(.inset(alternatesRowBackgrounds: true))
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

            // Access checkbox
            if domain.isHiddenBySensitivity {
                Toggle(isOn: .constant(false)) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(true)
                    .accessibilityLabel("@\(domain.domain) — hidden by sensitivity")
            } else {
                Toggle(isOn: Binding(
                    get: { false }, // TODO: Wire to PolicyStore per-agent
                    set: { newValue in
                        if newValue {
                            // Broadening → Review sheet
                            // TODO: Phase 8
                        } else {
                            handleNarrow(domain: domain.domain)
                        }
                    }
                )) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("@\(domain.domain) access")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Narrowing

    private func handleNarrow(domain: String) {
        // TODO: Wire to PolicyStore
        undoDomain = domain
        showUndoToast = true
        Task {
            try? await Task.sleep(for: .seconds(5))
            if showUndoToast { showUndoToast = false }
        }
    }

    // MARK: - Undo Toast

    private func undoToastView(domain: String) -> some View {
        HStack(spacing: Spacing.standard) {
            Text("Removed access to @\(domain)")
                .font(.callout)
            Button("Undo") {
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

    /// Compute domain aggregates from EmailStore data.
    private func computeDomains() async {
        guard let emailStore = store.emailStore else { return }
        do {
            let messages = try emailStore.allEmailMessages(limit: 10_000)
            var domainCounts: [String: Int] = [:]
            for msg in messages {
                let domain = msg.senderDomain ?? "unknown"
                domainCounts[domain, default: 0] += 1
            }

            domains = domainCounts.map { domain, count in
                let reason = hiddenReason(for: domain)
                let isHidden = reason != nil
                let category = categorize(domain: domain, isHidden: isHidden)
                return DomainAggregate(
                    domain: domain,
                    emailCount: count,
                    category: category,
                    isHiddenBySensitivity: isHidden,
                    hiddenReason: reason
                )
            }
            .sorted { $0.emailCount > $1.emailCount }
        } catch {
            domains = []
        }
    }

    private func categorize(domain: String, isHidden: Bool) -> DomainCategory {
        if isHidden { return .hidden }
        let automated = ["github.com", "circleci.com", "gitlab.com", "bitbucket.org",
                         "linear.app", "notion.so", "slack.com", "vercel.com"]
        if automated.contains(where: { domain.hasSuffix($0) }) { return .automated }
        let personal = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "icloud.com",
                         "protonmail.com", "fastmail.com"]
        if personal.contains(domain) { return .personal }
        return .work
    }

    private func hiddenReason(for domain: String) -> String? {
        let banking = ["bankofamerica.com", "chase.com", "wellsfargo.com", "fidelity.com",
                       "schwab.com", "vanguard.com", "citi.com"]
        if banking.contains(where: { domain.hasSuffix($0) }) { return "banking" }
        let health = ["mychart.com", "myhealth.com", "anthem.com", "cigna.com",
                      "unitedhealthcare.com"]
        if health.contains(where: { domain.hasSuffix($0) }) { return "health" }
        if domain.hasPrefix("noreply.") || domain.hasPrefix("no-reply.") { return "2FA" }
        return nil
    }
}
