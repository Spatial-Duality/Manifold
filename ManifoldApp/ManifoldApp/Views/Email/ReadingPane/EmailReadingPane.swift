// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct EmailReadingPane: View {
    @Environment(ManifoldStore.self) var store
    @Bindable var selection: EmailSelectionModel

    var body: some View {
        Group {
            if let message = selection.focusedMessage {
                EmailDetailView(message: message, selection: selection)
            } else if selection.isMultiSelecting {
                ContentUnavailableView(
                    "\(selection.selectedMessageIDs.count) Messages Selected",
                    systemImage: "envelope.open",
                    description: Text("Use the toolbar to perform actions on selected messages.")
                )
            } else {
                // 4.3: Warm empty state with keyboard hints
                ContentUnavailableView {
                    Label("Select a Message", systemImage: "envelope")
                } description: {
                    Text("Use \u{2191}\u{2193} to navigate the message list, Space to scroll.")
                }
            }
        }
    }
}

/// Full email detail view with header, body, and attachments.
struct EmailDetailView: View {
    @Environment(ManifoldStore.self) var store
    let message: EmailMessageRecord
    @Bindable var selection: EmailSelectionModel
    @State private var parsed: MIMEParser.ParsedEmail?
    @State private var rawText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ReadingPaneToolbar(message: message, selection: selection)

                EmailHeaderView(message: message)
                    .padding(Spacing.edge)

                Divider()

                // Body content
                if let parsed {
                    if let html = parsed.htmlBody, !html.isEmpty {
                        HTMLEmailView(html: html, attachments: parsed.attachments)
                            .frame(minHeight: 300)
                    } else if let text = parsed.textBody {
                        PlainTextEmailView(text: text)
                            .padding(Spacing.edge)
                    } else {
                        Text("No content")
                            .foregroundStyle(.tertiary)
                            .padding(Spacing.edge)
                    }

                    if !parsed.attachments.isEmpty {
                        Divider()
                        AttachmentBar(attachments: parsed.attachments)
                    }
                } else if let raw = rawText {
                    Text(raw)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(Spacing.edge)
                } else {
                    ProgressView("Loading email...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(Spacing.xlarge)
                }
            }
        }
        .task(id: message.emailID) {
            loadEmail()
        }
    }

    private func loadEmail() {
        parsed = store.emailAccounts.readEmail(emlPath: message.emlPath)
        if parsed == nil, let path = message.emlPath {
            rawText = try? String(contentsOfFile: path, encoding: .utf8)
        }
    }
}
