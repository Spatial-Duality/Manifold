// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ConnectionEventsStrip — chronological strip of recent agent
// connection events, shown above the activity timeline. Surfaces
// "Claude disconnected at 4:12 PM" so users investigating "why did my
// session lose context?" have something to look at.

import SwiftUI
import ManifoldKit

struct ConnectionEventsStrip: View {
    let events: [ConnectionEvent]

    private var visible: [ConnectionEvent] {
        Array(events.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(visible) { event in
                HStack(spacing: Spacing.s2) {
                    Image(systemName: event.kind == .connected
                          ? "antenna.radiowaves.left.and.right"
                          : "antenna.radiowaves.left.and.right.slash")
                        .font(ManifoldType.caption)
                        .foregroundStyle(event.kind == .connected
                                         ? ManifoldPalette.active
                                         : ManifoldPalette.attention)
                        .frame(width: 16)
                    Text(label(for: event))
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(timestampLabel(for: event))
                        .font(ManifoldType.numericCaption)
                        .foregroundStyle(.tertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label(for: event)) \(timestampLabel(for: event))")
            }
        }
        .padding(Spacing.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
        .accessibilityIdentifier("work.connectionEvents")
    }

    private func label(for event: ConnectionEvent) -> String {
        let agent: String = switch event.agent {
        case .cowork: "Claude"
        case .codex:  "Codex"
        }
        return event.kind == .connected
            ? "\(agent) connected"
            : "\(agent) disconnected"
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private func timestampLabel(for event: ConnectionEvent) -> String {
        Self.timestampFormatter.string(from: event.at)
    }
}
