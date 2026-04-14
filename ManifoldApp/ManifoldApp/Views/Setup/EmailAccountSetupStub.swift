// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EmailAccountSetupStub — minimal placeholder for the mailbox setup flow
// until it is rebuilt around the new Mail surface.
//
// The Stage-11 plan deletes the legacy Library/EmailAccountSetupView.swift
// (23-file Email subtree). Two kept sheets (AddMailAccountSheet,
// MailSettingsPane) still reference a setup view by name; this stub
// compiles that reference, and the full OAuth/IMAP flow is restored in
// a dedicated mail-onboarding pass.

import SwiftUI
import ManifoldKit

struct EmailAccountSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.s4) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(ManifoldPalette.codex)
            Text("Mailbox setup is being rebuilt")
                .font(ManifoldType.heading)
            Text("The provider picker, OAuth flow, and IMAP form that used to live here are folded into the Stage-11 Mail surface. In the meantime, mailbox setup is available via the Mail menu bar action once the new pipeline lands.")
                .font(ManifoldType.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, Spacing.s2)
        }
        .padding(Spacing.s8)
        .frame(width: 480, height: 360)
    }
}
