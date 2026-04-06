import SwiftUI

struct SetupView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ConnectionTab()
                .tabItem { Label("Connection", systemImage: "antenna.radiowaves.left.and.right") }
            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
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

            Section("Apple Mail") {
                HStack {
                    mailStatusIndicator
                    Spacer()
                    Button("Test") {
                        Task { await store.checkMailAccess() }
                    }
                    .controlSize(.small)
                }

                DisclosureGroup("Help") {
                    Text("Go to System Settings \u{2192} Privacy & Security \u{2192} Automation, then enable Manifold for Mail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            store.checkMCPInstalled()
            store.checkAgentConfigs()
            await store.checkMailAccess()
        }
    }

    @ViewBuilder
    private var mailStatusIndicator: some View {
        switch store.mailAccessStatus {
        case .available:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color(nsColor: .systemGreen))
        case .mailNotRunning:
            Label("Mail not running", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color(nsColor: .systemYellow))
        case .accessDenied:
            Label("Permission needed", systemImage: "xmark.circle")
                .foregroundStyle(Color(nsColor: .systemRed))
        case nil:
            Label("Not checked", systemImage: "questionmark.circle")
                .foregroundStyle(.gray)
        }
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Form {
            Section {
                Text("Emails matching these patterns are automatically hidden from AI agents. Banking, 2FA, and healthcare emails are hidden by default.")
                    .foregroundStyle(.secondary)
            }

            Section("Email Rules") {
                if store.emailRules.isEmpty {
                    Text("No custom rules. Built-in rules for banking, 2FA, and healthcare are always active.")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(store.emailRules, id: \.id) { rule in
                        HStack {
                            Text(rule.pattern)
                                .font(.callout.monospaced())
                            Spacer()
                            Text(rule.category ?? "Other")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await store.removeEmailRule(id: rule.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await store.loadEmailRules() }
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
