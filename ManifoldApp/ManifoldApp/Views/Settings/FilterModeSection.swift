// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FilterModeSection — the Sensitive Content Detection block in the Privacy
// Settings pane. Surfaces the Lane C filter-mode plumbing as a user-facing
// preference: global default + optional per-agent override.
//
// Modes:
//   off    Don't scan files for sensitive values
//   warn   Show warnings, files stay accessible
//   block  Block sharing until you explicitly override per-file
//
// Per-agent override is shown only for agents the user has actually
// connected — adaptive, never greyed out.

import SwiftUI
import ManifoldKit

struct FilterModeSection: View {
    @Environment(ManifoldStore.self) private var store
    @State private var globalMode: FilterMode = .off
    @State private var perAgentModes: [TargetApp: FilterMode?] = [:]
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        Section {
            content
        } header: {
            Text("Sensitive Content Detection").font(ManifoldType.title)
        } footer: {
            Text("Choose how Manifold handles files containing flagged values like API keys, credentials, or contact info. Per-agent overrides let you keep one assistant on a stricter setting than the default.")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
        }
        .task { await loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            ProgressView("Loading filter settings…")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: Spacing.section) {
                globalRow
                if !connectedAgents.isEmpty {
                    Divider()
                    perAgentRows
                }
                if let error {
                    Text(error)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Global default

    @ViewBuilder
    private var globalRow: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text("Default mode")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(ManifoldPalette.text2)
            Picker("Default mode", selection: globalModeBinding) {
                Text("Off").tag(FilterMode.off)
                Text("Warn").tag(FilterMode.warn)
                Text("Block").tag(FilterMode.block)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(modeDescription(for: globalMode))
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Per-agent overrides

    @ViewBuilder
    private var perAgentRows: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            Text("Per-agent override")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(ManifoldPalette.text2)
            ForEach(connectedAgents, id: \.rawValue) { agent in
                perAgentRow(agent)
            }
        }
    }

    @ViewBuilder
    private func perAgentRow(_ agent: TargetApp) -> some View {
        let binding = perAgentBinding(for: agent)
        HStack(spacing: Spacing.standard) {
            Text(displayName(for: agent))
                .frame(width: 80, alignment: .leading)
            Picker("\(displayName(for: agent)) override", selection: binding) {
                Text("Inherit (\(globalMode.label))").tag(FilterMode?.none)
                Text("Off").tag(FilterMode?.some(.off))
                Text("Warn").tag(FilterMode?.some(.warn))
                Text("Block").tag(FilterMode?.some(.block))
            }
            .labelsHidden()
            .frame(maxWidth: 240, alignment: .leading)
            Spacer()
        }
    }

    // MARK: - Bindings

    private var globalModeBinding: Binding<FilterMode> {
        Binding(
            get: { globalMode },
            set: { newMode in
                let previous = globalMode
                globalMode = newMode
                Task {
                    do {
                        try await store.runtime.setGlobalFilterMode(newMode)
                        error = nil
                    } catch {
                        await MainActor.run {
                            globalMode = previous
                            self.error = "Couldn't update default mode: \(error.localizedDescription)"
                        }
                    }
                }
            }
        )
    }

    private func perAgentBinding(for agent: TargetApp) -> Binding<FilterMode?> {
        Binding(
            get: { perAgentModes[agent] ?? nil },
            set: { newValue in
                let previous = perAgentModes[agent] ?? nil
                perAgentModes[agent] = newValue
                Task {
                    do {
                        if let mode = newValue {
                            try await store.runtime.setFilterMode(mode, for: agent)
                        } else {
                            try await store.runtime.clearAgentFilterMode(agent)
                        }
                        error = nil
                    } catch {
                        await MainActor.run {
                            perAgentModes[agent] = previous
                            self.error = "Couldn't update \(displayName(for: agent)) override: \(error.localizedDescription)"
                        }
                    }
                }
            }
        )
    }

    // MARK: - Loading

    private func loadIfNeeded() async {
        guard !loaded else { return }
        do {
            globalMode = try await store.runtime.globalFilterMode()
            for agent in connectedAgents {
                let effective = try await store.runtime.filterMode(for: agent)
                // We can't tell from `filterMode(for:)` alone whether the
                // value is an explicit per-agent override or inherited from
                // the global default. The honest read: if the effective
                // matches the global, treat it as inherited (nil binding).
                // The user can still set an explicit override that happens
                // to match the global — it just looks like "Inherit" in the
                // UI, which is fine for v1.
                perAgentModes[agent] = (effective == globalMode) ? nil : effective
            }
            loaded = true
            error = nil
        } catch {
            self.error = "Couldn't load filter settings: \(error.localizedDescription)"
            loaded = true // surface the error UI
        }
    }

    // MARK: - Helpers

    private var connectedAgents: [TargetApp] {
        store.connectedAgents.compactMap { TargetApp(rawValue: $0) }
    }

    private func displayName(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex:  return "Codex"
        }
    }

    private func modeDescription(for mode: FilterMode) -> String {
        switch mode {
        case .off:
            return "Don't scan files for sensitive values. Fastest; no warnings or blocks."
        case .warn:
            return "Show a warning badge on files with flagged values. Files stay accessible to AIs."
        case .block:
            return "Hide files with flagged values from AIs until you explicitly override sharing per file."
        }
    }
}

private extension FilterMode {
    var label: String {
        switch self {
        case .off:   return "Off"
        case .warn:  return "Warn"
        case .block: return "Block"
        }
    }
}
