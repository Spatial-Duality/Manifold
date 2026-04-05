import SwiftUI
import ManifoldKit

struct MainView: View {
    @Environment(ManifoldStore.self) var store
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailContent
                .inspector(isPresented: inspectorBinding) {
                    if let path = store.inspectedFilePath {
                        VersionDetailView(filePath: path)
                            .inspectorColumnWidth(min: 320, ideal: 400, max: 500)
                    }
                }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environment(store)
        }
        .task {
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

    @ViewBuilder
    private var detailContent: some View {
        switch store.selectedSidebarItem {
        case .dashboard, nil:
            DashboardView()
        case .activity:
            ActivityView()
        case .versions:
            VersionsView()
        }
    }
}
