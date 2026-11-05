import SwiftUI

/// Right-margin column of the editor: the checklist items and dated lines found in the note,
/// with the day each one resolves to and when it was first written.
struct AgendaInspectorView: View {
    let items: [AgendaItem]
    let onToggle: (AgendaItem) -> Void
    let history: (AgendaItem) -> [DateChange]
    let onSetDate: (AgendaItem, Date) -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agenda")
                    .font(.headline)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)

                ForEach(AgendaItem.pendingFirst(items)) { item in
                    InspectorRow(
                        item: item, dueLabel: dueLabel(for: item), history: history(item),
                        onToggle: { onToggle(item) }, onSetDate: { onSetDate(item, $0) }
                    )
                }
            }
            .padding(12)
        }
        .frame(width: 240)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func dueLabel(for item: AgendaItem) -> String? {
        guard let date = item.date else { return nil }
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        switch days {
        case 0: return "Today · \(day)"
        case 1: return "Tomorrow · \(day)"
        case ..<0: return "Overdue · \(day)"
        default: return day
        }
    }
}

private struct InspectorRow: View {
    let item: AgendaItem
    let dueLabel: String?
    let history: [DateChange]
    let onToggle: () -> Void
    let onSetDate: (Date) -> Void

    @State private var isHovering = false
    @State private var isEditingDate = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isDone ? .wcagGreen : .wcagSecondaryText)
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.callout)
                    .strikethrough(item.isDone, color: .wcagSecondaryText)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: { isEditingDate = true }) {
                    if let dueLabel {
                        Text(dueLabel)
                            .font(.caption.weight(.medium))
                            .foregroundColor(dueLabel.hasPrefix("Overdue") && !item.isDone ? .wcagOrange : .wcagBlue)
                    } else {
                        Label("Set a date", systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.wcagSecondaryText)
                            .opacity(isHovering || isEditingDate ? 1 : 0)
                    }
                }
                .buttonStyle(.plain)
                .help(item.date == nil ? "Set a date" : "Change the date")
                .accessibilityLabel(item.date == nil ? "Set a date for \(item.text)" : "Change the date of \(item.text)")
                .popover(isPresented: $isEditingDate, arrowEdge: .bottom) {
                    DateEditor(current: item.date, history: history) { day in
                        onSetDate(day)
                        isEditingDate = false
                    }
                }
                Text("Written \(item.writtenOn.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(history.suffix(5).reversed()) { change in
                    Text(change.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.5) : .clear)
        )
        .onHover { isHovering = $0 }
    }
}
