import SwiftUI
import ManifoldKit

struct ProfilesView: View {
    @EnvironmentObject var appState: AppState
    @Namespace private var presetNamespace
    @State private var profiles: [NamedProfile] = []
    @State private var selectedProfileID: String = "work"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Quick-switch what agents can access")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Preset picker — grouped glass elements
            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        PresetButton(
                            profile: profile,
                            isSelected: profile.id == selectedProfileID,
                            isDisabled: appState.hasActiveRun,
                            namespace: presetNamespace
                        ) {
                            if !appState.hasActiveRun {
                                withAnimation(.smooth) {
                                    selectedProfileID = profile.id
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            if appState.hasActiveRun {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("End current access before switching profiles")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            Divider()

            // Selected profile details
            if let profile = profiles.first(where: { $0.id == selectedProfileID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Sources in this profile
                        VStack(alignment: .leading, spacing: 8) {
                            Text("File sources")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            if profile.sourcePaths.isEmpty {
                                Text("No file sources. Add sources first.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(profile.sourcePaths, id: \.self) { path in
                                    HStack {
                                        Image(systemName: "folder")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(path)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }
                        }

                        Divider()

                        // Email setting
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundStyle(.secondary)
                            Text("Include emails")
                                .font(.caption)
                            Spacer()
                            Text(profile.includeEmails ? "Yes (filtered by rules)" : "No")
                                .font(.caption2)
                                .foregroundStyle(profile.includeEmails ? .green : .secondary)
                        }
                    }
                    .padding(20)
                }
            }

            Spacer()
        }
        .onAppear { loadProfiles() }
    }

    private func loadProfiles() {
        let manager = ProfileManager(baseURL: AppState.manifoldWorkspacesURL())
        let sourcePaths = appState.sources.map { $0.path }
        profiles = manager.seedDefaults(availableSources: sourcePaths)
        if profiles.isEmpty {
            profiles = manager.allProfiles()
        }
    }
}

struct PresetButton: View {
    let profile: NamedProfile
    let isSelected: Bool
    let isDisabled: Bool
    var namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: profile.icon)
                    .font(.callout)
                Text(profile.name)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glass)
        .tint(isSelected ? Color.accentColor : nil)
        .glassEffectID(profile.id, in: namespace)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Previews

#Preview("Profiles") {
    ProfilesView()
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
