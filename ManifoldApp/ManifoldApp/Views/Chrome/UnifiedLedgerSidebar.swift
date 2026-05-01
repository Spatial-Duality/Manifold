// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct UnifiedLedgerSidebar: View {
    @Binding var destination: LedgerDestination
    @Binding var accessSection: AccessSection
    let work: WorkModel

    var body: some View {
        VStack(spacing: 0) {
            SidebarBrandHeader()
            SpaceSwitcher(selection: $destination)
            Divider()

            // Navigator content fills the available vertical space so
            // the Settings button below stays pinned to the bottom.
            Group {
                switch destination {
                case .work:
                    WorkNavigator(work: work)
                case .access:
                    AccessNavigator(selection: $accessSection)
                case .mail:
                    MailNavigator()
                case .rules:
                    RulesNavigator()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()
            SidebarSettingsButton()
        }
        .navigationSplitViewColumnWidth(min: 248, ideal: 284, max: 340)
        .accessibilityIdentifier("ledger.sidebar")
    }
}

/// Centered identity stack at the top of the sidebar — mark, wordmark,
/// and a small status badge. Doubles as a quick session toggle (clicking
/// runs the most useful action for the current state).
///
/// Layout (top to bottom):
///   {|}            ← brand mark, whole-coloured by state
///   Manifold       ← wordmark, always neutral text colour (identity)
///   STATUS         ← small uppercase status badge in state colour
///
/// State map:
///   - Disconnected → red       — runtime unreachable; click restarts
///   - Warning      → orange    — pending approvals or paused agents;
///                                click navigates to Work
///   - Idle         → soft grey — runtime up, nothing running; click
///                                builds + activates a default session
///   - Ready        → amber     — preload staged; click activates
///   - Active       → green     — session running; click ends
///   - Writing      → green     — session running + writing files
///
/// No motion — pulsing reads as "needs action" in Apple's design
/// language. State communication is colour + text only.
private struct SidebarBrandHeader: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    /// Brand mark scales alongside the wordmark text style. Keeps the
    /// mark + wordmark + status badge in proportion under any Dynamic
    /// Type size. Apple HIG: visual elements adjacent to text should
    /// scale together via @ScaledMetric.
    /// https://developer.apple.com/documentation/swiftui/scaledmetric
    @ScaledMetric(relativeTo: .body) private var markSize: CGFloat = 36

    private enum SessionState {
        case disconnected
        case warning
        case idle
        case prepared
        case active
        case trackedEdit
    }

    private var sessionState: SessionState {
        if !store.isRuntimeConnected { return .disconnected }

        // Active states take precedence — session running is the
        // primary signal even if approvals are also pending.
        if let block = store.dataControlSummary?.activeWorkBlock,
           block.modifiedFileCount > 0 || block.newFileCount > 0 {
            return .trackedEdit
        }
        if let session = store.activeSession {
            return session.isTrackedEdit ? .trackedEdit : .active
        }

        // Warning surfaces only outside of an active session — inside
        // one, the session state is more important to communicate.
        let pendingCount = store.dataControlSummary?.pendingApprovalCount
            ?? store.governance.pendingApprovals.count
        if pendingCount > 0 { return .warning }
        if store.dataControlSummary?.agents.allSatisfy(\.isPaused) == true {
            return .warning
        }

        if store.sessionWorkbench.preload != nil { return .prepared }
        return .idle
    }

    /// Colour applied to the whole {|} mark and the status badge text.
    /// The "Manifold" wordmark stays neutral to preserve brand identity.
    private var stateColor: Color {
        switch sessionState {
        case .disconnected:         return ManifoldPalette.danger     // red
        case .warning:              return ManifoldPalette.attention  // orange
        case .idle:                 return ManifoldPalette.text2      // soft grey
        case .prepared:             return ManifoldPalette.preview    // amber
        case .active, .trackedEdit: return ManifoldPalette.active     // green
        }
    }

    private var statusLabel: String {
        switch sessionState {
        case .disconnected: return "Disconnected"
        case .warning:      return "Warning"
        case .idle:         return "Idle"
        case .prepared:     return "Ready"
        case .active:       return "Active"
        case .trackedEdit:  return "Writing"
        }
    }

    private var actionLabel: String {
        switch sessionState {
        case .disconnected: return "Reconnect runtime"
        case .warning:      return "Open Work"
        case .idle:         return "Start session"
        case .prepared:     return "Activate session"
        case .active:       return "End session"
        case .trackedEdit:  return "End session"
        }
    }

    var body: some View {
        Button(action: handleAction) {
            VStack(spacing: 6) {
                BrandMark(placement: .display, color: stateColor)
                    .frame(width: markSize, height: markSize)

                Text("Manifold")
                    .font(ManifoldType.wordmark)
                    .tracking(-0.4)
                    .foregroundStyle(ManifoldPalette.text)

                Text(statusLabel)
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(stateColor)
                    .accessibilityIdentifier("ledger.sidebar.brand.state")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s3)
            .padding(.horizontal, Spacing.s3)
            .background {
                // Hover swaps the flat surface3 fill for brand-tinted
                // Liquid Glass — a brief saffron warmth on the navigation
                // chrome that says "this *is* Manifold." Honest brand
                // presence: it only appears when you're actually
                // interacting with the brand button.
                if isHovering {
                    RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                        .fill(.clear)
                        .liquidGlassBrand(
                            in: RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                        )
                } else {
                    Color.clear
                }
            }
            .contentShape(Rectangle())
            .animation(ManifoldMotion.effective(ManifoldMotion.micro,
                                                reduceMotion: reduceMotion),
                       value: stateColor)
            .animation(ManifoldMotion.effective(ManifoldMotion.micro,
                                                reduceMotion: reduceMotion),
                       value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(actionLabel)
        .padding(.horizontal, Spacing.s2)
        .padding(.top, Spacing.s3)
        .padding(.bottom, Spacing.s2)
        .accessibilityIdentifier("ledger.sidebar.brand")
        .accessibilityLabel("Manifold — \(statusLabel)")
        .accessibilityHint(actionLabel)
        .accessibilityAddTraits(.isButton)
    }

    private func handleAction() {
        switch sessionState {
        case .disconnected:
            // Relaunch the XPC runtime helper — mirrors the
            // "Restart Runtime" button in WorkView.
            Task { await store.restartRuntimeHelper() }
        case .warning:
            // Navigate to Work where approvals and agent controls live.
            NotificationCenter.default.post(name: .manifoldShowWork, object: nil)
        case .idle:
            // Build preload then activate immediately.
            store.beginSessionPreload(
                agent: store.defaultSessionAgent,
                baseMode: .buildOnDefault
            )
            Task { await store.activateSessionPreload() }
        case .prepared:
            Task { await store.activateSessionPreload() }
        case .active, .trackedEdit:
            Task { await store.endSession() }
        }
    }
}

/// Gear icon + "Settings" label pinned to the bottom of the sidebar.
/// Pattern lifted from desktop apps (Linear, Codex, Notion) where the
/// settings entry is a quiet always-visible row at the foot of the
/// navigation column. Uses SettingsLink so the platform routes it to
/// the SettingsScene defined in ManifoldApp.swift, including the
/// standard ⌘, shortcut.
private struct SidebarSettingsButton: View {
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsLink {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ManifoldPalette.text2)
                    .frame(width: 18, alignment: .center)

                Text("Settings")
                    .font(ManifoldType.body)
                    .foregroundStyle(ManifoldPalette.text)

                Spacer(minLength: 0)

                Text("⌘,")
                    .font(ManifoldType.caption.monospacedDigit())
                    .foregroundStyle(ManifoldPalette.text3)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r2, style: .continuous)
                    .fill(isHovering
                          ? ManifoldPalette.surface3.opacity(0.7)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, Spacing.s2)
        .animation(ManifoldMotion.effective(ManifoldMotion.micro,
                                            reduceMotion: reduceMotion),
                   value: isHovering)
        .accessibilityIdentifier("ledger.sidebar.settings")
        .accessibilityLabel("Settings")
        .accessibilityHint("Open Manifold settings")
    }
}
