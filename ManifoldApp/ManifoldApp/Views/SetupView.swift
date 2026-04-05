import SwiftUI
import ManifoldKit

struct SetupView: View {
    @Environment(ManifoldStore.self) var store
    @State private var gcResult: Int?
    @State private var pruneResult: Int?
    @State private var integrityResult: Bool?

    var body: some View {
        Form {
            Section("MCP Server") {
                HStack {
                    Image(systemName: store.mcpInstalled ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(store.mcpInstalled ? .green : .red)
                    Text(store.mcpInstalled ? "Installed" : "Not installed")
                    Spacer()
                    Button(store.mcpInstalled ? "Reinstall" : "Install") { store.installMCP() }
                        .controlSize(.small)
                }
                if let error = store.installError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text(ManifoldStore.mcpBinaryPath()).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }

            Section("Agent Configurations") {
                LabeledContent("Claude Desktop") {
                    Image(systemName: store.claudeDesktopConfigured ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.claudeDesktopConfigured ? .green : .gray)
                }
                LabeledContent("Codex") {
                    Image(systemName: store.codexConfigured ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.codexConfigured ? .green : .gray)
                }
            }

            Section("Apple Mail") {
                HStack {
                    switch store.mailAccessStatus {
                    case .available: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Connected")
                    case .mailNotRunning: Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow); Text("Mail not running")
                    case .accessDenied: Image(systemName: "xmark.circle").foregroundStyle(.red); Text("Permission needed")
                    case nil: Image(systemName: "questionmark.circle").foregroundStyle(.gray); Text("Not checked")
                    }
                    Spacer()
                    Button("Test") { Task { await store.checkMailAccess() } }.controlSize(.small)
                }
            }

            Section("Email Rules") {
                if store.emailRules.isEmpty {
                    Text("Default rules for banking, 2FA, healthcare are built in.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.emailRules, id: \.id) { rule in
                        HStack {
                            Text(rule.pattern).font(.callout.monospaced())
                            Spacer()
                            Text(rule.category ?? "Other").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await store.removeEmailRule(id: rule.id) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }

            Section("Storage") {
                LabeledContent("Location") {
                    Text(ManifoldStore.storeURL().path).font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                LabeledContent("Size") { Text(ByteCountFormatter.string(fromByteCount: store.storageUsed, countStyle: .file)) }
                LabeledContent("Versions") { Text("\(store.blobCount)") }
                LabeledContent("Files tracked") { Text("\(store.allTrackedFiles.count)") }

                HStack {
                    Button("Clean Up Storage") {
                        Task { gcResult = await store.runGarbageCollection(); await store.loadStorageStats() }
                    }.controlSize(.small)
                    if let gc = gcResult { Text("Removed \(gc) items").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Remove Old Versions") {
                        Task { pruneResult = await store.pruneOldRuns(); await store.loadStorageStats() }
                    }.controlSize(.small)
                    if let pr = pruneResult { Text("Removed \(pr)").font(.caption).foregroundStyle(.secondary) }
                }
                HStack {
                    Button("Verify Database") {
                        Task { integrityResult = await store.runIntegrityCheck() }
                    }.controlSize(.small)
                    if let ok = integrityResult {
                        Text(ok ? "OK" : "FAILED").font(.caption).foregroundStyle(ok ? .green : .red)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") { Text("0.3.0") }
                LabeledContent("Bundle") { Text("com.spatialduality.manifold") }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Setup")
        .task {
            store.checkMCPInstalled(); store.checkAgentConfigs()
            await store.loadStorageStats(); await store.loadTrackedFiles()
            await store.loadEmailRules(); await store.checkMailAccess()
        }
    }
}
