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
    @State private var connectionDetailsExpanded: Bool
    @State private var appliedOtherProvider: EmailProvider?

    init(provider: EmailProvider = .other, onSaved: @escaping () -> Void = {}) {
        self.provider = provider
        self.onSaved = onSaved
        let preset = Self.preset(for: provider)
        _displayName = State(initialValue: preset.displayName)
        _server = State(initialValue: preset.server)
        _portText = State(initialValue: "\(preset.port)")
        // Collapsed by default: unknown domains resolve their server via
        // discovery on connect, so manual entry is the fallback, not the norm.
        _connectionDetailsExpanded = State(initialValue: false)
    }

    var body: some View {
        Form {
            accountSection
            signInSection
            helpSection
            connectionDetailsSection
            trustSection

            if let errorMessage {
                Section("Status") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(guide.validationHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connect \(guide.displayLabel)")
        .accessibilityIdentifier("settings.mail.account.header")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    submit()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(guide.primaryActionTitle)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || isSaving)
                .accessibilityIdentifier("settings.mail.account.connect")
            }
        }
        .onAppear {
            applyOtherProviderHintIfNeeded()
        }
        .onChange(of: username) { _, _ in
            applyOtherProviderHintIfNeeded()
        }
        .frame(width: 540, height: 640)
    }

    private var accountSection: some View {
        Section("Account") {
            TextField("Display name", text: $displayName)
                .accessibilityIdentifier("settings.mail.account.displayName")
            TextField("Email address", text: $username)
                .accessibilityIdentifier("settings.mail.account.username")
        }
    }

    @ViewBuilder
    private var signInSection: some View {
        if isOAuthProvider {
            Section("Sign-in") {
                if let oauthUnavailableMessage {
                    Text(oauthUnavailableMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(guide.validationHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Manifold opens Microsoft sign-in and stores the returned IMAP OAuth token in Keychain after validation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(guide.primaryActionTitle) {
                        submit()
                    }
                    .disabled(!canSubmit || isSaving)
                    .accessibilityIdentifier("settings.mail.account.oauth.signIn")
                }
            }
        } else {
            Section("Sign-in") {
                SecureField(guide.credentialLabel, text: $password)
                    .accessibilityIdentifier("settings.mail.account.password")
            }
        }
    }

    private var helpSection: some View {
        Section("Help") {
            ForEach(guide.steps, id: \.self) { step in
                Text(step)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(guide.links) { link in
                Link(link.title, destination: link.url)
            }

            DisclosureGroup("Common blockers") {
                ForEach(guide.blockers, id: \.self) { blocker in
                    Text(blocker)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("settings.mail.account.blockers")
        }
    }

    private var connectionDetailsSection: some View {
        Section("Connection Details") {
            DisclosureGroup("IMAP", isExpanded: $connectionDetailsExpanded) {
                if isOAuthProvider {
                    LabeledContent("Server", value: server)
                    LabeledContent("Port", value: portText)
                } else {
                    TextField(
                        provider == .other ? "Automatic (leave blank to detect)" : "Server",
                        text: $server
                    )
                    .accessibilityIdentifier("settings.mail.account.server")
                    TextField("Port", text: $portText)
                        .frame(width: 96)
                        .accessibilityIdentifier("settings.mail.account.port")
                }
            }
        }
    }

    private var trustSection: some View {
        Section("Trust") {
            Text("Manifold connects directly from this Mac, stores credentials in Keychain, and keeps the mail backup local.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("It will not send, delete, move, archive, or mark mail as read. AI access stays off until you explicitly grant it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("I understand this is a local, read-only backup.", isOn: $trustAccepted)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("settings.mail.account.trustAccepted")
        }
    }

    private var effectiveProvider: EmailProvider {
        if provider == .other,
           let detected = MailProviderOnboardingGuide.detectedOtherProvider(emailAddress: username) {
            return detected
        }
        return provider
    }

    private var guide: MailProviderOnboardingGuide {
        MailProviderOnboardingGuide.guide(for: provider, emailAddress: username)
    }

    private var providerProfile: MailProviderProfile {
        MailProviderCatalog.profile(for: effectiveProvider)
    }

    private var isOAuthProvider: Bool {
        if case .oauthIMAPXOAUTH2 = providerProfile.defaultAuthMethod {
            return true
        }
        return false
    }

    private static let cachedAuthConfig = LocalAuthConfig.load()

    private var oauthUnavailableMessage: String? {
        guard isOAuthProvider else { return nil }
        guard Self.cachedAuthConfig.isMicrosoftOAuthConfigured else {
            return "This build does not include Microsoft OAuth configuration. Developer and fork builds must configure MicrosoftClientID and a redirect URI locally."
        }
        return nil
    }

    private var canSubmit: Bool {
        guard displayName.trimmedForForm != nil,
              username.trimmedForForm != nil,
              Int(portText) != nil,
              trustAccepted else {
            return false
        }
        if isOAuthProvider {
            return server.trimmedForForm != nil && oauthUnavailableMessage == nil
        }
        guard password.trimmedForForm != nil else { return false }
        // A blank server is allowed for unknown domains: it resolves through
        // the discovery chain when the user connects.
        return server.trimmedForForm != nil || canDiscoverServer
    }

    private var canDiscoverServer: Bool {
        guard provider == .other, let address = username.trimmedForForm else { return false }
        let parts = address.components(separatedBy: "@")
        return parts.count == 2 && !(parts.last?.isEmpty ?? true)
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

        let providerToStore = effectiveProvider
        errorMessage = nil
        isSaving = true

        Task {
            var resolvedServer = server.trimmedForForm
            var resolvedPort = port

            if resolvedServer == nil {
                // One-field path: resolve the endpoint from the address domain
                // (domain autoconfig → ISPDB → DNS SRV; TLS-on-connect only).
                guard let domain = username.trimmedForForm?
                    .components(separatedBy: "@").last?.lowercased(), !domain.isEmpty else {
                    errorMessage = "Enter a valid email address."
                    isSaving = false
                    return
                }
                guard let discovered = await MailDiscoveryService.discover(domain: domain) else {
                    errorMessage = "Couldn't find mail server settings for \(domain). Enter the IMAP server below."
                    connectionDetailsExpanded = true
                    isSaving = false
                    return
                }
                resolvedServer = discovered.host
                resolvedPort = Int(discovered.port)
                server = discovered.host
                portText = "\(discovered.port)"
            }

            let error = await store.mailAccounts.addIMAPAccount(
                displayName: displayName.trimmedForForm ?? displayName,
                provider: providerToStore,
                server: resolvedServer ?? server,
                port: resolvedPort,
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

        let client = MicrosoftOAuthClient(config: Self.cachedAuthConfig)
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
                    errorMessage = "Microsoft sign-in didn't complete. Try again or check your network connection."
                    isSaving = false
                    oauthSession = nil
                    return
                }
                do {
                    let tokenSet = try await client.tokenSet(fromCallbackURL: callbackURL, matching: request)
                    let addError = await store.mailAccounts.addOAuthIMAPAccount(
                        displayName: displayName,
                        provider: effectiveProvider,
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
            errorMessage = "Couldn't start Microsoft sign-in. Try again."
            isSaving = false
            oauthSession = nil
        }
    }

    private func applyOtherProviderHintIfNeeded() {
        guard provider == .other else { return }

        guard let detected = MailProviderOnboardingGuide.detectedOtherProvider(emailAddress: username),
              let endpoint = MailProviderCatalog.profile(for: detected).imapEndpoint else {
            if let previous = appliedOtherProvider,
               let previousEndpoint = MailProviderCatalog.profile(for: previous).imapEndpoint,
               server == previousEndpoint.host {
                server = ""
                portText = "993"
                displayName = "Other IMAP"
            }
            appliedOtherProvider = nil
            return
        }

        if appliedOtherProvider != detected || server.trimmedForForm == nil {
            server = endpoint.host
            portText = "\(endpoint.port)"
            displayName = MailProviderCatalog.profile(for: detected).displayName
            appliedOtherProvider = detected
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
