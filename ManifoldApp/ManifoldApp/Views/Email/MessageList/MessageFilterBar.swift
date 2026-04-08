import SwiftUI
import ManifoldKit

struct MessageFilterBar: View {
    @Bindable var selection: EmailSelectionModel
    @Bindable var search: EmailSearchModel
    @State private var showDatePicker = false

    var body: some View {
        HStack(spacing: Spacing.standard) {
            // Sort picker
            Menu {
                ForEach(EmailSortKey.allCases, id: \.self) { key in
                    Button {
                        selection.sortKey = key
                    } label: {
                        HStack {
                            Text(key.rawValue.capitalized)
                            if selection.sortKey == key {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort: \(selection.sortKey.rawValue.capitalized)", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Date range button
            Button {
                showDatePicker.toggle()
            } label: {
                Label(dateRangeLabel, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(hasDateFilter ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDatePicker) {
                DateRangePopover(search: search)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.edge)
        .padding(.vertical, Spacing.tight)
        .background(.bar)
    }

    private var hasDateFilter: Bool {
        search.tokens.contains { $0.type == .dateAfter || $0.type == .dateBefore }
    }

    private var dateRangeLabel: String {
        hasDateFilter ? "Date Active" : "Date Range"
    }
}

// MARK: - Date Range Popover

private struct DateRangePopover: View {
    @Bindable var search: EmailSearchModel
    @State private var afterDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var beforeDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            Text("Date Range")
                .font(.callout.weight(.medium))

            HStack {
                Text("From:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $afterDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            HStack {
                Text("To:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 35, alignment: .leading)
                DatePicker("", selection: $beforeDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            Divider()

            // Presets
            HStack(spacing: Spacing.standard) {
                presetButton("Today") {
                    afterDate = Calendar.current.startOfDay(for: Date())
                    beforeDate = Date()
                }
                presetButton("This Week") {
                    afterDate = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
                    beforeDate = Date()
                }
                presetButton("This Month") {
                    afterDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
                    beforeDate = Date()
                }
                presetButton("Last 30 Days") {
                    afterDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                    beforeDate = Date()
                }
            }

            HStack {
                Button("Clear") {
                    search.tokens.removeAll { $0.type == .dateAfter || $0.type == .dateBefore }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Apply") {
                    applyDateRange()
                }
                .glassProminentButton()
            }
        }
        .padding(Spacing.edge)
        .frame(width: 280)
    }

    private func presetButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label) { action() }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func applyDateRange() {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        // Remove existing date tokens
        search.tokens.removeAll { $0.type == .dateAfter || $0.type == .dateBefore }

        // Add new date tokens
        search.addToken(SearchToken(type: .dateAfter, value: iso.string(from: afterDate)))
        search.addToken(SearchToken(type: .dateBefore, value: iso.string(from: beforeDate)))
    }
}
