import SwiftUI
import ManifoldKit

struct PresetPickerView: View {
    @Environment(ManifoldStore.self) var store
    @Binding var selectedPreset: DomainPreset?

    var body: some View {
        HStack(spacing: Spacing.standard) {
            Text("Type")
                .font(.callout)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(DomainPreset.presets) { preset in
                    Button {
                        selectedPreset = preset
                    } label: {
                        Label(preset.name, systemImage: preset.icon)
                    }
                }
                Divider()
                Button("Clear") { selectedPreset = nil }
            } label: {
                HStack(spacing: Spacing.tight) {
                    if let preset = selectedPreset {
                        Image(systemName: preset.icon)
                        Text(preset.name)
                    } else {
                        Text("General")
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, Spacing.standard)
                .padding(.vertical, Spacing.tight)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: Spacing.cornerSmall))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
