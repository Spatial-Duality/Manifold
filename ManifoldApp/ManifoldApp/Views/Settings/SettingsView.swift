// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Settings window — General / Agents / Storage / Mail / Advanced.
/// Stage-3 structure: engineering-flavored controls migrate to Advanced
/// in a subsequent minor pass; Phase 8 is the copy pass only.
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
        }
        .frame(minWidth: 580, minHeight: 500)
    }
}
