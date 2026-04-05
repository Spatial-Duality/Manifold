import SwiftUI
import ManifoldKit

struct OnboardingView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var claudeDesktopFound = false
    @State private var installing = false
    @State private var discoveredFolders: [String] = []
    @State private var selectedDiscovered: Set<String> = []

    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.2))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, Spacing.large).padding(.top, Spacing.edge)
            .accessibilityLabel("Setup progress: step \(step + 1) of \(totalSteps)")

            // Step indicator
            Text("Step \(step + 1) of \(totalSteps)")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, Spacing.tight + 2)

            Spacer()

            Group {
                switch step {
                case 0: welcomeStep
                case 1: claudeCheckStep
                case 2: installStep
                case 3: sourceStep
                case 4: emailStep
                case 5: doneStep
                default: EmptyView()
                }
            }
            .transition(.opacity)

            Spacer()

            // Navigation buttons
            HStack {
                if step > 0 && step < totalSteps - 1 {
                    Button("Back") { withAnimation { step -= 1 } }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if step < totalSteps - 1 {
                    Button(step == 0 ? "Get Started" : "Next") {
                        withAnimation { step += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(Spacing.large)
        }
        .frame(width: 580, height: 480)
        .interactiveDismissDisabled(step < totalSteps - 1)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48)).foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Welcome to Manifold")
                .font(.title.weight(.semibold))
            Text("Choose exactly what AI agents can see in your files.\nEvery change they make gets automatic version history.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: Spacing.standard) {
                featurePreview(icon: "folder.badge.gearshape", text: "Control which folders AI can access")
                featurePreview(icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", text: "Undo any AI change with one click")
                featurePreview(icon: "envelope.badge.shield.half.filled", text: "Share emails safely, sensitive ones auto-hidden")
            }
            .padding(Spacing.section)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.standard))
        }
        .padding(.horizontal, Spacing.xlarge + Spacing.standard)
    }

    private func featurePreview(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.standard) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 1: Check Claude Desktop

    private var claudeCheckStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 36)).foregroundStyle(Color.accentColor)
            Text("Check for Claude Desktop")
                .font(.title2.weight(.semibold))
            Text("Manifold needs Claude Desktop or Codex installed on your Mac to work.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            if claudeDesktopFound {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityLabel("Found")
                    Text("Claude Desktop found").font(.callout.weight(.medium))
                }
                .padding(.top, Spacing.standard)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                            .accessibilityLabel("Warning")
                        Text("Claude Desktop not found").font(.callout)
                    }
                    Text("Download it from Anthropic, then click Check Again.")
                        .font(.caption).foregroundStyle(.tertiary)
                    Button("Check Again") { checkClaudeDesktop() }
                        .controlSize(.small)
                }
            }

            Button("Skip (I'll install it later)") {
                withAnimation { step += 1 }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.xlarge + Spacing.standard)
        .task { checkClaudeDesktop() }
    }

    // MARK: - Step 2: Install MCP

    private var installStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 36)).foregroundStyle(Color.accentColor)
            Text("Install MCP Server")
                .font(.title2.weight(.semibold))
            Text("This copies the Manifold MCP binary and updates your Claude Desktop configuration so they can talk to each other.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            activationLabel("Activates: Agent connection, file monitoring, session replay")

            if store.mcpInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityLabel("Installed")
                    Text("Installed").font(.callout.weight(.medium))
                }
                VStack(alignment: .leading, spacing: 4) {
                    configLine("MCP binary", path: ManifoldStore.mcpBinaryPath())
                    if store.claudeDesktopConfigured {
                        configLine("Claude config", path: "~/Library/Application Support/Claude/claude_desktop_config.json")
                    }
                    if store.codexConfigured {
                        configLine("Codex config", path: "~/.codex/config.toml")
                    }
                }
                .padding(Spacing.standard)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if installing {
                ProgressView("Installing...")
            } else {
                Button("Install MCP Server") {
                    installing = true
                    store.installMCP()
                    store.checkMCPInstalled()
                    store.checkAgentConfigs()
                    installing = false
                }
                .buttonStyle(.borderedProminent)

                if let error = store.installError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Try Again") {
                        store.installError = nil
                        installing = true
                        store.installMCP()
                        installing = false
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, Spacing.xlarge + Spacing.standard)
    }

    // MARK: - Step 3: Add Source

    private var sourceStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36)).foregroundStyle(Color.accentColor)
            Text("Add Your First Source")
                .font(.title2.weight(.semibold))
            Text("Choose a folder to share with AI agents. Claude can read files here. Every change is versioned automatically.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            activationLabel("Activates: File browsing, search, version history, one-click revert")

            // Auto-discovered folders
            if !discoveredFolders.isEmpty && store.approvedSources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Found on your Mac:").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    ForEach(discoveredFolders, id: \.self) { path in
                        HStack {
                            Image(systemName: selectedDiscovered.contains(path) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedDiscovered.contains(path) ? .green : .gray)
                                .accessibilityLabel(selectedDiscovered.contains(path) ? "Selected" : "Not selected")
                            Text(shortenPath(path)).font(.caption.monospaced()).lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(.isButton)
                        .onTapGesture {
                            if selectedDiscovered.contains(path) { selectedDiscovered.remove(path) }
                            else { selectedDiscovered.insert(path) }
                        }
                    }
                    if !selectedDiscovered.isEmpty {
                        Button("Add \(selectedDiscovered.count) folder\(selectedDiscovered.count == 1 ? "" : "s")") {
                            for path in selectedDiscovered { store.addSource(path: path) }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                .padding(Spacing.section).background(Color(.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: Spacing.standard))
            }

            // Already added
            if !store.approvedSources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.approvedSources, id: \.self) { path in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(shortenPath(path)).font(.caption.monospaced()).lineLimit(1)
                        }
                    }
                }
            }

            Button("Choose Another Folder") { store.addSourceFromPicker() }.buttonStyle(.bordered)
            Button("Skip for Now") { withAnimation { step += 1 } }
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.xlarge + Spacing.standard)
        .task { discoverFolders() }
    }

    // MARK: - Step 4: Email (Optional)

    private var emailStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 36)).foregroundStyle(Color.accentColor)
            Text("Connect Apple Mail")
                .font(.title2.weight(.semibold))
            Text("Optionally let Claude see your emails. Manifold auto-hides sensitive ones (banking, 2FA, healthcare) and you control what's shared.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            activationLabel("Activates: Email sharing with automatic privacy filtering")

            switch store.mailAccessStatus {
            case .available:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Apple Mail connected").font(.callout.weight(.medium))
                }
            case .mailNotRunning:
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                    Text("Mail.app is not running").font(.callout)
                }
                Button("Check Again") { Task { await store.checkMailAccess() } }
                    .controlSize(.small)
            case .accessDenied:
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle").foregroundStyle(.red)
                    Text("Automation permission needed").font(.callout)
                }
                Text("Go to System Settings → Privacy & Security → Automation and enable Manifold for Mail.")
                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                Button("Check Again") { Task { await store.checkMailAccess() } }
                    .controlSize(.small)
            case nil:
                Button("Connect Apple Mail") { Task { await store.checkMailAccess() } }
                    .buttonStyle(.borderedProminent)
            }

            Button("I don't use Apple Mail") { withAnimation { step += 1 } }
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.xlarge + Spacing.standard)
        .task { await store.checkMailAccess() }
    }

    // MARK: - Step 5: Done

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48)).foregroundStyle(.green)
            Text("You're Ready")
                .font(.title.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                summaryRow("MCP Server", done: store.mcpInstalled, detail: store.mcpInstalled ? "Installed" : "Not installed, set up in Settings")
                summaryRow("Source Folders", done: !store.approvedSources.isEmpty, detail: store.approvedSources.isEmpty ? "None added yet" : "\(store.approvedSources.count) folder(s)")
                summaryRow("Apple Mail", done: store.mailAccessStatus == .available, detail: store.mailAccessStatus == .available ? "Connected" : "Not connected")
            }

            if !store.mcpInstalled || store.approvedSources.isEmpty {
                Text("You can finish setup anytime in Settings (Cmd+,)")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Button("Open Manifold") {
                store.hasCompletedOnboarding = true
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, Spacing.xlarge + Spacing.standard)
    }

    // MARK: - Helpers

    private func summaryRow(_ label: String, done: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .gray)
                .accessibilityLabel(done ? "Complete" : "Incomplete")
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func activationLabel(_ text: String) -> some View {
        HStack(spacing: Spacing.tight) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.standard)
        .padding(.vertical, Spacing.tight)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.tight))
    }

    private func configLine(_ label: String, path: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark").foregroundStyle(.green).imageScale(.small)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    private func checkClaudeDesktop() {
        let claudePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude")
        claudeDesktopFound = FileManager.default.fileExists(atPath: claudePath.path)
    }

    private func discoverFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        discoveredFolders = ["Developer", "Projects", "Documents", "Desktop"].compactMap { dir -> String? in
            let url = home.appendingPathComponent(dir)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
            else { return nil }
            let subdirCount = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.count
            return (1..<50).contains(subdirCount) ? url.path : nil
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
