import SwiftUI
import ManifoldKit

struct MainView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(CommandCenter.self) var commands
    @State private var showOnboarding = false
    @SceneStorage("selectedTab") private var restoredTab: String = "overview"

    var body: some View {
        @Bindable var commands = commands
        @Bindable var store = store

        tabContent
        .frame(minWidth: 780, minHeight: 520)
        .overlay {
            if commands.isPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { commands.isPresented = false }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Dismiss command palette")

                VStack {
                    CommandPaletteView()
                        .padding(.top, 80)
                    Spacer()
                }
            }
        }
        .animation(.snappy, value: commands.isPresented)
        .onKeyPress(.escape) {
            if commands.isPresented { commands.isPresented = false; return .handled }
            if store.inspectedFilePath != nil { store.inspectedFilePath = nil; return .handled }
            return .ignored
        }
        .overlay(alignment: .top) {
            if let error = store.lastError {
                errorBanner(error)
            }
        }
        .sheet(isPresented: $showOnboarding) {
            SetupAssistantView()
                .environment(store)
        }
        .sheet(item: $store.reviewSheetTrigger) { change in
            ReviewAccessSheet(pendingChange: change)
                .environment(store)
                .frame(minWidth: 560, minHeight: 500)
        }
        .inspector(isPresented: $store.showActivityDrawer) {
            ActivityDrawer(isPresented: $store.showActivityDrawer)
                .environment(store)
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
        .sheet(isPresented: reviewChangesBinding) {
            if let block = store.policy.activeWorkBlock {
                ReviewChangesSheet(block: block)
                    .environment(store)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $store.selectedTab) {
                    Text("Overview").tag(AppTab.overview)
                    Text("Files").tag(AppTab.files)
                    Text("Emails").tag(AppTab.emails)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            // Track Changes indicator (when active)
            ToolbarItemGroup(placement: .secondaryAction) {
                if let block = store.policy.activeWorkBlock {
                    TrackChangesToolbarContent(
                        block: block,
                        onFinish: { Task { await store.policy.finishWorkBlock() } },
                        onPause: { Task { await store.policy.pauseWorkBlock() } },
                        onStop: { Task { await store.policy.stopWorkBlock() } }
                    )
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                connectionIndicators
            }
        }
        // WWDC25 356: remove custom toolbar backgrounds. Let Liquid Glass handle it.
        .task {
            // Restore tab from SceneStorage
            if let tab = AppTab(rawValue: restoredTab) { store.selectedTab = tab }
            commands.bind(to: store)
            if !store.hasCompletedOnboarding { showOnboarding = true }
            await store.loadSummary()
            await store.policy.loadPolicies()
            await store.policy.loadActiveWorkBlock()
        }
        .onChange(of: store.selectedTab) { _, newTab in
            restoredTab = newTab.rawValue
            // Clear file inspector when leaving Files tab
            if newTab != .files {
                store.inspectedFilePath = nil
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch store.selectedTab {
        case .overview:
            OverviewTab()
        case .files:
            FilesTab()
        case .emails:
            EmailsTab()
        }
    }

    /// Presents ReviewChangesSheet when a work block enters .reviewing status.
    /// Dismissing the sheet (Cancel) reverts to .active — does NOT promote.
    /// Promotion only happens from the sheet's Promote button.
    private var reviewChangesBinding: Binding<Bool> {
        Binding(
            get: { store.policy.activeWorkBlock?.status == .reviewing },
            set: { if !$0 { Task { await store.policy.cancelReview() } } }
        )
    }

    // MARK: - Connection Indicators

    // MARK: - Toolbar Status (X.4)

    @ViewBuilder
    private var connectionIndicators: some View {
        HStack(spacing: 12) {
            Button("Command Palette", systemImage: "magnifyingglass") {
                commands.isPresented.toggle()
            }
            .labelStyle(.iconOnly)
            .keyboardShortcut("k", modifiers: .command)
            .help("Command Palette (⌘K)")

            // Persistent status indicator — always visible on every tab
            HStack(spacing: 4) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(Typ.caption)
                    .foregroundStyle(.secondary)
            }
            .help(statusDetail)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statusDetail)
        }
    }

    private var statusDotColor: Color {
        if !store.isRuntimeConnected { return .statusDanger }
        if store.policy.isAnyAgentPaused { return .statusWarning }
        if store.connectedAgents.isEmpty { return .secondary }
        return .statusActive
    }

    private var statusLabel: String {
        if !store.isRuntimeConnected { return "Disconnected" }
        if store.connectedAgents.isEmpty { return "No agents" }
        if store.policy.isAnyAgentPaused { return "Paused" }
        return "Connected"
    }

    private var statusDetail: String {
        if !store.isRuntimeConnected { return "Runtime not connected" }
        var parts: [String] = []
        if store.isClaudeConnected {
            parts.append(store.policy.claudePolicy?.isPaused == true ? "Claude: Paused" : "Claude: Connected")
        }
        if store.isCodexConnected {
            parts.append(store.policy.codexPolicy?.isPaused == true ? "Codex: Paused" : "Codex: Connected")
        }
        if parts.isEmpty { return "No agents connected" }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        let isDatabase = error.lowercased().contains("database") || error.lowercased().contains("sqlite")
        let isConnection = error.lowercased().contains("connect") || error.lowercased().contains("network")

        return HStack(spacing: 8) {
            Image(systemName: isDatabase ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isDatabase ? Color.statusDanger : Color.statusWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(isDatabase ? "Database Error" : isConnection ? "Connection Issue" : "Notice")
                    .font(Typ.caption.weight(.medium))
                Text(error)
                    .font(Typ.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if isConnection {
                Button("Retry") { Task { await store.refresh() } }
                    .controlSize(.small)
            }
            Button("Dismiss", systemImage: "xmark") {
                store.lastError = nil
            }
            .labelStyle(.iconOnly)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .buttonStyle(.plain)
        }
        .padding(Spacing.section)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Spacing.standard))
        .toastElevation()
        .padding(.horizontal, Spacing.edge)
        .padding(.top, Spacing.standard)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(Anim.entrance, value: store.lastError)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error)")
    }
}

