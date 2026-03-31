import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Control what each agent can access")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 16) {
                    ProfileCard(
                        agent: "Cowork",
                        icon: "desktopcomputer",
                        color: .blue,
                        sources: appState.sources,
                        description: "Claude's computer use agent. Runs in a VM with VirtioFS mount."
                    )

                    ProfileCard(
                        agent: "Codex",
                        icon: "terminal",
                        color: .purple,
                        sources: appState.sources,
                        description: "OpenAI's coding agent. Runs directly on your filesystem."
                    )
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }
}

struct ProfileCard: View {
    let agent: String
    let icon: String
    let color: Color
    let sources: [SourceItem]
    let description: String

    @State private var enabledPaths: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Agent header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.1))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent)
                        .font(.system(size: 15, weight: .semibold))
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if sources.isEmpty {
                Text("Add sources first, then assign them to this profile")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                // Source toggles
                ForEach(sources) { source in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { enabledPaths.contains(source.path) },
                            set: { enabled in
                                if enabled { enabledPaths.insert(source.path) }
                                else { enabledPaths.remove(source.path) }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Image(systemName: source.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(source.displayName)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Spacer()

                        if source.isSensitive && enabledPaths.contains(source.path) {
                            SensitiveBadge()
                        }

                        // Access duration picker
                        if enabledPaths.contains(source.path) {
                            Picker("", selection: .constant("persistent")) {
                                Text("Persistent").tag("persistent")
                                Text("Session only").tag("session")
                                Text("48 hours").tag("timed")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.02))
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
