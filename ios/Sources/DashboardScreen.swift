import SwiftUI

/// Overdue, today, the next 14 days and open to-dos from every note, as on the Mac Dashboard.
struct DashboardScreen: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    @State private var isCapturing = false
    @State private var query = ""
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
                        Counters(snapshot: snapshot)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if snapshot.isEmpty && !terms.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else if snapshot.isEmpty {
                    ContentUnavailableView(
                        "Nothing planned",
                        systemImage: "checkmark.circle",
                        description: Text("Write a to-do or a day in any note and it shows up here.")
                    )
                    .listRowBackground(Color.clear)
                }
                if !snapshot.overdue.isEmpty {
                    Section("Overdue") {
                        rows(snapshot.overdue, in: snapshot, showDate: true)
                    }
                }
                if !snapshot.dueToday.isEmpty {
                    Section("Today") {
                        rows(snapshot.dueToday, in: snapshot)
                    }
                }
                ForEach(snapshot.upcomingByDay, id: \.day) { group in
                    Section(DayLabel.text(for: group.day, today: today, calendar: calendar)) {
                        rows(group.items, in: snapshot)
                    }
                }
                // A note with one open to-do needs no heading: its row names the note
                let singles = snapshot.undatedTodosByNote.filter { $0.items.count == 1 }
                if !singles.isEmpty {
                    Section("To-do") {
                        rows(singles.flatMap(\.items), in: snapshot)
                    }
                }
                ForEach(snapshot.undatedTodosByNote.filter { $0.items.count != 1 }, id: \.note.id) { group in
                    Section(group.note.displayTitle) {
                        rows(group.items, in: snapshot, showNote: false)
                    }
                }
                if !snapshot.completed.isEmpty {
                    Section {
                        DisclosureGroup("Completed (\(snapshot.completed.count))", isExpanded: $completedExpanded) {
                            rows(snapshot.completed, in: snapshot)
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
            .searchable(text: $query, prompt: "Search the dashboard")
            .navigationDestination(for: Note.ID.self) { NoteEditorScreen(noteID: $0) }
            .refreshable { NotesFolder.refresh() }
            .toolbar {
                Button { isCapturing = true } label: { Label("Quick Capture", systemImage: "square.and.pencil") }
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

private struct Counters: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        HStack(spacing: 8) {
            counter("Overdue", snapshot.overdueCount, tint: .orange)
            counter("Today", snapshot.openTodayCount, tint: .blue)
            counter("Upcoming", snapshot.upcomingCount, tint: .purple)
            counter("To-dos", snapshot.openTodoCount, tint: .green)
        }
        .padding(.vertical, 4)
    }

    private func counter(_ title: String, _ value: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.weight(.semibold))
                .foregroundStyle(value > 0 ? tint : .secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
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