// MARK: - Overview Tab (full-width, no sidebar)

/// Overview tab — full-width, no sidebar. Shows agent policy cards.
private struct OverviewTab: View {
    var body: some View {
        OverviewView()
    }
}

// MARK: - Files Tab (sidebar + content + inspector)

/// Files tab with per-tab sidebar. Sidebar = source navigation.
/// When no source selected → Sources overview table (access controls).
/// When source selected → file browser.
private struct FilesTab: View {
    @Environment(ManifoldStore.self) var store
    @State private var selection: FilesSidebarSelection? = .dashboard

    var body: some View {
        NavigationSplitView {
            FilesSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            switch selection {
            case .dashboard, .none:
                FilesDashboardView()
            case .allSources:
                SourcesTableView()
            case .allFiles, .source, .recentlyModified, .aiTouched:
                FilesView(sidebarSelection: selection)
            }
        }
        .inspector(isPresented: inspectorBinding) {
            if let path = store.inspectedFilePath {
                VersionDetailView(filePath: path)
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 480)
            }
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { store.inspectedFilePath != nil },
            set: { if !$0 { store.inspectedFilePath = nil } }
        )
    }
}

// MARK: - Emails Tab (sidebar + content)

/// Emails tab with sidebar-driven mode switching.
/// "Rules" shows the runtime-backed email governance surface.
/// "Messages" shows the governed email archive browser.
/// Uses if/else to avoid nesting NavigationSplitViews which crashes on macOS.
///
/// EmailSelectionModel lives here so it survives tab switches.
private struct EmailsTab: View {
    @Environment(ManifoldStore.self) var store
    @State private var emailMode: EmailMode = .rules
    @State private var emailSelection = EmailSelectionModel()

    enum EmailMode: Hashable {
        case rules
        case messages
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    sidebarRow("Rules", systemImage: "shield", isSelected: emailMode == .rules) {
                        emailMode = .rules
                    }
                    sidebarRow("Messages", systemImage: "envelope", isSelected: emailMode == .messages && emailSelection.selectedAccountID == nil) {
                        emailMode = .messages
                        emailSelection.navigate(accountID: store.emailAccounts.accounts.first?.accountID)
                    }
                } header: {
                    Text("Mail")
                }
                .headerProminence(.increased)

                Section {
                    ForEach(store.emailAccounts.accounts) { account in
                        sidebarRow(account.displayName, systemImage: account.provider.systemImage, isSelected: emailMode == .messages && emailSelection.selectedAccountID == account.accountID) {
                            emailMode = .messages
                            emailSelection.navigate(accountID: account.accountID)
                        }
                    }
                    if store.emailAccounts.accounts.isEmpty {
                        Text("No accounts")
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                    }
                } header: {
                    Text("Accounts")
                }
                .headerProminence(.increased)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            .navigationTitle("Emails")
        } detail: {
            switch emailMode {
            case .rules:
                EmailRulesView()
            case .messages:
                EmailView(selection: emailSelection)
            }
        }
    }

    private func sidebarRow(_ title: String, systemImage: String, count: Int? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(Typ.numericCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .fontWeight(isSelected ? .medium : .regular)
    }

}
