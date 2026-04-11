import SwiftUI
import ManifoldKit

/// Shield detail view — toggle, description, detection patterns, recent matches.
struct ShieldDetailView: View {
    @Binding var shield: EmailShield

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with toggle
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: shield.isEnabled ? "shield.fill" : "shield")
                            .font(.title2)
                            .foregroundStyle(shield.isEnabled ? .green : .secondary)
                        Text(shield.name)
                            .font(Typ.sectionTitle)
                    }
                    Spacer()
                    Toggle(shield.isEnabled ? "Active" : "Disabled", isOn: $shield.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                // Description
                Text(shield.description)
                    .font(Typ.body)
                    .foregroundStyle(.secondary)

                Divider()

                // Detection patterns
                DisclosureGroup("Detection Patterns") {
                    VStack(alignment: .leading, spacing: 12) {
                        if !shield.domains.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Monitored domains")
                                    .font(Typ.caption)
                                    .foregroundStyle(.tertiary)
                                HStack(spacing: 6) {
                                    ForEach(shield.domains, id: \.self) { domain in
                                        Text(domain)
                                            .font(Typ.mono)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                            }
                        }

                        if !shield.patterns.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Subject & body patterns")
                                    .font(Typ.caption)
                                    .foregroundStyle(.tertiary)
                                HStack(spacing: 6) {
                                    ForEach(shield.patterns.prefix(4), id: \.self) { pattern in
                                        Text("\"\(pattern)\"")
                                            .font(Typ.mono)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.orange.opacity(0.08), in: Capsule())
                                    }
                                }
                                if shield.patterns.count > 4 {
                                    Text("+\(shield.patterns.count - 4) more patterns")
                                        .font(Typ.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }

                Divider()

                // Recent matches
                if shield.recentMatches.isEmpty {
                    ContentUnavailableView {
                        Label("No Recent Matches", systemImage: "shield")
                    } description: {
                        Text("Emails caught by this shield will appear here.")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Matches")
                            .font(Typ.heading)
                        ForEach(shield.recentMatches) { match in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.subject)
                                        .font(Typ.body)
                                        .lineLimit(1)
                                    Text(match.from)
                                        .font(Typ.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(match.date, style: .relative)
                                    .font(Typ.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle(shield.name)
    }
}
