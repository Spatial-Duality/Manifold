import SwiftUI
import ManifoldKit

struct CommandPaletteView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(CommandCenter.self) var commands
    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex: Int = 0

    private var filteredCommands: [ManifoldCommand] {
        commands.filteredCommands()
    }

    var body: some View {
        @Bindable var commands = commands

        VStack(spacing: 0) {
            // Search field
            HStack(spacing: Spacing.standard) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search commands...", text: $commands.searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit { executeSelected() }
                if !commands.searchText.isEmpty {
                    Button {
                        commands.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.edge)
            .padding(.vertical, Spacing.section)

            Divider()

            // Command list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                            CommandRow(
                                command: command,
                                isSelected: index == selectedIndex
                            ) {
                                runCommand(command)
                            }
                            .id(index)
                        }
                    }
                    .padding(.vertical, Spacing.standard)
                    .padding(.horizontal, Spacing.standard)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(width: 480, height: 360)
        .glassBackground(in: RoundedRectangle(cornerRadius: Spacing.cornerLarge))
        .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
        .onAppear {
            commands.searchText = ""
            selectedIndex = 0
            isSearchFocused = true
        }
        .onChange(of: commands.searchText) {
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredCommands.count - 1 { selectedIndex += 1 }
            return .handled
        }
    }

    private func executeSelected() {
        guard selectedIndex < filteredCommands.count else { return }
        runCommand(filteredCommands[selectedIndex])
    }

    private func runCommand(_ command: ManifoldCommand) {
        commands.isPresented = false
        Task { await command.action() }
    }
}

private struct CommandRow: View {
    let command: ManifoldCommand
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var highlighted: Bool { isSelected || isHovered }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.section) {
                Image(systemName: command.icon)
                    .frame(width: 20)
                    .foregroundStyle(highlighted ? .primary : .secondary)
                Text(command.title)
                    .font(.body)
                Spacer()
                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Spacing.section)
            .padding(.vertical, Spacing.standard)
            .background(highlighted ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerSmall))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
