import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            switch appState.selectedSidebar {
            case .sources:
                SourcesView()
            case .profiles:
                ProfilesView()
            case .activity:
                ActivityView()
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
