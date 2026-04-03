import SwiftUI
import ManifoldKit

struct ProfilesView: View {
    @EnvironmentObject var appState: AppState
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

            // Preset picker
            HStack(spacing: 8) {
                ForEach(profiles) { profile in
                    PresetButton(
                        profile: profile,
                        isSelected: profile.id == selectedProfileID,
                        isDisabled: appState.hasActiveRun
                    ) {
                        if !appState.hasActiveRun {
                            selectedProfileID = profile.id
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            if appState.hasActiveRun {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("End current access before switching profiles")
                        .font(.system(size: 11))
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            if profile.sourcePaths.isEmpty {
                                Text("No file sources. Add sources first.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(profile.sourcePaths, id: \.self) { path in
                                    HStack {
                                        Image(systemName: "folder")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Text(path)
                                            .font(.system(size: 12))
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
                                .font(.system(size: 12))
                            Spacer()
                            Text(profile.includeEmails ? "Yes (filtered by rules)" : "No")
                                .font(.system(size: 11))
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: profile.icon)
                    .font(.system(size: 16))
                Text(profile.name)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
