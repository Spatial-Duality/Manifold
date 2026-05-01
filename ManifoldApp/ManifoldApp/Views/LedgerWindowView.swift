// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LedgerView — the single Manifold window.
//
// Per the 2026-04-29 redesign, the app is organized around four
// task-oriented surfaces:
//
//   • Work   — sessions, approvals, activity, writes, runtime health
//   • Access — share folders with agents
//   • Mail   — share mailboxes with agents
//   • Rules  — manage reusable guardrails
//
// Approvals, session history, runtime health, and activity evidence live
// inside Work rather than separate top-level destinations.

import SwiftUI
import ManifoldKit

struct LedgerView: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var destination: LedgerDestination = .work
    @State private var accessSection: AccessSection = .folders
    @State private var work = WorkModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// 0 = no Tracked Work Block. 1 = TWB present, settled border visible.
    /// Animates between 0 and 1 with .landing motion when TWB transitions.
    @State private var trackedEditIntensity: Double = 0

    /// One-shot pulse trigger. Toggling fires the keyframe animation that
    /// gives the moment its "wow" — a brief saffron glow that breathes
    /// once and decays into the persistent thin border.
    @State private var trackedEditPulseToken: Int = 0

    private var hasActiveWorkBlock: Bool {
        store.dataControlSummary?.activeWorkBlock != nil
    }

    private var activeWorkBlockID: String? {
        store.dataControlSummary?.activeWorkBlock?.id
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            UnifiedLedgerSidebar(
                destination: $destination,
                accessSection: $accessSection,
                work: work
            )
        } detail: {
            // Title ownership: the DETAIL column owns the window title on
            // macOS `NavigationSplitView`. Setting `.navigationTitle` on
            // the sidebar as well causes the sidebar `List` to start
            // drawing from Y=0 (the first rows land behind the traffic
            // lights). So: the sidebar sets no title, the detail sets a
            // single canonical title — `destination.title` — and that's
            // it.
            content
                .frame(minWidth: 720, minHeight: 480)
                .background(workingSurfaceVignette, alignment: .top)
                .overlay(trackedEditFrame)
                .navigationTitle(destination.title)
                .toolbar { LedgerToolbar(destination: destination) }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            columnVisibility = .all
            // Sync intensity to current state so a TWB that was already
            // active when the window opened shows the settled border
            // without firing the pulse.
            trackedEditIntensity = hasActiveWorkBlock ? 1 : 0
        }
        .onChange(of: activeWorkBlockID) { previousID, newID in
            handleTrackedEditTransition(previousID: previousID, newID: newID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowLedgerDestination)) { notification in
            guard let rawValue = notification.object as? String,
                  let requestedDestination = LedgerDestination(rawValue: rawValue) else {
                return
            }
            destination = requestedDestination
            columnVisibility = .all
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .work:
            WorkView(work: work)
        case .access:
            AccessView(selectedSection: $accessSection)
        case .mail:
            MailView()
        case .rules:
            RulesView()
        }
    }

    /// Quiet saffron vignette that fades from a 4% wash at the top of
    /// the detail column to clear by ~220pt. Carries the brand warmth
    /// from the splash + first-run atmosphere into the working surface
    /// without interfering with content readability below.
    private var workingSurfaceVignette: some View {
        LinearGradient(
            stops: [
                .init(color: ManifoldPalette.brand.opacity(0.04), location: 0),
                .init(color: ManifoldPalette.brand.opacity(0.02), location: 0.4),
                .init(color: .clear,                              location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 220)
        .allowsHitTesting(false)
    }

    /// Tracked Work Block visual signature: a saffron border around the
    /// detail column that announces "writes are bounded right now." On
    /// open, a one-shot keyframe pulse breathes the border out and back,
    /// then settles at a thin 1pt brand line that persists for the
    /// duration of the block. This is the moment that says "this is
    /// Manifold's product promise, made visible."
    @ViewBuilder
    private var trackedEditFrame: some View {
        // Persistent settled border — fades in/out via intensity (0 or 1).
        Rectangle()
            .strokeBorder(
                ManifoldPalette.brand.opacity(0.22 * trackedEditIntensity),
                lineWidth: 1
            )
            .allowsHitTesting(false)

        // One-shot pulse — keyframed glow that decays. Triggered by token
        // change so each TWB open replays cleanly. Reduce-motion skips it.
        if !reduceMotion {
            Color.clear
                .keyframeAnimator(
                    initialValue: TrackedEditPulse(width: 0, opacity: 0),
                    trigger: trackedEditPulseToken
                ) { _, value in
                    Rectangle()
                        .strokeBorder(
                            ManifoldPalette.brand.opacity(value.opacity),
                            lineWidth: value.width
                        )
                        .blur(radius: value.width * 0.6)
                } keyframes: { _ in
                    KeyframeTrack(\.width) {
                        LinearKeyframe(0, duration: 0.0)
                        SpringKeyframe(10, duration: 0.5, spring: .smooth)
                        SpringKeyframe(0, duration: 1.4, spring: .snappy)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: 0.0)
                        LinearKeyframe(0.55, duration: 0.4)
                        LinearKeyframe(0.0, duration: 1.5)
                    }
                }
                .allowsHitTesting(false)
        }
    }

    private func handleTrackedEditTransition(previousID: String?, newID: String?) {
        let opening = previousID == nil && newID != nil
        let closing = previousID != nil && newID == nil
        let switching = previousID != nil && newID != nil && previousID != newID

        if opening || switching {
            withAnimation(ManifoldMotion.effective(ManifoldMotion.landing,
                                                   reduceMotion: reduceMotion)) {
                trackedEditIntensity = 1
            }
            // Replay the pulse on every transition that brings a TWB into
            // focus — opening a fresh block OR switching to a new one.
            trackedEditPulseToken &+= 1
        } else if closing {
            withAnimation(ManifoldMotion.effective(ManifoldMotion.landing,
                                                   reduceMotion: reduceMotion)) {
                trackedEditIntensity = 0
            }
        }
    }
}

/// Animatable pulse parameters for the Tracked Work Block magic moment.
private struct TrackedEditPulse: Animatable {
    var width: CGFloat
    var opacity: Double

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(width, opacity) }
        set {
            width = newValue.first
            opacity = newValue.second
        }
    }
}

#Preview("Ledger window — Work") {
    LedgerView()
        .environment(ManifoldStore(runtime: FixtureRuntimeClient(profile: .trackedWork), startServices: false))
        .frame(width: 1080, height: 720)
}
