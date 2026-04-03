import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAccessSummary = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            // Each detail view manages its own NavigationStack
            switch appState.selectedSidebar {
            case .sources:
                SourcesView()
            case .profiles:
                ProfilesView()
            case .activity:
                ActivityView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("What Claude sees", systemImage: "eye") {
                    showAccessSummary.toggle()
                }
                .popover(isPresented: $showAccessSummary) {
                    AccessSummaryView()
                        .environmentObject(appState)
                }
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(AppState.SidebarItem.allCases, selection: $appState.selectedSidebar) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 180)
    }
}

#Preview("Main Window") {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
