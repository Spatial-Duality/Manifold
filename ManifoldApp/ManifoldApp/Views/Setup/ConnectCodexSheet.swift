import SwiftUI
import ManifoldKit

/// Standalone connection sheet for Codex — used from Settings > AI Apps.
/// Two footer buttons only (Cancel + Done). Same 460×420 size as Claude sheet.
struct ConnectCodexSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var addError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Circle().fill(Color.purple).frame(width: 12, height: 12)
                Text("Connect Codex").font(.title3.weight(.semibold))
            }
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                LiveCheckRow(
                    label: "Codex installed",
                    status: store.integrationHealth.codex.cliInstalled,
                    action: { NSWorkspace.shared.open(URL(string: "https://openai.com/index/introducing-codex/")!) },
                    actionLabel: "Install",
                    onRefresh: { await store.integrationHealth.checkCodex() }
                )

                LiveCheckRow(
                    label: "Manifold added",
                    status: store.integrationHealth.codex.mcpAdded,
                    action: {
                        adding = true
                        addError = nil
                        // Use ConfigWriter to add Manifold to Codex config.toml
                        do {
                            let writer = ConfigWriter(
                                binaryPath: ManifoldStore.mcpBinaryPath,
                                homeDir: FileManager.default.homeDirectoryForCurrentUser
                            )
                            try writer.installCodex()
                            Task {
                                await store.integrationHealth.checkCodex()
                                adding = false
                            }
                        } catch {
                            addError = error.localizedDescription
                            adding = false
                        }
                    },
                    actionLabel: adding ? "Adding\u{2026}" : "Add to Codex",
                    onRefresh: { await store.integrationHealth.checkCodex() }
                )

                if let addError {
                    Text(addError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 36)
                }

                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        DetailLine("Binary", value: ManifoldStore.mcpBinaryPath)
                        DetailLine("Config", value: "~/.codex/config.toml")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 380)

            Spacer()

            // Footer — 2 buttons only (same as Claude)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if store.integrationHealth.codex.mcpAdded == .installed {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)
        .task { await store.integrationHealth.checkCodex() }
    }
}
