// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Synology-style inline preview that expands below a clicked table row.
/// Not a separate reading pane column. Shows subject, from/to, body preview,
/// attachments, and governance actions (Share with Agent, Open, Close).
struct InlineMessagePreview: View {
    @Environment(ManifoldStore.self) var store
    let message: EmailMessageRecord
    let focusedAgent: TargetApp
    let onClose: () -> Void

    @State private var parsed: MIMEParser.ParsedEmail?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: subject + action buttons
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.subject)
                        .font(Typ.heading)
                    Text("From: \(message.sender) \u{00B7} \(formattedDate)")
                        .font(Typ.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    // Share button or shared badge
                    Button("Share with \(focusedAgent == .codex ? "Codex" : "Claude")", systemImage: "shield") {
                        Task {
                            await store.emailAccounts.shareEmails(emailIDs: [message.emailID])
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.agent(focusedAgent))
                    .controlSize(.small)

                    // Open in mail app
                    if let path = message.emlPath {
                        Button("Open", systemImage: "envelope") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    // Close
                    Button("Close", systemImage: "xmark") {
                        onClose()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }

            // Body preview
            if let parsed {
                if let text = parsed.textBody, !text.isEmpty {
                    ScrollView {
                        Text(text)
                            .font(Typ.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                } else if let html = parsed.htmlBody, !html.isEmpty {
                    HTMLEmailView(html: html, attachments: parsed.attachments)
                        .frame(maxHeight: 200)
                }

                // Attachments
                if !parsed.attachments.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.tertiary)
                        Text("^[\(parsed.attachments.count) attachment](inflect: true)")
                            .font(Typ.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            } else if let preview = message.preview, !preview.isEmpty {
                ScrollView {
                    Text(preview)
                        .font(Typ.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            } else {
                ProgressView("Loading\u{2026}")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.init(top: 16, leading: 48, bottom: 16, trailing: 20))
        .background(Color.accentColor.opacity(0.03))
        .overlay(alignment: .bottom) { Divider() }
        .task(id: message.emailID) { loadEmail() }
    }

    private func loadEmail() {
        parsed = store.emailAccounts.readEmail(emlPath: message.emlPath)
    }

    private var formattedDate: String {
        message.receivedAt
    }
}
