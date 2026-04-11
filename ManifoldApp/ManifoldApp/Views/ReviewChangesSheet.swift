import SwiftUI
import ManifoldKit
import CryptoKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "review-changes")

/// Sheet shown when finishing a tracked work block.
/// Displays PromoteEngine.dryRun() results: Applied, Conflicts, New, Skipped.
struct ReviewChangesSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss

    let block: WorkBlockRecord

    @State private var applied: [String] = []
    @State private var conflicts: [String] = []
    @State private var newFiles: [String] = []
    @State private var skipped = 0
    @State private var isLoading = true
    @State private var isPromoting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Review Changes")
                    .font(.title2.weight(.semibold))
                Spacer()
                Circle()
                    .fill(block.agent == .codex ? Color.purple : Color.blue)
                    .frame(width: 8, height: 8)
                Text(block.agent == .codex ? "Codex" : "Claude")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.edge)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Analyzing changes\u{2026}")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.section) {
                        // Applied
                        if !applied.isEmpty {
                            changesSection(
                                title: "Applied",
                                subtitle: "Files safely written back to originals",
                                icon: "checkmark.circle.fill",
                                color: .green,
                                files: applied
                            )
                        }

                        // Conflicts
                        if !conflicts.isEmpty {
                            changesSection(
                                title: "Conflicts",
                                subtitle: "Changed by both agent and externally",
                                icon: "exclamationmark.triangle.fill",
                                color: .orange,
                                files: conflicts
                            )
                        }

                        // New files
                        if !newFiles.isEmpty {
                            changesSection(
                                title: "New Files",
                                subtitle: "Created by agent",
                                icon: "plus.circle.fill",
                                color: .blue,
                                files: newFiles
                            )
                        }

                        // Skipped
                        if skipped > 0 {
                            HStack(spacing: Spacing.standard) {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                                Text("\(skipped) files unchanged")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, Spacing.edge)
                        }

                        // Empty state
                        if applied.isEmpty && conflicts.isEmpty && newFiles.isEmpty {
                            VStack(spacing: Spacing.standard) {
                                Image(systemName: "doc.text")
                                    .font(.title)
                                    .foregroundStyle(.tertiary)
                                Text("No changes detected")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.xlarge)
                        }
                    }
                    .padding(.vertical, Spacing.section)
                }
            }

            Divider()

            // Footer
            HStack {
                let total = applied.count + conflicts.count + newFiles.count
                Text("\(total) changed, \(skipped) unchanged")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                if conflicts.isEmpty {
                    Button(isPromoting ? "Promoting\u{2026}" : "Promote All") {
                        promote()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isPromoting || (applied.isEmpty && newFiles.isEmpty))
                } else {
                    Button(isPromoting ? "Promoting\u{2026}" : "Promote (Skip Conflicts)") {
                        promote()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isPromoting)
                }
            }
            .padding(Spacing.edge)
        }
        .frame(minWidth: 520, minHeight: 400)
        .task { await loadDryRun() }
    }

    // MARK: - Section

    private func changesSection(title: String, subtitle: String, icon: String, color: Color, files: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            HStack(spacing: Spacing.standard) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(files.count) \(title)")
                        .font(.callout.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            ForEach(files, id: \.self) { file in
                Text(file)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, Spacing.edge)
    }

    // MARK: - Data

    private func loadDryRun() async {
        guard let grantStore = store.policy.grantStoreRef else {
            isLoading = false
            return
        }

        do {
            let grantSources = try await grantStore.grantSources(grantID: block.grantID)
            guard let grant = try await grantStore.grant(id: block.grantID) else {
                isLoading = false
                return
            }

            var totalSkipped = 0

            // Use dryRun for counts — it's safe (reads only, no writes)
            for gs in grantSources {
                guard let source = try await grantStore.source(id: gs.sourceID) else { continue }
                let mountURL = URL(fileURLWithPath: grant.materializationRoot)
                    .appendingPathComponent(gs.mountName)
                let originalURL = URL(fileURLWithPath: source.originalRootPath)

                guard FileManager.default.fileExists(atPath: mountURL.path) else { continue }

                let (dryApplied, dryConflicts, drySkipped, dryNew) = try PromoteEngine.dryRun(
                    mountURL: mountURL,
                    originalURL: originalURL
                )

                // dryRun returns counts. For file names, compare the manifest
                // against originals to identify which files changed.
                let manifest = try MaterializationEngine.computeManifest(mountURL: mountURL)
                for (relativePath, currentHash) in manifest {
                    let originalFile = originalURL.appendingPathComponent(relativePath)
                    let prefixed = "\(gs.mountName)/\(relativePath)"
                    if !FileManager.default.fileExists(atPath: originalFile.path) {
                        newFiles.append(prefixed)
                    } else {
                        let originalData = try Data(contentsOf: originalFile)
                        let originalDigest = CryptoKit.SHA256.hash(data: originalData)
                        let originalHash = originalDigest.map { String(format: "%02x", $0) }.joined()
                        let baselineURL = mountURL.appendingPathComponent(".manifold-baseline.json")
                        let baselineHash: String?
                        if let baselineData = try? Data(contentsOf: baselineURL),
                           let baselineJSON = try? JSONSerialization.jsonObject(with: baselineData) as? [String: String] {
                            baselineHash = baselineJSON[relativePath]
                        } else {
                            baselineHash = nil
                        }

                        if currentHash != baselineHash {
                            // File was modified in workspace
                            if originalHash != baselineHash {
                                // Original also changed → conflict
                                conflicts.append(prefixed)
                            } else {
                                // Original unchanged → safe to apply
                                applied.append(prefixed)
                            }
                        }
                    }
                }
                totalSkipped += drySkipped
            }

            skipped = totalSkipped
        } catch {
            logger.error("Failed to load dry run: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func promote() {
        isPromoting = true
        Task {
            await store.policy.completeWorkBlock()
            isPromoting = false
            dismiss()
        }
    }
}
