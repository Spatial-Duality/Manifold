import SwiftUI
import ManifoldKit

struct SetupView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var gcResult: Int?
    @State private var pruneResult: Int?
    @State private var integrityResult: Bool?

    var body: some View {
        Form {
            Section("MCP Server") {
                HStack {
                    if store.mcpInstalled {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Installed")
                    } else {
                        Image(systemName: "xmark.circle").foregroundStyle(.red)
                        Text("Not installed")
                    }
                    Spacer()
                    Button(store.mcpInstalled ? "Reinstall" : "Install") {
                        store.installMCP()
                    }
                    .buttonStyle(.bordered)
                }
                if let error = store.installError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text(ManifoldStore.mcpBinaryPath())
                    .font(.caption.monospaced()).foregroundStyle(.tertiary)
            }

            Section("Agent Configurations") {
                HStack {
                    Image(systemName: store.claudeDesktopConfigured ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.claudeDesktopConfigured ? .green : .gray)
                    Text("Claude Desktop")
                    Spacer()
                    if !store.claudeDesktopConfigured {
                        Text("Not found").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Image(systemName: store.codexConfigured ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.codexConfigured ? .green : .gray)
                    Text("Codex")
                    Spacer()
                    if !store.codexConfigured {
                        Text("Not found").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Apple Mail") {
                HStack {
                    switch store.mailAccessStatus {
                    case .available:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Connected")
                    case .mailNotRunning:
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                        Text("Mail not running")
                    case .accessDenied:
                        Image(systemName: "xmark.circle").foregroundStyle(.red)
                        Text("Permission denied")
                    case nil:
                        Image(systemName: "questionmark.circle").foregroundStyle(.gray)
                        Text("Not checked")
                    }
                    Spacer()
                    Button("Test") {
                        Task { await store.checkMailAccess() }
                    }
                    .controlSize(.small)
                }
            }

            Section("Storage") {
                LabeledContent("Store Location") {
                    Text(ManifoldStore.storeURL().path)
                        .font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                LabeledContent("Size") {
                    Text(formatBytes(store.storageUsed))
                }
                LabeledContent("Versions") {
                    Text("\(store.blobCount)")
                }
                LabeledContent("Tracked Files") {
                    Text("\(store.allTrackedFiles.count)")
                }

                HStack {
                    Button("Garbage Collect") {
                        Task {
                            gcResult = await store.runGarbageCollection()
                            await store.loadStorageStats()
                        }
                    }
                    .controlSize(.small)
                    if let gc = gcResult {
                        Text("Removed \(gc) blobs").font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Prune Old Runs") {
                        Task {
                            pruneResult = await store.pruneOldRuns()
                            await store.loadStorageStats()
                        }
                    }
                    .controlSize(.small)
                    if let pr = pruneResult {
                        Text("Pruned \(pr)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Integrity Check") {
                        Task { integrityResult = await store.runIntegrityCheck() }
                    }
                    .controlSize(.small)
                    if let ok = integrityResult {
                        Text(ok ? "OK" : "FAILED")
                            .font(.caption)
                            .foregroundStyle(ok ? .green : .red)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") { Text("0.2.0") }
                LabeledContent("Bundle ID") { Text("com.spatialduality.manifold") }
                Text("Spatial Duality")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Setup")
        .task {
            store.checkMCPInstalled()
            store.checkAgentConfigs()
            await store.loadStorageStats()
            await store.loadTrackedFiles()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
