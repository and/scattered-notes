import SwiftUI

/// Overdue, today, the next 14 days and open to-dos from every note, as on the Mac Dashboard.
struct DashboardScreen: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    @State private var isCapturing = false
    @State private var query = ""
    /// The search bar takes a row of its own, so it stays closed until the magnifier is tapped
    @State private var isSearchOpen = false
    /// The counter tapped to show only its group; tapping it again shows everything
    @State private var filter: DashboardFilter?
    /// True for the moments after launch while iCloud hands over the notes, so an empty list is not
    /// taken for "nothing planned"
    @State private var isSettling = true
    /// Everything ticked earlier starts folded away
    @AppStorage("dashboard.completedExpanded") private var completedExpanded = false

    private let upcomingDays = 14

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let terms = DashboardSearch.terms(query)
        let items = terms.isEmpty
            ? storage.agendaItems
            : DashboardSearch.filter(storage.agendaItems, terms: terms,
                                     notes: Dictionary(uniqueKeysWithValues: storage.notes.map { ($0.id, $0) }))
        let snapshot = DashboardSnapshot(notes: storage.notes, items: items,
                                         today: today, upcomingDays: upcomingDays, calendar: calendar)

        NavigationStack {
            List {
                if !snapshot.isEmpty {
                    Section {
                        Counters(snapshot: snapshot, filter: $filter)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if let filter, snapshot.count(for: filter) == 0, !snapshot.isEmpty {
                    ContentUnavailableView(filter.emptyText, systemImage: "checkmark.circle")
                        .listRowBackground(Color.clear)
                }
                if snapshot.isEmpty && !terms.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else if snapshot.isEmpty && isSettling && storage.notes.isEmpty {
                    ProgressView("Loading notes")
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if snapshot.isEmpty {
                    ContentUnavailableView(
                        "Nothing planned",
                        systemImage: "checkmark.circle",
                        description: Text("Write a to-do or a day in any note and it shows up here.")
                    )
                    .listRowBackground(Color.clear)
                }
                if filter == nil || filter == .overdue, !snapshot.overdue.isEmpty {
                    Section("Overdue") {
                        rows(snapshot.overdue, in: snapshot, showDate: true)
                    }
                }
                if filter == nil || filter == .today, !snapshot.dueToday.isEmpty {
                    Section("Today") {
                        rows(snapshot.dueToday, in: snapshot)
                    }
                }
                ForEach(filter == nil || filter == .upcoming ? snapshot.upcomingByDay : [], id: \.day) { group in
                    Section(DayLabel.text(for: group.day, today: today, calendar: calendar)) {
                        rows(group.items, in: snapshot)
                    }
                }
                // A note with one open to-do needs no heading: its row names the note
                let showUndated = filter == nil
                let singles = showUndated ? snapshot.undatedTodosByNote.filter { $0.items.count == 1 } : []
                if !singles.isEmpty {
                    Section("To-do") {
                        rows(singles.flatMap(\.items), in: snapshot)
                    }
                }
                ForEach(showUndated ? snapshot.undatedTodosByNote.filter { $0.items.count != 1 } : [], id: \.note.id) { group in
                    Section(group.note.displayTitle) {
                        rows(group.items, in: snapshot, showNote: false)
                    }
                }
                // The To-dos counter counts every open to-do, dated or not, so its list shows them all by note
                if filter == .todos {
                    ForEach(snapshot.openTodosByNote(items: items), id: \.note.id) { group in
                        Section(group.note.displayTitle) {
                            rows(group.items, in: snapshot, showDate: true, showNote: false)
                        }
                    }
                }
                if filter == nil, !snapshot.completed.isEmpty {
                    Section {
                        DisclosureGroup("Completed (\(snapshot.completed.count))", isExpanded: $completedExpanded) {
                            rows(snapshot.completed, in: snapshot)
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
            // The large title of the other tabs, which shrinks as the list scrolls; tight rows leave the screen to the items
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListRowHeight, 34)
            .task { try? await Task.sleep(for: .seconds(3)); isSettling = false }
            .modifier(OptionalSearch(text: $query, isOpen: $isSearchOpen))
            .navigationDestination(for: Note.ID.self) { NoteEditorScreen(noteID: $0) }
            .refreshable { NotesFolder.refresh() }
            // One button on each side, so the centered title has room and sits where it does on the other tabs
            .toolbar {
                if !isSearchOpen {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { isSearchOpen = true } label: { Label("Search", systemImage: "magnifyingglass") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isCapturing = true } label: { Label("Quick Capture", systemImage: "square.and.pencil") }
                }
            }
            .sheet(isPresented: $isCapturing) { CaptureSheet() }
        }
    }

    @ViewBuilder
    private func rows(_ items: [AgendaItem], in snapshot: DashboardSnapshot, showDate: Bool = false, showNote: Bool = true) -> some View {
        ForEach(items) { item in
            AgendaRow(
                item: item,
                note: snapshot.notesByID[item.noteID],
                dateLabel: showDate ? item.date.map { DayLabel.text(for: $0) } : nil,
                showNote: showNote
            )
        }
    }
}

/// The groups a counter can narrow the Dashboard to
enum DashboardFilter: Hashable {
    case overdue, today, upcoming, todos

    var emptyText: String {
        switch self {
        case .overdue: "Nothing overdue."
        case .today: "Nothing today."
        case .upcoming: "Nothing upcoming."
        case .todos: "No open to-dos."
        }
    }
}

extension DashboardSnapshot {
    /// How many items the Dashboard shows for a counter
    func count(for filter: DashboardFilter) -> Int {
        switch filter {
        case .overdue: overdue.count
        case .today: dueToday.count
        case .upcoming: upcomingByDay.reduce(0) { $0 + $1.items.count }
        case .todos: openTodoCount
        }
    }

    /// Every unticked to-do, dated or not, under the note it is written in, newest note first
    func openTodosByNote(items: [AgendaItem]) -> [(note: Note, items: [AgendaItem])] {
        Dictionary(grouping: items.filter { $0.isTodo && !$0.isDone }) { $0.noteID }
            .compactMap { id, items in notesByID[id].map { (note: $0, items: items.sorted { $0.lineIndex < $1.lineIndex }) } }
            .sorted { $0.note.updatedAt > $1.note.updatedAt }
    }
}

/// One line of four counts, so the summary costs a single row. Each one is a button that narrows the
/// Dashboard to its group; the one in use looks selected, and tapping it again shows everything.
private struct Counters: View {
    let snapshot: DashboardSnapshot
    @Binding var filter: DashboardFilter?

    var body: some View {
        HStack(spacing: 4) {
            counter("Overdue", snapshot.overdueCount, tint: CounterColors.orange, for: .overdue)
            counter("Today", snapshot.openTodayCount, tint: CounterColors.blue, for: .today)
            counter("Upcoming", snapshot.upcomingCount, tint: CounterColors.purple, for: .upcoming)
            counter("To-dos", snapshot.openTodoCount, tint: CounterColors.green, for: .todos)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func counter(_ title: String, _ value: Int, tint: Color, for target: DashboardFilter) -> some View {
        let selected = filter == target
        return Button {
            withAnimation(.snappy) { filter = selected ? nil : target }
        } label: {
            VStack(spacing: 0) {
                Text("\(value)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? CounterColors.onTint : tint)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(selected ? CounterColors.onTint : CounterColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(CounterButtonStyle(tint: tint, selected: selected))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel("\(value) \(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "Shows everything again" : "Shows only \(title)")
    }
}

/// Colors for the counters, the same accessible palette the Mac app uses. Every text and background
/// pair here is at least 4.5:1 (checked in both appearances), 
private enum CounterColors {
    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        })
    }
    static let orange = dynamic(light: (194, 65, 12), dark: (251, 146, 60))
    static let blue = dynamic(light: (29, 78, 216), dark: (96, 165, 250))
    static let purple = dynamic(light: (107, 33, 168), dark: (192, 132, 252))
    static let green = dynamic(light: (22, 101, 52), dark: (74, 222, 128))
    static let secondaryText = dynamic(light: (71, 85, 105), dark: (203, 213, 225))
    /// Text on a selected counter's tint: white on the dark tints of light mode, black on the light tints of dark mode
    static let onTint = dynamic(light: (255, 255, 255), dark: (0, 0, 0))
}

/// A rounded counter in the system's grouped-row fill and corner radius, with no outline of its own,
/// as Apple's own controls have none; filled with its tint while selected
private struct CounterButtonStyle: ButtonStyle {
    let tint: Color
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .background(selected ? tint : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Adds the search bar only once it has been asked for, and drops it, and the text, when it closes
private struct OptionalSearch: ViewModifier {
    @Binding var text: String
    @Binding var isOpen: Bool
    @State private var isPresented = true

    func body(content: Content) -> some View {
        if isOpen {
            content
                .searchable(text: $text, isPresented: $isPresented, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search the dashboard")
                .onChange(of: isPresented) { _, presented in
                    if !presented { text = ""; isOpen = false; isPresented = true }
                }
        } else {
            content
        }
    }
}

/// One to-do or dated line: tick it, or open the note it came from.
struct AgendaRow: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    let item: AgendaItem
    let note: Note?
    var dateLabel: String?
    var showNote = true
    @State private var isEditingDate = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if item.isTodo {
                Button {
                    storage.toggleChecklistItem(noteID: item.noteID, lineIndex: item.lineIndex)
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isDone ? .green : .secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.isDone ? "Mark as not done" : "Mark as done")
            } else {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }

            NavigationLink(value: item.noteID) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                    let caption = [dateLabel, showNote ? note?.displayTitle : nil].compactMap { $0 }
                    if !caption.isEmpty {
                        Text(caption.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button { isEditingDate = true } label: { Label("Date", systemImage: "calendar") }
                .tint(.orange)
        }
        .contextMenu {
            Button { isEditingDate = true } label: {
                Label(item.date == nil ? "Set a Date" : "Change the Date", systemImage: "calendar")
            }
        }
        .sheet(isPresented: $isEditingDate) {
            DateEditorSheet(item: item) { storage.setDate(noteID: item.noteID, lineIndex: item.lineIndex, to: $0) }
        }
    }
}

/// Sets the day of a to-do: quick picks, a calendar, and what was changed before.
private struct DateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: AgendaItem
    let onPick: (Date) -> Void
    @State private var picked: Date

    init(item: AgendaItem, onPick: @escaping (Date) -> Void) {
        self.item = item
        self.onPick = onPick
        _picked = State(initialValue: item.date ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(QuickDates.options(today: Date()), id: \.title) { option in
                        Button(option.title) { pick(option.day) }
                    }
                }
                Section {
                    DatePicker("Date", selection: $picked, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .onChange(of: picked) { _, day in pick(day) }
                }
                let history = NoteStorageManager.shared.dateHistory(for: item)
                if !history.isEmpty {
                    Section("History") {
                        ForEach(history.suffix(5).reversed()) { change in
                            Text(change.summary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(item.date == nil ? "Set a Date" : "Change the Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
        .presentationDetents([.large])
    }

    private func pick(_ day: Date) {
        onPick(day)
        dismiss()
    }
}

enum DayLabel {
    static func text(for day: Date, today: Date = Calendar.current.startOfDay(for: Date()), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: today) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
