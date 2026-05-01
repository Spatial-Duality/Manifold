// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// StorageSettingsPane — user-facing storage stats.
//
// Stage-11 redesign: the "Database" section (location + Finder button)
// moved out; AdvancedSettingsPane owns every raw-path diagnostic now.
// This pane is the plain-language stats pane — how much space is used
// and how many versions are tracked — plus the two maintenance
// affordances (clean up orphan blobs, verify database).

import SwiftUI
import ManifoldKit

struct StorageSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var gcResult: Int?
    @State private var integrityResult: Bool?

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Blob storage") {
                    Text(ByteCountFormatter.string(fromByteCount: store.storageUsed,
                                                   countStyle: .file))
                        .monospacedDigit()
                }
                LabeledContent("Versions tracked") {
                    Text("\(store.allTrackedFiles.count) files")
                        .monospacedDigit()
                }
            }

            Section("Maintenance") {
                HStack {
                    Button("Clean up orphan blobs") {
                        Task { gcResult = await store.runGarbageCollection() }
                    }
                    .controlSize(.small)

                    if let gc = gcResult {
                        Text(gc > 0 ? "Removed \(gc) orphaned blobs" : "Nothing to clean up")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Verify database") {
                        Task { integrityResult = await store.runIntegrityCheck() }
                    }
                    .controlSize(.small)

                    if let ok = integrityResult {
                        Label(ok ? "Database OK" : "Issues found",
                              systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(ManifoldType.caption)
                            .foregroundStyle(ok
                                             ? ManifoldPalette.active
                                             : ManifoldPalette.attention)
                    }
                }
            }

            Section {
                Text("Detailed paths and raw-disk diagnostics live in Advanced.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

extension Bundle {
    var shortVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
