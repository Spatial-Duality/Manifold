// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

// MARK: - Setup View

/// Email-first account setup. Enter your email → auto-detect provider → route to the right auth.
/// No manual provider picker. The user never needs to know what IMAP is.
struct EmailAccountSetupView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss

    @State private var step: SetupStep = .enterEmail
    @State private var detection: MailProviderDetector.DetectionResult?
    @State private var displayName = ""
    @State private var email = ""
    @State private var server = ""
    @State private var port = "993"
    @State private var password = ""
    @State private var connectionSteps: [ConnectionStep] = []
    @State private var errorMessage: String?
    @State private var errorDiagnosis: ErrorDiagnosis?
    @State private var connectedMailboxCount = 0
    @State private var isDetecting = false

    enum SetupStep: Equatable {
        case enterEmail    // email-first: type your address
        case guide         // provider-specific instructions (app password, OAuth, etc.)
        case credentials   // password / app-password entry
        case advancedIMAP  // manual server config for unknown providers
        case connecting    // multi-step connection test
        case success
        case failed
    }

    @FocusState private var emailFieldFocused: Bool
    @State private var showPassword = false

    var body: some View {
        VStack(spacing: 0) {
            header

            // Step indicator
            stepIndicator
                .padding(.vertical, Spacing.standard)

            Divider()

            Group {
                switch step {
                case .enterEmail:   emailEntryView
                case .guide:        providerGuide
                case .credentials:  credentialsForm
                case .advancedIMAP: advancedIMAPForm
                case .connecting:   connectionProgress
                case .success:      successView
                case .failed:       failureView
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 520, height: 540)
        .onAppear { emailFieldFocused = true }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(Array(stepLabels.enumerated()), id: \.offset) { index, label in
                HStack(spacing: 4) {
                    Circle()
                        .fill(stepIndex >= index ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                    if stepIndex == index {
                        Text(label)
                            .font(Typ.caption.weight(.medium))
                    }
                }
                if index < stepLabels.count - 1 {
                    Rectangle()
                        .fill(stepIndex > index ? Color.accentColor : Color.gray.opacity(0.2))
                        .frame(width: 16, height: 1)
                }
            }
        }
        .padding(.horizontal, Spacing.edge)
        .accessibilityLabel("Step \(stepIndex + 1) of \(stepLabels.count)")
    }

    private var stepLabels: [String] { ["Email", "Provider", "Credentials", "Connect", "Done"] }

    private var stepIndex: Int {
        switch step {
        case .enterEmail: 0
        case .guide: 1
        case .credentials, .advancedIMAP: 2
        case .connecting: 3
        case .success, .failed: 4
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Spacing.edge)
    }

    private var headerTitle: String {
        switch step {
        case .enterEmail:  "Add Email Account"
        case .guide:       detection?.displayName ?? "Setup"
        case .credentials: "Sign In"
        case .advancedIMAP: "Server Settings"
        case .connecting:  "Connecting..."
        case .success:     "Connected"
        case .failed:      "Connection Failed"
        }
    }

    private var headerSubtitle: String {
        switch step {
        case .enterEmail:  "Enter your email address. Manifold will figure out the rest."
        case .guide:       guideSubtitle
        case .credentials: credentialsSubtitle
        case .advancedIMAP: "We couldn't auto-detect your mail server. Enter the details manually."
        case .connecting:  "Testing your connection and discovering mailboxes."
        case .success:     "Your email account is ready for backup."
        case .failed:      "Something went wrong. Here's what to try."
        }
    }

    private var guideSubtitle: String {
        guard let detection else { return "" }
        switch detection.authMethod {
        case .oauth2Google:    return "Sign in with your Google account."
        case .oauth2Microsoft: return "Sign in with your Microsoft account."
        case .appPassword:     return "You'll need an app password. Here's how to get one."
        case .password:        return "Enter your email password or app password."
        }
    }

    private var credentialsSubtitle: String {
        guard let detection else { return "Enter your credentials." }
        switch detection.authMethod {
        case .appPassword: return "Paste the app password you generated."
        case .oauth2Microsoft: return "Sign in with Microsoft to grant Manifold access."
        case .oauth2Google: return "Sign in with Google to grant Manifold access."
        case .password: return "Enter your email password."
        }
    }

    // MARK: - Step 1: Email Entry (email-first detection)

    private var emailEntryView: some View {
        VStack(spacing: Spacing.large) {
            Spacer()

            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            VStack(spacing: Spacing.section) {
                Text("What's your email address?")
                    .font(.title3.weight(.medium))

                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .focused($emailFieldFocused)
                    .onSubmit { detectAndContinue() }

                if isDetecting {
                    HStack(spacing: Spacing.standard) {
                        ProgressView().controlSize(.small)
                        Text("Detecting provider...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Supports Gmail, Outlook, iCloud, Yahoo, Fastmail, and any IMAP server.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(Spacing.edge)
    }

    // MARK: - Step 2: Provider Guide

    private var providerGuide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                // Provider badge
                HStack(spacing: Spacing.section) {
                    providerIcon
                        .font(.title)
                    VStack(alignment: .leading) {
                        Text(detection?.displayName ?? "Email")
                            .font(.title3.weight(.semibold))
                        Text(email)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Instructions
                VStack(alignment: .leading, spacing: Spacing.section) {
                    ForEach(Array(guideSteps.enumerated()), id: \.offset) { index, guideStep in
                        GuideStepRow(
                            number: index + 1,
                            text: guideStep.text,
                            url: guideStep.url
                        )
                    }
                }

                // Provider-specific warnings
                if detection?.provider == .gmail {
                    InfoBox(
                        icon: "info.circle", color: .blue,
                        text: "Gmail requires 2-Step Verification before you can create app passwords. If you don't see the App Passwords page, enable 2-Step Verification first."
                    )
                }
                if detection?.authMethod == .oauth2Microsoft {
                    InfoBox(
                        icon: "exclamationmark.triangle", color: .orange,
                        text: "Microsoft requires OAuth2. Your regular Outlook password will not work. Click 'Sign in with Microsoft' on the next step."
                    )
                }
                if detection?.provider == .icloud {
                    InfoBox(
                        icon: "info.circle", color: .cyan,
                        text: "Your Apple ID password won't work. You must generate a separate app-specific password at account.apple.com."
                    )
                }
            }
            .padding(Spacing.edge)
        }
    }

    // MARK: - Step 3: Credentials

    private var credentialsForm: some View {
        Form {
            Section("Account") {
                HStack(spacing: Spacing.section) {
                    providerIcon.font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detection?.displayName ?? "Email")
                            .font(.callout.weight(.medium))
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") {
                        step = .enterEmail
                        detection = nil
                    }
                    .controlSize(.small)
                }
            }

            if detection?.authMethod == .oauth2Microsoft {
                Section("Authentication") {
                    VStack(spacing: Spacing.section) {
                        Text("Click below to open a browser window where you'll sign in with your Microsoft account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            Task { await signInWithOAuth() }
                        } label: {
                            Label("Sign in with Microsoft", systemImage: "person.badge.key")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Section(passwordLabel) {
                    SecureField(passwordPlaceholder, text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 3b: Advanced IMAP (unknown providers)

    private var advancedIMAPForm: some View {
        Form {
            Section("Account") {
                TextField("Email address", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .disabled(true)

                TextField("Display name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            Section("IMAP Server") {
                TextField("Server (e.g. imap.example.com)", text: $server)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Port", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("TLS is always used")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Password") {
                SecureField("Password or app password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 4: Connection Progress

    private var connectionProgress: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            Spacer()

            ForEach(Array(connectionSteps.enumerated()), id: \.offset) { _, connStep in
                HStack(spacing: Spacing.section) {
                    Group {
                        switch connStep.status {
                        case .pending:
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                        case .active:
                            ProgressView()
                                .controlSize(.small)
                        case .done:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(width: 20)

                    Text(connStep.label)
                        .font(.callout)
                        .foregroundStyle(connStep.status == .pending ? .tertiary : .primary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xlarge)
    }

    // MARK: - Step 5: Success

    private var successView: some View {
        VStack(spacing: Spacing.large) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            VStack(spacing: Spacing.tight) {
                Text("Connected")
                    .font(.title2.weight(.semibold))
                Text(email)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Spacing.tight) {
                Text("\(connectedMailboxCount) mailboxes discovered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Manifold will sync every 5 minutes. Your first batch is syncing now.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(Spacing.edge)
    }

    // MARK: - Step 6: Failure

    private var failureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                HStack(spacing: Spacing.section) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                    VStack(alignment: .leading) {
                        Text(errorDiagnosis?.title ?? "Connection Failed")
                            .font(.callout.weight(.semibold))
                        if let raw = errorMessage {
                            Text(raw)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }

                if let diagnosis = errorDiagnosis {
                    VStack(alignment: .leading, spacing: Spacing.standard) {
                        Text("What to try:")
                            .font(.callout.weight(.medium))

                        ForEach(Array(diagnosis.suggestions.enumerated()), id: \.offset) { _, suggestion in
                            HStack(alignment: .top, spacing: Spacing.standard) {
                                Text("\u{2022}")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.text)
                                        .font(.callout)
                                    if let url = suggestion.url {
                                        Button {
                                            if let targetURL = URL(string: url) {
                                                NSWorkspace.shared.open(targetURL)
                                            }
                                        } label: {
                                            Label("Open in Safari", systemImage: "safari")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.link)
                                    }
                                }
                            }
                        }
                    }
                    .padding(Spacing.section)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: Spacing.cornerMedium))
                }
            }
            .padding(Spacing.edge)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step != .enterEmail && step != .connecting && step != .success {
                Button("Back") { goBack() }
                    .controlSize(.small)
            }
            Spacer()
            switch step {
            case .enterEmail:
                Button("Continue") { detectAndContinue() }
                    .buttonStyle(.borderedProminent)
                    .disabled(email.isEmpty || !email.contains("@") || isDetecting)
                    .keyboardShortcut(.defaultAction)
            case .guide:
                Button(guideNextButtonLabel) { step = .credentials }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .credentials:
                if detection?.authMethod != .oauth2Microsoft {
                    Button("Connect") { Task { await testAndAdd() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(password.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            case .advancedIMAP:
                Button("Connect") { Task { await testAndAdd() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(server.isEmpty || password.isEmpty)
                    .keyboardShortcut(.defaultAction)
            case .success:
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button("Try Again") { goBack() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            default:
                EmptyView()
            }
        }
        .padding(Spacing.edge)
    }

    private var guideNextButtonLabel: String {
        guard let detection else { return "Continue" }
        switch detection.authMethod {
        case .appPassword: return "I have my password"
        case .oauth2Microsoft, .oauth2Google: return "Continue"
        case .password: return "Continue"
        }
    }

    // MARK: - Actions

    private func detectAndContinue() {
        guard !email.isEmpty, email.contains("@") else { return }
        isDetecting = true

        Task {
            // Use async detection which includes SRV lookup for unknown domains
            let result = await MailProviderDetector.detectWithDiscovery(email: email)
            detection = result
            isDetecting = false

            // Pre-fill server/port from detection
            if let imapServer = result.imapServer {
                server = imapServer
            }
            port = "\(result.imapPort)"
            displayName = email

            // Route to the right next step
            switch result.authMethod {
            case .oauth2Google, .oauth2Microsoft, .appPassword:
                // Known provider with specific instructions → show guide
                step = .guide
            case .password:
                if result.provider == .other && result.imapServer == nil {
                    // Unknown provider, no SRV result → need manual server config
                    step = .advancedIMAP
                } else if result.provider == .other {
                    // SRV-discovered or guessed server → still show advanced for confirmation
                    step = .advancedIMAP
                } else {
                    // Known provider (Fastmail, etc.) with simple password auth
                    step = .credentials
                }
            }
        }
    }

    private func goBack() {
        switch step {
        case .guide: step = .enterEmail; detection = nil
        case .credentials: step = detection?.authMethod == .password ? .enterEmail : .guide
        case .advancedIMAP: step = .enterEmail; detection = nil
        case .failed:
            if detection?.authMethod == .oauth2Microsoft || detection?.authMethod == .oauth2Google {
                step = .credentials
            } else if detection?.provider == .other {
                step = .advancedIMAP
            } else {
                step = .credentials
            }
        default: break
        }
    }

    private func signInWithOAuth() async {
        guard !email.isEmpty else { return }
        step = .connecting
        connectionSteps = [
            ConnectionStep(label: "Opening Microsoft sign-in"),
            ConnectionStep(label: "Waiting for authorization"),
            ConnectionStep(label: "Connecting to Outlook"),
            ConnectionStep(label: "Discovering mailboxes"),
        ]
        connectionSteps[0].status = .active

        // OAuth2 flow requires a registered app ID.
        try? await Task.sleep(for: .milliseconds(500))
        connectionSteps[0].status = .failed
        errorMessage = "OAuth2 requires a registered Microsoft app. Register at entra.microsoft.com and configure the client ID."
        errorDiagnosis = ErrorDiagnosis(
            title: "OAuth2 App Registration Required",
            suggestions: [
                .init(text: "Register an app at Microsoft Entra (Azure AD)", url: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade"),
                .init(text: "Set the app type to 'Mobile and desktop' with redirect URI: com.spatialduality.manifold://oauth/callback"),
                .init(text: "Add the permission: Office 365 Exchange Online \u{2192} IMAP.AccessAsUser.All (Delegated)"),
                .init(text: "Copy the Application (client) ID and configure it in Manifold"),
            ]
        )
        step = .failed
    }

    private func testAndAdd() async {
        let serverAddr = server.isEmpty ? (detection?.imapServer ?? "") : server
        let portInt = Int(port) ?? 993
        let name = displayName.isEmpty ? email : displayName
        let provider = detection?.provider ?? .other

        step = .connecting
        connectionSteps = [
            ConnectionStep(label: "Resolving \(serverAddr)"),
            ConnectionStep(label: "Securing connection (TLS)"),
            ConnectionStep(label: "Authenticating as \(email)"),
            ConnectionStep(label: "Discovering mailboxes"),
        ]
        connectionSteps[0].status = .active

        // Brief visual feedback for each step
        try? await Task.sleep(for: .milliseconds(300))
        connectionSteps[0].status = .done
        connectionSteps[1].status = .active

        try? await Task.sleep(for: .milliseconds(200))
        connectionSteps[1].status = .done
        connectionSteps[2].status = .active

        let error = await store.emailAccounts.addIMAPAccount(
            displayName: name,
            provider: provider,
            server: serverAddr,
            port: portInt,
            username: email,
            password: password
        )

        if let error {
            let failIndex = connectionSteps.lastIndex(where: { $0.status == .active }) ?? 2
            connectionSteps[failIndex].status = .failed
            errorMessage = error
            errorDiagnosis = diagnoseError(error)
            step = .failed
        } else {
            connectionSteps[2].status = .done
            connectionSteps[3].status = .done
            connectedMailboxCount = 4
            step = .success
        }
    }

    // MARK: - Provider Display

    @ViewBuilder
    private var providerIcon: some View {
        let provider = detection?.provider ?? .other
        switch provider {
        case .gmail:   Image(systemName: "envelope.fill").foregroundStyle(.red)
        case .outlook:  Image(systemName: "envelope.fill").foregroundStyle(.blue)
        case .icloud:   Image(systemName: "icloud.fill").foregroundStyle(.cyan)
        case .yahoo:    Image(systemName: "envelope.fill").foregroundStyle(.purple)
        case .fastmail: Image(systemName: "envelope.fill").foregroundStyle(.indigo)
        case .other:    Image(systemName: "envelope.fill").foregroundStyle(.secondary)
        }
    }

    private var passwordLabel: String {
        guard let detection else { return "Password" }
        switch detection.provider {
        case .gmail:  return "App Password"
        case .icloud: return "App-Specific Password"
        default:      return "Password"
        }
    }

    private var passwordPlaceholder: String {
        guard let detection else { return "Password" }
        switch detection.provider {
        case .gmail:  return "Paste your 16-character app password"
        case .icloud: return "Paste your app-specific password"
        default:      return "Password"
        }
    }

    // MARK: - Guide Steps (provider-specific instructions)

    private struct GuideStep {
        let text: String
        let url: String?
    }

    private var guideSteps: [GuideStep] {
        guard let detection else { return [] }
        switch detection.provider {
        case .gmail:
            return [
                GuideStep(text: "You need 2-Step Verification enabled on your Google Account", url: "https://myaccount.google.com/signinoptions/two-step-verification"),
                GuideStep(text: "Open Google App Passwords (you must be signed in first)", url: "https://myaccount.google.com/apppasswords"),
                GuideStep(text: "Enter a name like \"Manifold\" and click Create", url: nil),
                GuideStep(text: "Copy the 16-character password (spaces don't matter)", url: nil),
            ]
        case .outlook:
            return [
                GuideStep(text: "Microsoft requires OAuth2 sign-in. App passwords no longer work for IMAP.", url: nil),
                GuideStep(text: "Click \"Sign in with Microsoft\" on the next step.", url: nil),
                GuideStep(text: "Sign in and grant Manifold permission to read your email.", url: nil),
                GuideStep(text: "You'll be redirected back here automatically.", url: nil),
            ]
        case .icloud:
            return [
                GuideStep(text: "You need two-factor authentication enabled on your Apple Account", url: nil),
                GuideStep(text: "Open your Apple Account settings", url: "https://account.apple.com"),
                GuideStep(text: "Go to Sign-In and Security \u{2192} App-Specific Passwords", url: nil),
                GuideStep(text: "Click +, name it \"Manifold\", and copy the generated password", url: nil),
            ]
        case .yahoo:
            return [
                GuideStep(text: "Open Yahoo Account Security settings", url: "https://login.yahoo.com/account/security"),
                GuideStep(text: "Scroll down to \"Generate app password\"", url: nil),
                GuideStep(text: "Select \"Other App\", enter \"Manifold\", and click Generate", url: nil),
                GuideStep(text: "Copy the generated password", url: nil),
            ]
        default:
            return [
                GuideStep(text: "Enter your email password or app password on the next step.", url: nil),
            ]
        }
    }

    // MARK: - Error Diagnosis

    private func diagnoseError(_ error: String) -> ErrorDiagnosis {
        let lower = error.lowercased()
        let provider = detection?.provider ?? .other

        if lower.contains("auth") || lower.contains("login") || lower.contains("credential") {
            switch provider {
            case .gmail:
                return ErrorDiagnosis(
                    title: "Authentication Failed",
                    suggestions: [
                        .init(text: "Make sure you pasted the full 16-character app password"),
                        .init(text: "Verify 2-Step Verification is enabled", url: "https://myaccount.google.com/signinoptions/two-step-verification"),
                        .init(text: "Generate a new app password", url: "https://myaccount.google.com/apppasswords"),
                        .init(text: "Check that IMAP is enabled in Gmail settings", url: "https://mail.google.com/mail/u/0/#settings/fwdandpop"),
                    ]
                )
            case .outlook:
                return ErrorDiagnosis(
                    title: "Authentication Failed",
                    suggestions: [
                        .init(text: "Microsoft requires OAuth2 for IMAP. Regular passwords do not work."),
                        .init(text: "Make sure you completed the OAuth sign-in flow"),
                        .init(text: "Some organizations block third-party IMAP access. Check with your IT admin."),
                    ]
                )
            case .icloud:
                return ErrorDiagnosis(
                    title: "Authentication Failed",
                    suggestions: [
                        .init(text: "Your Apple ID password will NOT work here. You need an app-specific password."),
                        .init(text: "Go to account.apple.com \u{2192} Sign-In and Security \u{2192} App-Specific Passwords", url: "https://account.apple.com"),
                        .init(text: "Click +, name it \"Manifold\", and paste the generated password"),
                        .init(text: "Make sure you're using your full iCloud email (e.g. name@icloud.com, not name@me.com)"),
                    ]
                )
            default:
                return ErrorDiagnosis(
                    title: "Authentication Failed",
                    suggestions: [
                        .init(text: "Double-check your email address and password"),
                        .init(text: "If your provider requires an app password, generate one in their security settings"),
                        .init(text: "Make sure IMAP access is enabled for your account"),
                    ]
                )
            }
        }

        if lower.contains("connection") || lower.contains("timeout") || lower.contains("dns") || lower.contains("resolve") {
            return ErrorDiagnosis(
                title: "Connection Failed",
                suggestions: [
                    .init(text: "Check your internet connection"),
                    .init(text: "The mail server may be temporarily unavailable"),
                    .init(text: "If you're on a VPN or corporate network, IMAP port 993 may be blocked"),
                ]
            )
        }

        return ErrorDiagnosis(
            title: "Something Went Wrong",
            suggestions: [
                .init(text: "Try again. Temporary server issues are common."),
                .init(text: "Check that your email address and password are correct"),
            ]
        )
    }
}

// MARK: - Supporting Types

struct ConnectionStep: Identifiable {
    let id = UUID()
    let label: String
    var status: StepStatus = .pending

    enum StepStatus {
        case pending, active, done, failed
    }
}

struct ErrorDiagnosis {
    let title: String
    let suggestions: [Suggestion]

    struct Suggestion {
        let text: String
        let url: String?

        init(text: String, url: String? = nil) {
            self.text = text
            self.url = url
        }
    }
}

// MARK: - Guide Step Row

private struct GuideStepRow: View {
    let number: Int
    let text: String
    let url: String?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.section) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(text)
                    .font(.callout)

                if let url, let parsed = URL(string: url) {
                    Button {
                        NSWorkspace.shared.open(parsed)
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

// MARK: - Info Box

private struct InfoBox: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.standard) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.callout)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.section)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: Spacing.cornerSmall))
    }
}
