import SwiftUI
import ManifoldKit

struct SetupView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ConnectionTab()
                .tabItem { Label("Connection", systemImage: "antenna.radiowaves.left.and.right") }
            EmailBackupTab()
                .tabItem { Label("Email", systemImage: "envelope") }
            StorageTab()
                .tabItem { Label("Storage", systemImage: "externaldrive") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                Toggle("Launch at Login", isOn: $store.launchAtLogin)
            }

            Section("Notifications") {
                Toggle("Session start and end", isOn: $store.notifyOnSessionEnd)
                Toggle("Access denied alerts", isOn: $store.notifyOnAccessDenied)
            }

            Section {
                Text("Accent color follows System Settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Connection

private struct ConnectionTab: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Form {
            Section("Server Status") {
                HStack {
                    ColorIndicator(color: store.mcpInstalled ? .green : .red)
                        .accessibilityLabel(store.mcpInstalled ? "Installed" : "Not installed")
                    Text(store.mcpInstalled ? "Installed" : "Not installed")
                    Spacer()
                    Button(store.mcpInstalled ? "Reinstall" : "Install") {
                        store.installMCP()
                    }
                    .controlSize(.small)
                }

                DisclosureGroup("Details") {
                    if let error = store.installError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text(ManifoldStore.mcpBinaryPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }

            Section("Agents") {
                LabeledContent("Claude Desktop") {
                    Image(systemName: store.claudeDesktopConfigured ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.claudeDesktopConfigured ? Color(nsColor: .systemGreen) : .gray)
                        .accessibilityLabel(store.claudeDesktopConfigured ? "Configured" : "Not configured")
                }
                LabeledContent("Codex") {
                    Image(systemName: store.codexConfigured ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.codexConfigured ? Color(nsColor: .systemGreen) : .gray)
                        .accessibilityLabel(store.codexConfigured ? "Configured" : "Not configured")
                }
            }

        }
        .formStyle(.grouped)
        .task {
            store.checkMCPInstalled()
            store.checkAgentConfigs()
        }
    }
}

// MARK: - Email Backup

private struct EmailBackupTab: View {
    @Environment(ManifoldStore.self) var store
    @State private var showAddAccount = false
    @State private var confirmDelete: EmailAccountRecord?

    var body: some View {
        Form {
            Section("Accounts") {
                if store.emailAccounts.accounts.isEmpty {
                    Text("No email accounts configured. Add one to start continuous backup.")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(store.emailAccounts.accounts) { account in
                        HStack(spacing: Spacing.section) {
                            Image(systemName: account.provider.systemImage)
                                .foregroundStyle(providerColor(account.provider))
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(.callout.weight(.medium))
                                HStack(spacing: Spacing.standard) {
                                    Text(account.username ?? "")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("\u{2022}").foregroundStyle(.quaternary).font(.caption2)
                                    Text(account.server ?? "")
                                        .font(.caption.monospaced()).foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { account.syncEnabled },
                                set: { enabled in
                                    Task { await store.emailAccounts.toggleSync(accountID: account.accountID, enabled: enabled) }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()

                            Button {
                                Task { await store.emailAccounts.syncNow(accountID: account.accountID) }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderless)
                            .help("Sync Now")

                            Button(role: .destructive) {
                                confirmDelete = account
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove Account")
                        }
                    }
                }

                Button("Add Email Account") { showAddAccount = true }
                    .controlSize(.small)
            }

            Section("Storage") {
                LabeledContent("Backup location") {
                    HStack(spacing: Spacing.tight) {
                        Text(store.emailAccounts.backupRootPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: store.emailAccounts.backupRootPath)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                }

                LabeledContent("Total messages") {
                    Text("\(store.emailAccounts.totalMessageCount)")
                        .monospacedDigit()
                }

                let usage = store.emailAccounts.backupDiskUsage
                if usage > 0 {
                    LabeledContent("Disk usage") {
                        Text(ByteCountFormatter.string(fromByteCount: usage, countStyle: .file))
                            .monospacedDigit()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddAccount) {
            EmailAccountSetupView()
        }
        .alert("Remove Account?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmDelete = nil }
            Button("Remove", role: .destructive) {
                if let account = confirmDelete {
                    Task { await store.emailAccounts.removeAccount(id: account.accountID) }
                }
                confirmDelete = nil
            }
        } message: {
            Text("This will remove \(confirmDelete?.displayName ?? "this account") and stop syncing. Backed up .eml files on disk will not be deleted.")
        }
        .task {
            await store.emailAccounts.loadAccounts()
        }
    }

    private func providerColor(_ provider: EmailProvider) -> Color {
        switch provider {
        case .gmail:    .red
        case .outlook:  .blue
        case .icloud:   .cyan
        case .yahoo:    .purple
        case .fastmail: .indigo
        case .other:    .secondary
        }
    }
}

// MARK: - Storage

private struct StorageTab: View {
    @Environment(ManifoldStore.self) var store
    @State private var gcResult: Int?
    @State private var pruneResult: Int?
    @State private var integrityResult: Bool?

    var body: some View {
        Form {
            Section {
                LabeledContent("Location") {
                    Text(ManifoldStore.storeURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                LabeledContent("Size") {
                    Text(ByteCountFormatter.string(fromByteCount: store.storageUsed, countStyle: .file))
                }
                LabeledContent("Versions") {
                    Text("\(store.blobCount)")
                }
                LabeledContent("Files tracked") {
                    Text("\(store.allTrackedFiles.count)")
                }
            }

            Section {
                DisclosureGroup("Maintenance") {
                    HStack {
                        Button("Clean Up Storage") {
                            Task {
                                gcResult = await store.runGarbageCollection()
                                await store.loadStorageStats()
                            }
                        }
                        .controlSize(.small)
                        if let gc = gcResult {
                            Text("Removed \(gc) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button("Remove Old Versions") {
                            Task {
                                pruneResult = await store.pruneOldRuns()
                                await store.loadStorageStats()
                            }
                        }
                        .controlSize(.small)
                        if let pr = pruneResult {
                            Text("Removed \(pr)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button("Verify Database") {
                            Task { integrityResult = await store.runIntegrityCheck() }
                        }
                        .controlSize(.small)
                        if let ok = integrityResult {
                            Text(ok ? "OK" : "FAILED")
                                .font(.caption)
                                .foregroundStyle(ok ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await store.loadStorageStats()
            await store.loadTrackedFiles()
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: Spacing.large) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Manifold")
                .font(.title.weight(.medium))

            Text("Spatial Duality")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: Spacing.tight) {
                Text("Version 0.3.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("com.spatialduality.manifold")
                    .font(.caption.monospaced())
                    .foregroundStyle(.quaternary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
