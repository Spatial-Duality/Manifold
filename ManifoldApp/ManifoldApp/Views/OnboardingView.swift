import SwiftUI
import ManifoldKit

struct OnboardingView: View {
    @EnvironmentObject var store: ManifoldStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var discoveredFolders: [String] = []
    @State private var selectedDiscovered: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // Step content
            switch step {
            case 0: welcomeStep
            case 1: installStep
            case 2: sourceStep
            case 3: doneStep
            default: EmptyView()
            }

            Spacer()

            // Navigation
            HStack {
                if step > 0 && step < 3 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if step < 3 {
                    Button(step == 0 ? "Get Started" : "Next") { step += 1 }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 500, height: 380)
        .interactiveDismissDisabled(step < 3)
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Manifold")
                .font(.title.weight(.semibold))
            Text("Choose what AI agents can see.\nEvery file they touch is versioned automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private var installStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Install MCP Server")
                .font(.title2.weight(.semibold))
            Text("Manifold connects to Claude and Codex via the MCP protocol. This installs the server binary and configures both apps.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if store.mcpInstalled {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Already installed")
                }
            } else {
                Button("Install MCP Server") {
                    store.installMCP()
                }
                .buttonStyle(.borderedProminent)

                if let error = store.installError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 40)
    }

    private var sourceStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Add Your First Source")
                .font(.title2.weight(.semibold))
            Text("Select a folder to share with AI agents. Files are never copied. Manifold versions every change the agent makes.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Auto-discovered folders
            if !discoveredFolders.isEmpty && store.approvedSources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Found on your Mac:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    ForEach(discoveredFolders, id: \.self) { path in
                        HStack {
                            Image(systemName: selectedDiscovered.contains(path) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedDiscovered.contains(path) ? .green : .gray)
                            Text(shortenPath(path))
                                .font(.caption.monospaced())
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedDiscovered.contains(path) {
                                selectedDiscovered.remove(path)
                            } else {
                                selectedDiscovered.insert(path)
                            }
                        }
                    }
                    if !selectedDiscovered.isEmpty {
                        Button("Add \(selectedDiscovered.count) folder\(selectedDiscovered.count == 1 ? "" : "s")") {
                            for path in selectedDiscovered {
                                store.addSource(path: path)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Already added sources
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

            Button("Choose Another Folder") {
                store.addSourceFromPicker()
            }
            .buttonStyle(.bordered)

            Button("Skip for Now") { step += 1 }
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
        .task { discoverFolders() }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("You're Ready")
                .font(.title.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                statusRow("MCP Server", done: store.mcpInstalled)
                statusRow("Source Folder", done: !store.approvedSources.isEmpty)
            }

            Button("Open Manifold") {
                store.hasCompletedOnboarding = true
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 40)
    }

    private func statusRow(_ label: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .gray)
            Text(label).font(.callout)
        }
    }

    private func discoverFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["Developer", "Projects", "Documents", "Desktop"]
        var found: [String] = []
        for dir in candidates {
            let url = home.appendingPathComponent(dir)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                // Check for subdirectories (project folders)
                if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
                    let subdirs = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                    if subdirs.count > 0 && subdirs.count < 50 {
                        found.append(url.path)
                    }
                }
            }
        }
        discoveredFolders = found
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
