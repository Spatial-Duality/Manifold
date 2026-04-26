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
                    Text(store.connectedAgents.isEmpty
                         ? "none"
                         : store.connectedAgents.joined(separator: ", "))
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reconnect runtime") {
                    Task {
                        store.registerAgent()
                        await store.refreshAll(force: true)
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
                    Button("Create Diagnostic Report…") {
                        diagnosticsPreviewPresented = true
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("diagnostics.createReport")

                    Button("Reveal Diagnostics in Finder") {
                        store.diagnostics.revealDiagnosticsInFinder()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("diagnostics.revealInFinder")

                    Button("Delete Local Diagnostics", role: .destructive) {
                        deleteConfirmationPresented = true
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("diagnostics.delete")
                }
                Text("Reports describe app health and runtime registration outcomes. They never include file paths, prompts, email contents, or governed data.")
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
                Text("Landing here is a self-selection into engineering diagnostics. Plain-language controls live in the other panes; this one exists so you can see exactly what Manifold is doing on your Mac.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $diagnosticsPreviewPresented) {
            DiagnosticReportPreviewSheet(
                json: store.diagnostics.reportPreviewJSON(),
                canSend: store.diagnostics.canSendReports,
                onSave: { saveSheetPresented = true },
                onSend: {
                    // Phase C wires the actual transport. For Phase A, the
                    // button is hidden when canSend is false.
                },
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
    let canSend: Bool
    let onSave: () -> Void
    let onSend: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Diagnostic Report")
                .font(ManifoldType.heading)
            Text("Preview the exact JSON that would be saved or sent. Nothing leaves your Mac unless you press Send.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s2)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .accessibilityIdentifier("diagnostics.preview")

            HStack {
                Spacer()
                Button("Save to File…", action: onSave)
                    .accessibilityIdentifier("diagnostics.saveToFile")
                if canSend {
                    Button("Send to Spatial Duality", action: onSend)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("diagnostics.send")
                }
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.s4)
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
