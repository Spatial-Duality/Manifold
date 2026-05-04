// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// Mirror scope sheet — one-shot copy of one assistant's full scope onto
// the other. Lives in Settings → Advanced because it's a power-user
// reconciliation tool; the day-to-day "keep both AIs in lockstep"
// answer is the auto-mirror toggle next to this button.
//
// Auto-mirror handles future changes; this sheet handles the existing
// divergence the toggle deliberately doesn't touch.

import SwiftUI
import ManifoldKit

struct MirrorScopeSheet: View {
    @Environment(ManifoldStore.self) private var store
    let runtime: any RuntimeClientProtocol
    let onApplied: (String) -> Void
    let onCancel: () -> Void

    @State private var sourceAgent: TargetApp = .cowork
    @State private var targetAgent: TargetApp = .codex
    @State private var plan: ScopeMirrorPlan?
    @State private var loadingPreview = false
    @State private var applying = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "Mirror sources between assistants",
                subtitle: "Make \(displayName(for: targetAgent))'s file scope match \(displayName(for: sourceAgent))'s. Standing folders and per-file decisions are copied; write approvals stay where you set them.",
                systemImage: "arrow.left.arrow.right",
                accent: ManifoldPalette.preview
            )

            Divider()

            Form {
                Section("Direction") {
                    HStack(spacing: Spacing.s3) {
                        Picker("From", selection: $sourceAgent) {
                            ForEach(TargetApp.allCases, id: \.rawValue) { agent in
                                Text(displayName(for: agent)).tag(agent)
                            }
                        }
                        .pickerStyle(.segmented)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Picker("To", selection: $targetAgent) {
                            ForEach(TargetApp.allCases, id: \.rawValue) { agent in
                                Text(displayName(for: agent)).tag(agent)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .labelsHidden()

                    if sourceAgent == targetAgent {
                        Label("Pick two different assistants to mirror between.", systemImage: "info.circle")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Changes") {
                    if loadingPreview {
                        HStack(spacing: Spacing.s2) {
                            ProgressView().scaleEffect(0.6)
                            Text("Computing diff…")
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if sourceAgent == targetAgent {
                        Text("—")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    } else if let plan {
                        if !plan.hasChanges {
                            Label("Already in sync — nothing to mirror.", systemImage: "checkmark.circle")
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                if !plan.sourceIDsToAdd.isEmpty {
                                    diffLine(
                                        symbol: "plus.circle.fill",
                                        tint: ManifoldPalette.active,
                                        text: "Add \(plan.sourceIDsToAdd.count) folder\(plan.sourceIDsToAdd.count == 1 ? "" : "s") to \(displayName(for: plan.targetAgent))"
                                    )
                                }
                                if !plan.sourceIDsToRemove.isEmpty {
                                    diffLine(
                                        symbol: "minus.circle.fill",
                                        tint: .red,
                                        text: "Remove \(plan.sourceIDsToRemove.count) folder\(plan.sourceIDsToRemove.count == 1 ? "" : "s") from \(displayName(for: plan.targetAgent))"
                                    )
                                }
                                if !plan.overridesToWrite.isEmpty {
                                    diffLine(
                                        symbol: "pencil.circle.fill",
                                        tint: ManifoldPalette.preview,
                                        text: "Update \(plan.overridesToWrite.count) per-file decision\(plan.overridesToWrite.count == 1 ? "" : "s")"
                                    )
                                }
                                if !plan.overridesToClear.isEmpty {
                                    diffLine(
                                        symbol: "xmark.circle.fill",
                                        tint: .secondary,
                                        text: "Clear \(plan.overridesToClear.count) per-file decision\(plan.overridesToClear.count == 1 ? "" : "s")"
                                    )
                                }
                            }
                        }
                    } else {
                        Text("Pick a direction to see what would change.")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(ManifoldType.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(ManifoldPalette.bg)

            Divider()

            SettingsSheetFooter {
                Button("Cancel", role: .cancel, action: onCancel)
                    .disabled(applying)
                Button(applying ? "Mirroring…" : "Mirror") {
                    Task { await apply() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .frame(width: 520, height: 460)
        .task(id: previewKey) { await refreshPreview() }
    }

    private var previewKey: String {
        "\(sourceAgent.rawValue)→\(targetAgent.rawValue)"
    }

    private var canApply: Bool {
        guard !applying, !loadingPreview, sourceAgent != targetAgent else { return false }
        return plan?.hasChanges == true
    }

    @ViewBuilder
    private func diffLine(symbol: String, tint: Color, text: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(ManifoldType.caption)
        }
    }

    private func refreshPreview() async {
        guard sourceAgent != targetAgent else {
            plan = nil
            error = nil
            return
        }
        guard let client = runtime as? AppRuntimeClient else {
            error = "Mirror is unavailable in this build."
            plan = nil
            return
        }
        loadingPreview = true
        defer { loadingPreview = false }
        do {
            plan = try await client.previewScopeMirror(from: sourceAgent, to: targetAgent)
            error = nil
        } catch {
            self.error = "Couldn't compute diff: \(error.localizedDescription)"
            plan = nil
        }
    }

    private func apply() async {
        guard let plan, plan.hasChanges else { return }
        guard let client = runtime as? AppRuntimeClient else { return }
        applying = true
        defer { applying = false }
        do {
            try await client.applyScopeMirror(plan)
            // Persist the synced live state into the active Focus's
            // preset rows so the change survives Focus
            // deactivation/reactivation. Without this step, the next
            // setActiveFocus would restore the (now-stale) preset and
            // re-create the divergence the user just resolved.
            await store.snapshotLiveStateToActivePresets()
            let summary = "Mirrored \(displayName(for: plan.sourceAgent)) → \(displayName(for: plan.targetAgent)): "
                + summarize(plan)
            onApplied(summary)
        } catch {
            self.error = "Couldn't apply mirror: \(error.localizedDescription)"
        }
    }

    private func summarize(_ plan: ScopeMirrorPlan) -> String {
        var parts: [String] = []
        if !plan.sourceIDsToAdd.isEmpty {
            parts.append("+\(plan.sourceIDsToAdd.count) folder\(plan.sourceIDsToAdd.count == 1 ? "" : "s")")
        }
        if !plan.sourceIDsToRemove.isEmpty {
            parts.append("-\(plan.sourceIDsToRemove.count) folder\(plan.sourceIDsToRemove.count == 1 ? "" : "s")")
        }
        let overrideTotal = plan.overridesToWrite.count + plan.overridesToClear.count
        if overrideTotal > 0 {
            parts.append("\(overrideTotal) per-file change\(overrideTotal == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "no changes" : parts.joined(separator: ", ") + "."
    }

    private func displayName(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex:  return "Codex"
        }
    }
}
