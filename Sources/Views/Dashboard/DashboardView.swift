import SwiftUI

public struct DashboardView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared

    var onOpenNote: (Note) -> Void

    private let upcomingDays = 14

    public init(onOpenNote: @escaping (Note) -> Void) {
        self.onOpenNote = onOpenNote
    }

    // MARK: - Derived Data
    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }

    private var notesByID: [UUID: Note] {
        Dictionary(uniqueKeysWithValues: storageManager.notes.map { ($0.id, $0) })
    }

    private var overdue: [AgendaItem] {
        storageManager.agendaItems
            .filter { $0.isTodo && !$0.isDone && ($0.date.map { $0 < today } ?? false) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    private var dueToday: [AgendaItem] {
        storageManager.agendaItems
            .filter { $0.date.map { calendar.isDate($0, inSameDayAs: today) } ?? false }
            .sorted { !$0.isDone && $1.isDone }
    }

    private var upcomingByDay: [(day: Date, items: [AgendaItem])] {
        guard let end = calendar.date(byAdding: .day, value: upcomingDays + 1, to: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let items = storageManager.agendaItems.filter { item in
            guard let date = item.date else { return false }
            return date >= tomorrow && date < end && !item.isDone
        }
        return Dictionary(grouping: items) { $0.date! }
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, items: $0.value) }
    }

    private var undatedTodosByNote: [(note: Note, items: [AgendaItem])] {
        let items = storageManager.agendaItems.filter { $0.isTodo && !$0.isDone && $0.date == nil }
        let lookup = notesByID
        return Dictionary(grouping: items) { $0.noteID }
            .compactMap { id, items in lookup[id].map { (note: $0, items: items.sorted { $0.lineIndex < $1.lineIndex }) } }
            .sorted { $0.note.updatedAt > $1.note.updatedAt }
    }

    private var openTodoCount: Int {
        storageManager.agendaItems.filter { $0.isTodo && !$0.isDone }.count
    }

    // MARK: - Body
    public var body: some View {
        let lookup = notesByID
        let upcoming = upcomingByDay
        let todos = undatedTodosByNote
        let isEmpty = overdue.isEmpty && dueToday.isEmpty && upcoming.isEmpty && todos.isEmpty

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(upcomingCount: upcoming.reduce(0) { $0 + $1.items.count })

                if isEmpty {
                    emptyState
                } else {
                    if !overdue.isEmpty {
                        DashboardSection(title: "Overdue", systemImage: "exclamationmark.circle.fill", tint: .wcagOrange) {
                            ForEach(overdue) { item in
                                row(item, note: lookup[item.noteID], showDate: true)
                            }
                        }
                    }

                    DashboardSection(title: "Today", systemImage: "sun.max.fill", tint: .wcagBlue) {
                        if dueToday.isEmpty {
                            Text("Nothing planned for today.")
                                .font(.callout)
                                .foregroundColor(.wcagSecondaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(dueToday) { item in
                                row(item, note: lookup[item.noteID], showDate: false)
                            }
                        }
                    }

                    if !upcoming.isEmpty {
                        DashboardSection(title: "Next \(upcomingDays) Days", systemImage: "calendar", tint: .wcagPurple) {
                            ForEach(upcoming, id: \.day) { group in
                                Text(dayLabel(group.day))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.wcagSecondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                                ForEach(group.items) { item in
                                    row(item, note: lookup[item.noteID], showDate: false)
                                }
                            }
                        }
                    }

                    if !todos.isEmpty {
                        DashboardSection(title: "To-do", systemImage: "checklist", tint: .wcagGreen) {
                            ForEach(todos, id: \.note.id) { group in
                                Button(action: { onOpenNote(group.note) }) {
                                    Label(group.note.displayTitle, systemImage: group.note.categoryType.iconName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.wcagSecondaryText)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                                .help("Open note")
                                ForEach(group.items) { item in
                                    row(item, note: nil, showDate: false)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .scrollContentBackground(.hidden)
    }

    // MARK: - Pieces
    private func header(upcomingCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(Date().formatted(.dateTime.day().month(.wide).year()))
                    .font(.system(size: 34, weight: .bold))
            }
            HStack(spacing: 8) {
                StatChip(value: overdue.count, label: "overdue", tint: .wcagOrange)
                StatChip(value: dueToday.filter { !$0.isDone }.count, label: "today", tint: .wcagBlue)
                StatChip(value: upcomingCount, label: "upcoming", tint: .wcagPurple)
                StatChip(value: openTodoCount, label: "open to-dos", tint: .wcagGreen)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to show yet")
                .font(.headline)
            Text("The dashboard collects checklists and dated lines from all your notes. Try writing:")
                .font(.callout)
                .foregroundColor(.wcagSecondaryText)
            VStack(alignment: .leading, spacing: 4) {
                Text("- [ ] Renew passport")
                Text("- [ ] Call the bank tomorrow")
                Text("Team dinner on friday")
                Text("Dentist oct 30 at 4pm")
                Text("- [ ] Send invoice @2026-11-02")
            }
            .font(.system(.callout, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.wcagBadgeBackground)
            .cornerRadius(8)
        }
        .padding(.top, 8)
    }

    private func row(_ item: AgendaItem, note: Note?, showDate: Bool) -> some View {
        AgendaRow(
            item: item,
            note: note,
            dateLabel: showDate ? item.date.map(dayLabel) : nil,
            onToggle: { storageManager.toggleChecklistItem(noteID: item.noteID, lineIndex: item.lineIndex) },
            onOpenNote: onOpenNote
        )
    }

    private func dayLabel(_ date: Date) -> String {
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        if (2...6).contains(days) {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
                    .font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
        }
    }
}

private struct StatChip: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundColor(value > 0 ? tint : .wcagSecondaryText)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

private struct AgendaRow: View {
    let item: AgendaItem
    let note: Note?
    let dateLabel: String?
    let onToggle: () -> Void
    let onOpenNote: (Note) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if item.isTodo {
                Button(action: onToggle) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundColor(item.isDone ? .wcagGreen : .wcagSecondaryText)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(item.isDone ? "Mark as not done" : "Mark as done")
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
            }

            Text(item.text)
                .strikethrough(item.isDone, color: .wcagSecondaryText)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if let dateLabel {
                Text(dateLabel)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.wcagOrange)
            }

            if let note {
                Button(action: { onOpenNote(note) }) {
                    Text(note.displayTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 160, alignment: .trailing)
                        .foregroundColor(.wcagBlue)
                }
                .buttonStyle(.plain)
                .help("Open \"\(note.displayTitle)\"")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.5) : .clear)
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.default, value: item.isDone)
    }
}
