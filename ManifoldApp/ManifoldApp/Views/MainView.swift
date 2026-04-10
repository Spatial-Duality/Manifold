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
        .animation(.easeInOut(duration: 0.15), value: commands.isPresented)
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
        .animation(.easeInOut(duration: 0.25), value: store.lastError)
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
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
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

/// Emails tab with mode-driven navigation.
/// Domains mode → DomainsTableView with its own sidebar.
/// Messages mode → EmailView (which has its own NavigationSplitView).
/// Uses if/else to avoid nesting NavigationSplitViews which crashes on macOS.
private struct EmailsTab: View {
    @State private var showingDomains = true

    var body: some View {
        if showingDomains {
            DomainsTableView()
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button("View Messages") {
                            showingDomains = false
                        }
                        .controlSize(.small)
                    }
                }
        } else {
            EmailView()
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button("\u{2190} Domains") {
                            showingDomains = true
                        }
                        .controlSize(.small)
                    }
                }
        }
    }
}
