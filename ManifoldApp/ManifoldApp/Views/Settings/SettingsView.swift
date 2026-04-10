import SwiftUI
import ManifoldKit

/// Settings window — 4 tabs: General, AI Apps, Mail, Storage.
/// Uses SwiftUI Settings scene which auto-sizes per pane.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            AIAppsSettingsPane()
                .tabItem { Label("AI Apps", systemImage: "cpu") }
            MailSettingsPane()
                .tabItem { Label("Mail", systemImage: "envelope") }
            StorageSettingsPane()
                .tabItem { Label("Storage", systemImage: "externaldrive") }
        }
        .frame(minWidth: 580, minHeight: 500)
    }
}
