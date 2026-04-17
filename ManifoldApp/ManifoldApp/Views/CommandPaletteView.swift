// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct CommandPaletteView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(CommandPaletteModel.self) var commandPalette
    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex: Int = 0

    private var filteredCommands: [ManifoldCommand] {
        commandPalette.filteredCommands(for: store)
    }

    var body: some View {
        @Bindable var commandPalette = commandPalette

        VStack(spacing: 0) {
            // Search field
            HStack(spacing: Spacing.standard) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search commands...", text: $commandPalette.searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit { executeSelected() }
                    .accessibilityIdentifier("commandPalette.search")
                if !commandPalette.searchText.isEmpty {
                    Button {
                        commandPalette.searchText = ""
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
            if filteredCommands.isEmpty {
                ContentUnavailableView(
                    "No commands match",
                    systemImage: "magnifyingglass",
                    description: Text("Try a shorter search, or clear the filter to browse all available actions.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
        }
        .frame(width: 480, height: 360)
        .glassBackground(in: RoundedRectangle(cornerRadius: Spacing.cornerLarge))
        .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
        .onAppear {
            commandPalette.searchText = ""
            selectedIndex = 0
            isSearchFocused = true
        }
        .onChange(of: commandPalette.searchText) {
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
        .accessibilityIdentifier("commandPalette.sheet")
    }

    private func executeSelected() {
        guard selectedIndex < filteredCommands.count else { return }
        runCommand(filteredCommands[selectedIndex])
    }

    private func runCommand(_ command: ManifoldCommand) {
        commandPalette.isPresented = false
        Task { await command.action(store) }
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
                if let shortcut = command.shortcutLabel {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Spacing.section)
            .padding(.vertical, Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cornerSmall, style: .continuous)
                    .fill(highlighted ? ManifoldPalette.selectionSoft : Color.clear)
            )
            .overlay(alignment: .leading) {
                if highlighted {
                    Capsule(style: .continuous)
                        .fill(ManifoldPalette.selection)
                        .frame(width: 2)
                        .padding(.vertical, 6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("commandPalette.command.\(command.identifierSlug)")
    }
}

private extension ManifoldCommand {
    var identifierSlug: String {
        title
            .lowercased()
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: " ", with: "-")
    }
}
