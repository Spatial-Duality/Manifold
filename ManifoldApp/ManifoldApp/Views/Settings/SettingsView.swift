// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Settings window — 4 tabs: General, AI Apps, Mail, Storage.
/// Uses SwiftUI Settings scene which auto-sizes per pane.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("AI Apps", systemImage: "cpu") {
                AIAppsSettingsPane()
            }
            Tab("Mail", systemImage: "envelope") {
                MailSettingsPane()
            }
            Tab("Storage", systemImage: "externaldrive") {
                StorageSettingsPane()
            }
        }
        .frame(minWidth: 580, minHeight: 500)
    }
}
