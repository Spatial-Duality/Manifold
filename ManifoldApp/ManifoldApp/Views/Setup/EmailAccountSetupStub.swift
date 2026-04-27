// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct EmailAccountSetupView: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let provider: EmailProvider
    private let onSaved: () -> Void

    @State private var displayName: String
    @State private var server: String
    @State private var portText: String
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(provider: EmailProvider = .other, onSaved: @escaping () -> Void = {}) {
        self.provider = provider
        self.onSaved = onSaved
        let preset = Self.preset(for: provider)
        _displayName = State(initialValue: preset.displayName)
        _server = State(initialValue: preset.server)
        _portText = State(initialValue: "\(preset.port)")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s4)

            Divider()

            Form {
                Section("Mailbox") {
                    TextField("Display name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Email address", text: $username)
                        .textFieldStyle(.roundedBorder)
                }

                Section("IMAP server") {
                    TextField("Server", text: $server)
                        .textFieldStyle(.roundedBorder)
                    TextField("Port", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                }

                Section("Credential") {
                    SecureField("Password or app password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    submit()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || isSaving)
            }
            .padding(Spacing.s5)
        }
        .frame(width: 500, height: 520)
    }

    private var header: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: provider.systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(providerTint)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Connect \(provider.displayName)")
                    .font(ManifoldType.heading)
                Text("Credentials are stored in your macOS keychain.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var canSubmit: Bool {
        displayName.trimmedForForm != nil &&
        server.trimmedForForm != nil &&
        username.trimmedForForm != nil &&
        password.trimmedForForm != nil &&
        Int(portText) != nil
    }

    private var providerTint: Color {
        switch provider {
        case .gmail:    return .red
        case .outlook:  return ManifoldPalette.claude
        case .icloud:   return .cyan
        case .yahoo:    return ManifoldPalette.codex
        case .fastmail: return .indigo
        case .other:    return .secondary
        }
    }

    private func submit() {
        guard let port = Int(portText) else {
            errorMessage = "Enter a valid IMAP port."
            return
        }

        errorMessage = nil
        isSaving = true

        Task {
            let error = await store.mailAccounts.addIMAPAccount(
                displayName: displayName.trimmedForForm ?? displayName,
                provider: provider,
                server: server.trimmedForForm ?? server,
                port: port,
                username: username.trimmedForForm ?? username,
                password: password.trimmedForForm ?? password
            )
            isSaving = false
            if let error {
                errorMessage = error
            } else {
                dismiss()
                onSaved()
            }
        }
    }

    private static func preset(for provider: EmailProvider) -> (displayName: String, server: String, port: Int) {
        switch provider {
        case .gmail:
            return ("Gmail", "imap.gmail.com", 993)
        case .outlook:
            return ("Outlook", "outlook.office365.com", 993)
        case .icloud:
            return ("iCloud Mail", "imap.mail.me.com", 993)
        case .yahoo:
            return ("Yahoo Mail", "imap.mail.yahoo.com", 993)
        case .fastmail:
            return ("Fastmail", "imap.fastmail.com", 993)
        case .other:
            return ("IMAP mailbox", "", 993)
        }
    }
}

private extension String {
    var trimmedForForm: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
