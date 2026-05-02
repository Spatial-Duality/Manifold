// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AdvancedSettingsPane — the Stage-3 "destination for engineering-flavored
// controls" pane. Landing here is a self-selection into diagnostics;
// normal users shouldn't need to visit this.
//
// Collects database paths, MCP binary location, runtime connection
// diagnostics, and maintenance actions (GC, integrity check) that used
// to live under Storage.

import SwiftUI
import ManifoldKit

struct AdvancedSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var gcResult: Int?
    @State private var integrityResult: Bool?
    @State private var diagnosticsPreviewPresented = false
    @State private var deleteConfirmationPresented = false
    @State private var saveSheetPresented = false

    private var connectedAgentsLabel: String {
        let agents = store.connectedAgents.compactMap(TargetApp.init(rawValue:))
        guard !agents.isEmpty else { return "none" }
        return agents.map(AgentMeta.label).joined(separator: ", ")
    }

    var body: some View {
        Form {
            Section("Runtime") {
                LabeledContent("Status") {
                    HStack(spacing: Spacing.s1) {
                        AgentStatusDot(
                            status: store.isRuntimeConnected ? .active : .offline,
                            size: 7, pulses: false
                        )
                        Text(store.isRuntimeConnected ? "Connected" : "Not connected")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Connected agents") {
                    Text(connectedAgentsLabel)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Restart runtime helper") {
                    Task {
                        await store.restartRuntimeHelper()
                    }
                }
                .controlSize(.small)
            }

            Section("Paths") {
                LabeledContent("Database") {
                    PathLabel(ManifoldStore.storeURL.path)
                }
                LabeledContent("MCP binary") {
                    PathLabel(ManifoldStore.mcpBinaryPath)
                }
                LabeledContent("Launch agent") {
                    PathLabel(ManifoldStore.launchAgentPlistURL.path)
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
                            .foregroundStyle(ok ? ManifoldPalette.active : ManifoldPalette.attention)
                    }
                }
            }

            Section("Diagnostics") {
                HStack {
                    Button("Create diagnostic report…") {
                        diagnosticsPreviewPresented = true
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("diagnostics.createReport")

                    Button("Reveal diagnostics in Finder") {
                        store.diagnostics.revealDiagnosticsInFinder()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("diagnostics.revealInFinder")

                    Button("Delete local diagnostics", role: .destructive) {
                        deleteConfirmationPresented = true
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("diagnostics.delete")
                }
                Text("Reports describe app health and runtime registration outcomes. You can preview and save the JSON; Manifold does not upload it. Reports never include file paths, prompts, email contents, or governed data.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let receipt = store.diagnostics.lastReceiptID {
                    LabeledContent("Last sent receipt") {
                        Text(receipt)
                            .font(ManifoldType.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Text("Advanced contains runtime paths and diagnostics for troubleshooting. Everyday controls live in the other Settings panes.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $diagnosticsPreviewPresented) {
            DiagnosticReportPreviewSheet(
                json: store.diagnostics.reportPreviewJSON(),
                onSave: { saveSheetPresented = true },
                onClose: { diagnosticsPreviewPresented = false }
            )
            .frame(minWidth: 560, minHeight: 420)
        }
        .fileExporter(
            isPresented: $saveSheetPresented,
            document: DiagnosticReportDocument(json: store.diagnostics.reportPreviewJSON()),
            contentType: .json,
            defaultFilename: "manifold-diagnostic-report.json"
        ) { _ in }
        .confirmationDialog(
            "Delete all local diagnostics?",
            isPresented: $deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                try? store.diagnostics.deleteLocalDiagnostics()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes the diagnostics directory on this Mac. Consent state is unchanged. Sparkle and runtime behavior are unaffected.")
        }
    }
}

// MARK: - Preview sheet

private struct DiagnosticReportPreviewSheet: View {
    let json: String
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "Diagnostic Report",
                subtitle: "Preview the JSON that can be saved. Nothing leaves your Mac from this screen.",
                systemImage: "doc.text.magnifyingglass",
                accent: ManifoldPalette.selection
            )

            Divider()

            ScrollView {
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s2)
            }
            .background(ManifoldPalette.surface2)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
            )
            .padding(Spacing.s5)
            .accessibilityIdentifier("diagnostics.preview")

            Divider()

            SettingsSheetFooter {
                Button("Save to file…", action: onSave)
                    .accessibilityIdentifier("diagnostics.saveToFile")

                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

// MARK: - Document

import UniformTypeIdentifiers

private struct DiagnosticReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let json: String

    init(json: String) { self.json = json }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.json = text
        } else {
            self.json = "{}"
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(json.utf8))
    }
}

// PathLabel promoted to Components/Primitives/PathLabel.swift.
