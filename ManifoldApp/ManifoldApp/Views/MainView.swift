import SwiftUI
import ManifoldKit

struct MainView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            Group {
                switch store.selectedSection {
                case .summary:
                    SummaryView()
                case .sources:
                    SourcesSection()
                case .emails:
                    EmailsView()
                case .activity:
                    ActivityView()
                case .versions:
                    VersionsSection()
                case .setup:
                    SetupView()
                case nil:
                    SummaryView()
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(store)
        }
        .task {
            if !store.hasCompletedOnboarding {
                showOnboarding = true
            }
            await store.loadSummary()
        }
    }
}

// Wraps SourcesView in its own NavigationStack so back button works
struct SourcesSection: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var selectedWorkspace: WorkspaceRecord?

    var body: some View {
        NavigationStack {
            SourcesView(selectedWorkspace: $selectedWorkspace)
                .navigationDestination(item: $selectedWorkspace) { workspace in
                    SourceDetailView(workspace: workspace)
                }
        }
    }
}

// Wraps VersionsView in its own NavigationStack so back button works
struct VersionsSection: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var selectedFile: String?

    var body: some View {
        NavigationStack {
            VersionsView(selectedFile: $selectedFile)
                .navigationDestination(item: $selectedFile) { filePath in
                    VersionDetailView(filePath: filePath)
                }
        }
    }
}
