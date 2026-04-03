import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAccessSummary = false

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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showAccessSummary.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 11))
                        Text("What Claude sees")
                            .font(.system(size: 11))
                    }
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
