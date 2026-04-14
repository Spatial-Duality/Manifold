// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Settings window — General / Agents / Storage / Mail / Advanced.
/// Stage-3 structure. Normal users stay in the first four panes; the
/// Advanced pane is a destination, never a gate.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("Agents", systemImage: "sparkle") {
                AIAppsSettingsPane()
            }
            Tab("Storage", systemImage: "externaldrive") {
                StorageSettingsPane()
            }
            Tab("Mail", systemImage: "envelope") {
                MailSettingsPane()
            }
            Tab("Advanced", systemImage: "slider.horizontal.3") {
                AdvancedSettingsPane()
            }
        }
        .frame(minWidth: 580, minHeight: 500)
    }
}
