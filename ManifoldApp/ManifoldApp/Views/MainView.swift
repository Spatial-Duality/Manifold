import SwiftUI
import ManifoldKit

struct MainView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(CommandCenter.self) var commands
    @State private var showOnboarding = false
    @State private var reviewSheetChange: ReviewAccessChange?

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
        .sheet(item: $reviewSheetChange) { change in
            ReviewAccessSheet(pendingChange: change)
                .environment(store)
                .frame(minWidth: 560, minHeight: 500)
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
        .toolbarBackgroundVisibility(
            store.policy.activeWorkBlock != nil ? .visible : .automatic,
            for: .windowToolbar
        )
        .toolbarBackground(
            store.policy.activeWorkBlock?.agent == .codex
                ? Color.purple.opacity(0.06)
                : store.policy.activeWorkBlock != nil
                    ? Color.blue.opacity(0.06)
                    : Color.clear,
            for: .windowToolbar
        )
        .task {
            commands.bind(to: store)
            if !store.hasCompletedOnboarding { showOnboarding = true }
            await store.loadSummary()
            await store.policy.loadPolicies()
            await store.policy.loadActiveWorkBlock()
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
    private var reviewChangesBinding: Binding<Bool> {
        Binding(
            get: { store.policy.activeWorkBlock?.status == .reviewing },
            set: { if !$0 { Task { await store.policy.completeWorkBlock() } } }
        )
    }

    // MARK: - Connection Indicators

    @ViewBuilder
    private var connectionIndicators: some View {
        HStack(spacing: 12) {
            Button {
                commands.isPresented.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .keyboardShortcut("k", modifiers: .command)
            .help("Command Palette (⌘K)")

            if store.isConnected, let agent = store.connectedAgent {
                HStack(spacing: 4) {
                    Circle()
                        .fill(agent.lowercased().contains("codex") ? Color.purple : Color.blue)
                        .frame(width: 8, height: 8)
                    Text(agent.capitalized)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(agent) connected")
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(error)
                .font(.callout)
            Spacer()
            Button("Dismiss") { store.lastError = nil }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
        }
        .padding(Spacing.section)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Spacing.standard))
        .padding(.horizontal, Spacing.edge)
        .padding(.top, Spacing.standard)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring, value: store.lastError)
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
    @State private var selection: FilesSidebarSelection?

    var body: some View {
        NavigationSplitView {
            FilesSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            if selection == nil {
                // No source selected → Sources overview with agent access controls
                SourcesTableView()
            } else {
                // Sidebar selection → file browser
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
/// "All Domains" → DomainsTableView (governance surface).
/// Account/mailbox → EmailView (browsing surface with its own NavigationSplitView).
/// Uses if/else to avoid nesting NavigationSplitViews which crashes on macOS.
private struct EmailsTab: View {
    @Environment(ManifoldStore.self) var store
    @State private var emailMode: EmailMode = .domains

    enum EmailMode: Hashable {
        case domains
        case messages
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar — always present
            List(selection: $emailMode) {
                Section("Mail") {
                    Label("All Domains", systemImage: "tray.full")
                        .tag(EmailMode.domains)
                    Label("Messages", systemImage: "envelope")
                        .tag(EmailMode.messages)
                }

                Section("Accounts") {
                    ForEach(store.emailAccounts.accounts) { account in
                        Button {
                            emailMode = .messages
                        } label: {
                            Label(account.displayName, systemImage: "envelope")
                        }
                    }
                    if store.emailAccounts.accounts.isEmpty {
                        Text("No accounts")
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        store.showActivityDrawer = true
                    } label: {
                        Label("View Activity", systemImage: "list.bullet.rectangle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            .navigationTitle("Emails")
        } detail: {
            // Content switches based on sidebar selection
            switch emailMode {
            case .domains:
                DomainsTableView()
            case .messages:
                // EmailView has its own NavigationSplitView internally
                // This is safe because it's the sole detail content, not nested
                EmailView()
            }
        }
    }
}
