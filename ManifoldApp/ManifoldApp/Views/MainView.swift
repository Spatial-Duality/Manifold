import SwiftUI
import ManifoldKit

struct MainView: View {
    @EnvironmentObject var store: ManifoldStore
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
                .environmentObject(store)
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
        case .summary:
            SummaryView()
        case .sources:
            SourcesView()
        case .sourceDetail(let wsID):
            if let ws = store.workspaces.first(where: { $0.workspaceID == wsID }) {
                SourceDetailView(workspace: ws)
            } else {
                SourcesView()
            }
        case .emailOverview:
            EmailOverviewView()
        case .emailInbox:
            EmailListView()
        case .emailRules:
            EmailRulesView()
        case .activity:
            ActivityView()
        case .versions:
            VersionsView()
        case nil:
            SummaryView()
        }
    }
}
