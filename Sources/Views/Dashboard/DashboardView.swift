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

    // MARK: - Body
    public var body: some View {
        let snapshot = DashboardSnapshot(notes: storageManager.notes, items: storageManager.agendaItems,
                                today: today, upcomingDays: upcomingDays, calendar: calendar)
        let lookup = snapshot.notesByID
        let overdue = snapshot.overdue
        let dueToday = snapshot.dueToday
        let upcoming = snapshot.upcomingByDay
        let todos = snapshot.undatedTodosByNote
        let isEmpty = snapshot.isEmpty

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(snapshot)

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
    private func header(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(Date().formatted(.dateTime.day().month(.wide).year()))
                    .font(.system(size: 34, weight: .bold))
            }
            HStack(spacing: 8) {
                StatChip(value: snapshot.overdue.count, label: "overdue", tint: .wcagOrange)
                StatChip(value: snapshot.dueToday.filter { !$0.isDone }.count, label: "today", tint: .wcagBlue)
                StatChip(value: snapshot.upcomingCount, label: "upcoming", tint: .wcagPurple)
                StatChip(value: snapshot.openTodoCount, label: "open to-dos", tint: .wcagGreen)
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
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(item.isDone ? .wcagGreen : .wcagSecondaryText)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark as not done" : "Mark as done")

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
