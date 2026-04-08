import SwiftUI
import ManifoldKit

struct MainView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(CommandCenter.self) var commands
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var commands = commands

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: inspectorBinding) {
            if let path = store.inspectedFilePath {
                VersionDetailView(filePath: path)
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 480)
            }
        }
        .overlay(alignment: .top) {
            if let error = store.lastError {
                errorBanner(error)
            }
        }
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
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environment(store)
        }
        .task {
            commands.bind(to: store)
            if !store.hasCompletedOnboarding { showOnboarding = true }
            await store.loadSummary()
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { store.inspectedFilePath != nil },
            set: { if !$0 { store.inspectedFilePath = nil } }
        )
    }

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
        .glassBackground(in: RoundedRectangle(cornerRadius: Spacing.standard))
        .padding(.horizontal, Spacing.edge)
        .padding(.top, Spacing.standard)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: store.lastError)
    }

    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch store.selectedSidebarItem {
            case .home, nil:
                HomeView()
            case .files:
                SessionView()
            case .emails:
                EmailView()
            case .history:
                HistoryView()
            case .sources:
                SourcesView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
