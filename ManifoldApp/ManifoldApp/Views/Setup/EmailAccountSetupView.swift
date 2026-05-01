// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AuthenticationServices
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
    @State private var oauthSession: ASWebAuthenticationSession?
    @State private var trustAccepted = false

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

            Divider()

            Form {
                Section("Mailbox") {
                    TextField("Display name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings.mail.account.displayName")
                    TextField("Email address", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings.mail.account.username")
                }

                Section("IMAP server") {
                    if isOAuthProvider {
                        LabeledContent("Server", value: server)
                        LabeledContent("Port", value: portText)
                    } else {
                        TextField("Server", text: $server)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.mail.account.server")
                        TextField("Port", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 96)
                            .accessibilityIdentifier("settings.mail.account.port")
                    }
                }

                Section("Provider steps") {
                    ForEach(providerProfile.setupInstructions.steps, id: \.self) { step in
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if isOAuthProvider {
                    Section("Microsoft sign-in") {
                        if let oauthUnavailableMessage {
                            Text(oauthUnavailableMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Manifold opens Microsoft sign-in in your browser and stores the returned IMAP OAuth token in Keychain after validation.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Section("Credential") {
                        SecureField(credentialPlaceholder, text: $password)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.mail.account.password")
                    }
                }

                Section("Trust") {
                    Text(providerProfile.setupInstructions.trustCopy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("I understand Manifold will only read and back up mail locally.", isOn: $trustAccepted)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("settings.mail.account.trustAccepted")
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
            .background(ManifoldPalette.bg)

            Divider()

            SettingsSheetFooter {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

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
                .accessibilityIdentifier("settings.mail.account.connect")
            }
        }
        .frame(width: 500, height: 640)
    }

    private var header: some View {
        SettingsSheetHeader(
            title: "Connect \(provider.displayName)",
            subtitle: providerProfile.setupInstructions.title,
            systemImage: provider.systemImage,
            accent: providerTint
        )
        .accessibilityIdentifier("settings.mail.account.header")
    }

    private var providerProfile: MailProviderProfile {
        MailProviderCatalog.profile(for: provider)
    }

    private var credentialPlaceholder: String {
        switch providerProfile.defaultAuthMethod {
        case .appPasswordIMAP:
            "App password"
        case .oauthIMAPXOAUTH2:
            "OAuth handled by provider sign-in"
        case .manualPasswordIMAP:
            "Password or app password"
        }
    }

    private var isOAuthProvider: Bool {
        if case .oauthIMAPXOAUTH2 = providerProfile.defaultAuthMethod {
            true
        } else {
            false
        }
    }

    private var oauthUnavailableMessage: String? {
        guard isOAuthProvider else { return nil }
        let config = LocalAuthConfig.load()
        guard config.isMicrosoftOAuthConfigured else {
            return "This build does not include Microsoft OAuth configuration. Developer and fork builds must configure MicrosoftClientID and a redirect URI locally."
        }
        return nil
    }

    private var canSubmit: Bool {
        guard displayName.trimmedForForm != nil,
              server.trimmedForForm != nil,
              username.trimmedForForm != nil,
              Int(portText) != nil,
              trustAccepted else {
            return false
        }
        if isOAuthProvider {
            return oauthUnavailableMessage == nil
        }
        return password.trimmedForForm != nil
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
        if isOAuthProvider {
            submitOAuth()
            return
        }

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

    private func submitOAuth() {
        guard let port = Int(portText),
              let username = username.trimmedForForm,
              let displayName = displayName.trimmedForForm,
              let server = server.trimmedForForm else {
            errorMessage = "Enter a valid email address."
            return
        }

        let config = LocalAuthConfig.load()
        let client = MicrosoftOAuthClient(config: config)
        let request: MicrosoftOAuthAuthorizationRequest
        do {
            request = try client.makeAuthorizationRequest(emailAddress: username)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        errorMessage = nil
        isSaving = true
        let session = ASWebAuthenticationSession(
            url: request.authorizationURL,
            callbackURLScheme: request.callbackScheme
        ) { callbackURL, error in
            Task { @MainActor in
                if let error {
                    errorMessage = error.localizedDescription
                    isSaving = false
                    oauthSession = nil
                    return
                }
                guard let callbackURL else {
                    errorMessage = "Microsoft sign-in did not return a callback."
                    isSaving = false
                    oauthSession = nil
                    return
                }
                do {
                    let tokenSet = try await client.tokenSet(fromCallbackURL: callbackURL, matching: request)
                    let addError = await store.mailAccounts.addOAuthIMAPAccount(
                        displayName: displayName,
                        provider: provider,
                        server: server,
                        port: port,
                        username: username,
                        tokenSet: tokenSet
                    )
                    isSaving = false
                    oauthSession = nil
                    if let addError {
                        errorMessage = addError
                    } else {
                        dismiss()
                        onSaved()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    isSaving = false
                    oauthSession = nil
                }
            }
        }
        session.prefersEphemeralWebBrowserSession = false
        oauthSession = session
        if !session.start() {
            errorMessage = "Microsoft sign-in could not be started."
            isSaving = false
            oauthSession = nil
        }
    }

    private static func preset(for provider: EmailProvider) -> (displayName: String, server: String, port: Int) {
        let profile = MailProviderCatalog.profile(for: provider)
        return (profile.displayName, profile.imapEndpoint?.host ?? "", profile.imapEndpoint?.port ?? 993)
    }
}

private extension String {
    var trimmedForForm: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
