import SwiftUI

/// Right-margin column of the editor: the checklist items and dated lines found in the note,
/// with the day each one resolves to and when it was first written.
struct AgendaInspectorView: View {
    let items: [AgendaItem]
    let onToggle: (AgendaItem) -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agenda")
                    .font(.headline)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)

                ForEach(items) { item in
                    InspectorRow(item: item, dueLabel: dueLabel(for: item), onToggle: { onToggle(item) })
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
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if item.isTodo {
                Button(action: onToggle) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(item.isDone ? .wcagGreen : .wcagSecondaryText)
                }
                .buttonStyle(.plain)
                .help(item.isDone ? "Mark as not done" : "Mark as done")
            } else {
                Image(systemName: "calendar")
                    .foregroundColor(.wcagPurple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.callout)
                    .strikethrough(item.isDone, color: .wcagSecondaryText)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let dueLabel {
                    Text(dueLabel)
                        .font(.caption.weight(.medium))
                        .foregroundColor(dueLabel.hasPrefix("Overdue") && !item.isDone ? .wcagOrange : .wcagBlue)
                }
                Text("Written \(item.writtenOn.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
