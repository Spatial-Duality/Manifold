import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAccessSummary = false

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedSidebar) {
                Section("Sources") {
                    Label("Files", systemImage: "folder")
                        .tag(AppState.SidebarItem.files)
                    Label("Emails", systemImage: "envelope")
                        .tag(AppState.SidebarItem.emails)
                }

                Section("Setup") {
                    Label("Profiles", systemImage: "person.2")
                        .tag(AppState.SidebarItem.profiles)
                }

                Section("Monitor") {
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                        .tag(AppState.SidebarItem.activity)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            switch appState.selectedSidebar {
            case .files:
                FilesView()
            case .emails:
                EmailsView()
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

#Preview("Main Window") {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
