import SwiftUI

/// The note whose text the pointer is over in a dashboard's notes log, so the note list can
/// mark it. Only one dashboard is on screen at a time.
@MainActor
final class NoteHighlight: ObservableObject {
    static let shared = NoteHighlight()
    @Published var noteID: UUID?
}

public struct DashboardView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject private var highlight = NoteHighlight.shared
    /// Whether items ticked today stay on the dashboard, struck through
    @AppStorage("dashboard.showCompleted") private var showCompleted = true
    /// The list of everything ticked earlier starts folded away
    @AppStorage("dashboard.completedExpanded") private var completedExpanded = false
    /// Quick search: only items matching every word are shown
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// `.dashboard` for every note, or a project or area for only its notes
    var scope: SidebarSelection
    /// Set to `.dashboard` to move keyboard focus onto the first item; cleared once it has
    @Binding var focusRequest: MainPane?
    var onOpenNote: (Note) -> Void

    private let upcomingDays = 14
    /// The item the arrow keys are on, marked in its row
    @State private var focusedItemID: String?
    @FocusState private var itemsFocused: Bool

    public init(scope: SidebarSelection = .dashboard, focusRequest: Binding<MainPane?> = .constant(nil),
                onOpenNote: @escaping (Note) -> Void) {
        self.scope = scope
        self._focusRequest = focusRequest
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

                    if !isEmpty {
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
                                    if group.items.count == 1, let item = group.items.first {
                                        // A lone to-do needs no heading: the note's name sits on the right, as under Overdue
                                        row(item, note: group.note, showDate: false)
                                    } else {
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
                            .id(Section.todos)
                        }
                    }

                    completedSection(snapshot)

                    if !query.isEmpty && isEmpty && snapshot.completed.isEmpty {
                        Text("No items match \"\(query)\".")
                            .font(.callout)
                            .foregroundColor(.wcagSecondaryText)
                            .padding(.horizontal, 4)
                    }

                    if scope.hasOwnDashboard {
                        let terms = DashboardSearch.terms(query)
                        notesLog(snapshot.notesByID.values.filter {
                            DashboardSearch.matches(terms, in: [$0.displayTitle, $0.content])
                        })
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .scrollContentBackground(.hidden)
            .focusable()
            .focusEffectDisabled()
            .focused($itemsFocused)
            .onKeyPress(.downArrow) { moveFocus(by: 1, proxy: proxy); return .handled }
            .onKeyPress(.upArrow) { moveFocus(by: -1, proxy: proxy); return .handled }
            .onKeyPress(.leftArrow) { focusRequest = .sidebar; return .handled }
            .onKeyPress(.return) {
                guard let id = focusedItemID, let item = navigableItems(snapshot).first(where: { $0.id == id }),
                      let note = lookup[item.noteID] else { return .ignored }
                onOpenNote(note)
                return .handled
            }
            .onChange(of: focusRequest) { _, request in
                guard request == .dashboard else { return }
                focusRequest = nil
                focusFirstItem(proxy: proxy)
            }
            .onChange(of: itemsFocused) { _, focused in
                if !focused { focusedItemID = nil }
            }
        }
    }

    /// The items in the order they are on the page, which is the order the arrow keys walk them
    private func navigableItems(_ snapshot: DashboardSnapshot) -> [AgendaItem] {
        var items = snapshot.overdue + snapshot.dueToday
        items += snapshot.upcomingByDay.flatMap(\.items)
        items += snapshot.undatedTodosByNote.flatMap(\.items)
        if completedExpanded { items += snapshot.completed }
        return items
    }

    /// Puts the keyboard on the first item, or in the search box when there is none
    private func focusFirstItem(proxy: ScrollViewProxy) {
        guard let first = navigableItems(scopedSnapshot()).first else {
            focusedItemID = nil
            searchFocused = true
            return
        }
        searchFocused = false
        itemsFocused = true
        focusedItemID = first.id
        proxy.scrollTo(first.id)
    }

    /// Down goes to the next item, up to the previous one; up from the first goes to the search box
    private func moveFocus(by step: Int, proxy: ScrollViewProxy) {
        let items = navigableItems(scopedSnapshot())
        guard !items.isEmpty else { searchFocused = true; return }
        let current = items.firstIndex { $0.id == focusedItemID }
        if step < 0, (current ?? 0) <= 0 {
            focusedItemID = nil
            searchFocused = true
            return
        }
        let next = items[min(max((current ?? -1) + step, 0), items.count - 1)]
        focusedItemID = next.id
        proxy.scrollTo(next.id)
    }

    /// The sections the summary chips scroll to
    private enum Section { case overdue, today, upcoming, todos, completed }

    private func scopedSnapshot() -> DashboardSnapshot {
        var notes = storageManager.notes
        var items = storageManager.agendaItems
        if scope.hasOwnDashboard {
            notes = notes.filter(scope.contains)
            let ids = Set(notes.map(\.id))
            items = items.filter { ids.contains($0.noteID) }
        }
        let terms = DashboardSearch.terms(query)
        if !terms.isEmpty {
            let lookup = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
            items = DashboardSearch.filter(items, terms: terms, notes: lookup)
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
            searchField
            // With nothing to show there is nothing to count; ticked items stay reachable through the toggle
            if !snapshot.isEmpty || snapshot.completedTodayCount > 0 {
                HStack(spacing: 8) {
                    if !snapshot.isEmpty {
                        StatChip(value: snapshot.overdueCount, label: "overdue", tint: .wcagOrange) { show(.overdue) }
                        StatChip(value: snapshot.openTodayCount, label: "today", tint: .wcagBlue,
                                 isAllDone: snapshot.isTodayDone) { show(.today) }
                        StatChip(value: snapshot.upcomingCount, label: "upcoming", tint: .wcagPurple) { show(.upcoming) }
                        StatChip(value: snapshot.openTodoCount, label: "open to-dos", tint: .wcagGreen) { show(.todos) }
                    }
                    Spacer()
                    Button(showCompleted ? "Hide Completed" : "Show Completed",
                           systemImage: showCompleted ? "eye.slash" : "eye") {
                        withAnimation { showCompleted.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.wcagSecondaryText)
                    .help(showCompleted ? "Hide items ticked today" : "Show items ticked today")
                }
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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.wcagSecondaryText)
            TextField("Search the dashboard", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.downArrow) {
                    focusedItemID = navigableItems(scopedSnapshot()).first?.id
                    guard focusedItemID != nil else { return .handled }
                    searchFocused = false
                    itemsFocused = true
                    return .handled
                }
                .onExitCommand { query = ""; searchFocused = false }
                .accessibilityIdentifier("dashboardSearch")
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.wcagSecondaryText)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Every note in the scope as one running document, newest first: the day it was written,
    /// then the whole note. Pointing at a note marks it in the note list; clicking its date opens it.
    @ViewBuilder
    private func notesLog(_ notes: some Collection<Note>) -> some View {
        let entries = notes.sorted { $0.createdAt > $1.createdAt }
        if !entries.isEmpty {
            DashboardSection(title: "Notes", systemImage: "doc.text", tint: .wcagSecondaryText) {
                ForEach(entries) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: { onOpenNote(note) }) {
                            Text(note.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.wcagSecondaryText)
                        }
                        .buttonStyle(.plain)
                        .help("Open note")
                        Text(note.content.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(highlight.noteID == note.id ? Color.wcagSelection.opacity(0.15) : Color.clear)
                    )
                    .onHover { inside in
                        if inside {
                            highlight.noteID = note.id
                        } else if highlight.noteID == note.id {
                            highlight.noteID = nil
                        }
                    }
                }
            }
            .onDisappear { highlight.noteID = nil }
        }
    }

    /// Everything ticked that the sections above do not show, folded away until asked for
    @ViewBuilder
    private func completedSection(_ snapshot: DashboardSnapshot) -> some View {
        if !snapshot.completed.isEmpty {
            let groups = completedGroups(snapshot.completed)
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { withAnimation { completedExpanded.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: completedExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 12)
                        Image(systemName: "checkmark.circle.fill")
                            .prominenceAwareColor(.wcagGreen)
                        Text("Completed")
                            .font(.title3.weight(.semibold))
                        Text("\(snapshot.completed.count)")
                            .font(.callout)
                            .foregroundColor(.wcagSecondaryText)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Completed, \(snapshot.completed.count)")
                .accessibilityValue(completedExpanded ? "expanded" : "collapsed")
                .help(completedExpanded ? "Hide completed items" : "Show completed items")

                if completedExpanded {
                    ForEach(groups, id: \.label) { group in
                        Text(group.label)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.wcagSecondaryText)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        ForEach(group.items) { item in
                            row(item, note: snapshot.notesByID[item.noteID], showDate: false)
                        }
                    }
                }
            }
            .id(Section.completed)
        }
    }

    /// Completed items under the day they were ticked; ones without a day under "Earlier"
    private func completedGroups(_ items: [AgendaItem]) -> [(label: String, items: [AgendaItem])] {
        var groups: [(label: String, items: [AgendaItem])] = []
        for item in items {
            let label = item.doneOn.map(dayLabel) ?? "Earlier"
            if let last = groups.indices.last, groups[last].label == label {
                groups[last].items.append(item)
            } else {
                groups.append((label, [item]))
            }
        }
        return groups
    }

    private func row(_ item: AgendaItem, note: Note?, showDate: Bool) -> some View {
        AgendaRow(
            item: item,
            note: note,
            dateLabel: showDate ? item.date.map(dayLabel) : nil,
            history: { storageManager.dateHistory(for: item) },
            onToggle: { storageManager.toggleChecklistItem(noteID: item.noteID, lineIndex: item.lineIndex) },
            onSetDate: { storageManager.setDate(noteID: item.noteID, lineIndex: item.lineIndex, to: $0) },
            onOpenNote: onOpenNote,
            isFocused: focusedItemID == item.id
        )
        .id(item.id)
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
    let history: () -> [DateChange]
    let onToggle: () -> Void
    let onSetDate: (Date) -> Void
    let onOpenNote: (Note) -> Void
    /// The arrow keys are on this row
    var isFocused = false

    @State private var isHovering = false
    @State private var isEditingDate = false

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
            .accessibilityLabel(item.isDone ? "Mark \(item.text) as not done" : "Mark \(item.text) as done")

            Text(item.text)
                .strikethrough(item.isDone, color: .wcagSecondaryText)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Button(action: { isEditingDate = true }) {
                if let dateLabel {
                    Text(dateLabel)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.wcagOrange)
                } else {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.wcagSecondaryText)
                        .opacity(isHovering || isEditingDate ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .help(item.date == nil ? "Set a date" : "Change the date")
            .accessibilityLabel(item.date == nil ? "Set a date for \(item.text)" : "Change the date of \(item.text)")
            .popover(isPresented: $isEditingDate, arrowEdge: .bottom) {
                DateEditor(current: item.date, history: history()) { day in
                    onSetDate(day)
                    isEditingDate = false
                }
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
                .fill(isFocused ? Color.wcagBlue.opacity(0.18) : (isHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.5) : .clear))
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.default, value: item.isDone)
    }
}

/// The popover that sets the day of a to-do: quick picks, a calendar, and what was changed before.
struct DateEditor: View {
    let current: Date?
    let history: [DateChange]
    let onPick: (Date) -> Void

    @State private var picked: Date

    init(current: Date?, history: [DateChange], onPick: @escaping (Date) -> Void) {
        self.current = current
        self.history = history
        self.onPick = onPick
        _picked = State(initialValue: current ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(QuickDates.options(today: Date()), id: \.title) { option in
                    Button(option.title) { onPick(option.day) }
                }
            }
            DatePicker("Date", selection: $picked, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .onChange(of: picked) { _, day in onPick(day) }

            if !history.isEmpty {
                Divider()
                Text("History")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.wcagSecondaryText)
                ForEach(history.suffix(5).reversed()) { change in
                    Text(change.summary)
                        .font(.caption)
                        .foregroundColor(.wcagSecondaryText)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
