import SwiftUI

public struct DashboardView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    /// Whether items ticked today stay on the dashboard, struck through
    @AppStorage("dashboard.showCompleted") private var showCompleted = true

    /// `.dashboard` for every note, or a project or area for only its notes
    var scope: SidebarSelection
    var onOpenNote: (Note) -> Void

    private let upcomingDays = 14

    public init(scope: SidebarSelection = .dashboard, onOpenNote: @escaping (Note) -> Void) {
        self.scope = scope
        self.onOpenNote = onOpenNote
    }

    // MARK: - Derived Data
    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }

    // MARK: - Body
    public var body: some View {
        let snapshot = scopedSnapshot()
        let lookup = snapshot.notesByID
        let overdue = snapshot.overdue
        let dueToday = snapshot.dueToday
        let upcoming = snapshot.upcomingByDay
        let todos = snapshot.undatedTodosByNote
        let isEmpty = snapshot.isEmpty

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(snapshot) { section in
                        withAnimation { proxy.scrollTo(section, anchor: .top) }
                    }

                    if isEmpty {
                        emptyState
                    } else {
                        if !overdue.isEmpty {
                            DashboardSection(title: "Overdue", systemImage: "exclamationmark.circle.fill", tint: .wcagOrange) {
                                ForEach(overdue) { item in
                                    row(item, note: lookup[item.noteID], showDate: true)
                                }
                            }
                            .id(Section.overdue)
                        }

                        DashboardSection(title: "Today", systemImage: "sun.max.fill", tint: .wcagBlue) {
                            if dueToday.isEmpty {
                                Text(snapshot.isTodayDone ? "All done for today." : "Nothing planned for today.")
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
                        .id(Section.today)

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
                            .id(Section.upcoming)
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
                            .id(Section.todos)
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
    }

    /// The sections the summary chips scroll to
    private enum Section { case overdue, today, upcoming, todos }

    private func scopedSnapshot() -> DashboardSnapshot {
        var notes = storageManager.notes
        var items = storageManager.agendaItems
        if scope.hasOwnDashboard {
            notes = notes.filter(scope.contains)
            let ids = Set(notes.map(\.id))
            items = items.filter { ids.contains($0.noteID) }
        }
        let doneToday = Set(storageManager.itemsDone(on: today, in: items, calendar: calendar).map(\.id))
        return DashboardSnapshot(notes: notes, items: items, today: today, upcomingDays: upcomingDays,
                                 calendar: calendar, doneToday: doneToday, showCompleted: showCompleted)
    }

    // MARK: - Pieces
    private func header(_ snapshot: DashboardSnapshot, show: @escaping (Section) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if scope.hasOwnDashboard {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(scope.title)
                        .font(.system(size: 34, weight: .bold))
                        .lineLimit(1)
                } else {
                    Text(Date().formatted(.dateTime.weekday(.wide)))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(Date().formatted(.dateTime.day().month(.wide).year()))
                        .font(.system(size: 34, weight: .bold))
                }
            }
            HStack(spacing: 8) {
                StatChip(value: snapshot.overdueCount, label: "overdue", tint: .wcagOrange) { show(.overdue) }
                StatChip(value: snapshot.openTodayCount, label: "today", tint: .wcagBlue,
                         isAllDone: snapshot.isTodayDone) { show(.today) }
                StatChip(value: snapshot.upcomingCount, label: "upcoming", tint: .wcagPurple) { show(.upcoming) }
                StatChip(value: snapshot.openTodoCount, label: "open to-dos", tint: .wcagGreen) { show(.todos) }
                Spacer()
                Button(showCompleted ? "Hide Completed" : "Show Completed",
                       systemImage: showCompleted ? "eye.slash" : "eye") {
                    withAnimation { showCompleted.toggle() }
                }
                .buttonStyle(.borderless)
                .foregroundColor(.wcagSecondaryText)
                .help(showCompleted ? "Hide items ticked today" : "Show items ticked today")
            }
            if snapshot.completedTodayCount > 0 {
                Text(snapshot.isTodayDone
                     ? "All done for today: \(snapshot.completedTodayCount) completed"
                     : "\(snapshot.completedTodayCount) completed today")
                    .font(.caption)
                    .foregroundColor(.wcagSecondaryText)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to show yet")
                .font(.headline)
            Text(scope.hasOwnDashboard
                 ? "This dashboard collects to-dos and dated lines from the notes in \(scope.title). Try writing:"
                 : "The dashboard collects to-dos and dated lines from all your notes. Try writing:")
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
    /// Shows a sun in place of the count, once everything it counts is done
    var isAllDone = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isAllDone {
                    Text("☀️")
                        .font(.callout)
                        .accessibilityLabel("All done")
                } else {
                    Text("\(value)")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundColor(value > 0 ? tint : .wcagSecondaryText)
                }
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // With nothing to show, the section may not be there to scroll to
        .disabled(value == 0 && !isAllDone)
        .help(value > 0 || isAllDone ? "Show \(label)" : "")
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
