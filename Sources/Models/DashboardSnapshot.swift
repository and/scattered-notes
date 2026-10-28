import Foundation

/// Everything the dashboard shows, derived from one read of the agenda items, so a redraw scans
/// the notes at most once. Shared by the Mac and iOS dashboards
public struct DashboardSnapshot: Sendable {
    public let notesByID: [UUID: Note]
    public let overdue: [AgendaItem]
    public let dueToday: [AgendaItem]
    public let upcomingByDay: [(day: Date, items: [AgendaItem])]
    public let undatedTodosByNote: [(note: Note, items: [AgendaItem])]
    public let openTodoCount: Int

    public var upcomingCount: Int { upcomingByDay.reduce(0) { $0 + $1.items.count } }
    public var isEmpty: Bool { overdue.isEmpty && dueToday.isEmpty && upcomingByDay.isEmpty && undatedTodosByNote.isEmpty }

    public init(notes: [Note], items: [AgendaItem], today: Date, upcomingDays: Int, calendar: Calendar) {
        let lookup = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        notesByID = lookup
        overdue = items
            .filter { $0.isTodo && !$0.isDone && ($0.date.map { $0 < today } ?? false) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        dueToday = items
            .filter { $0.date.map { calendar.isDate($0, inSameDayAs: today) } ?? false }
            .sorted { !$0.isDone && $1.isDone }
        if let end = calendar.date(byAdding: .day, value: upcomingDays + 1, to: today),
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            let upcoming = items.filter { item in
                guard let date = item.date else { return false }
                return date >= tomorrow && date < end && !item.isDone
            }
            upcomingByDay = Dictionary(grouping: upcoming) { $0.date! }
                .sorted { $0.key < $1.key }
                .map { (day: $0.key, items: $0.value) }
        } else {
            upcomingByDay = []
        }
        let undated = items.filter { $0.isTodo && !$0.isDone && $0.date == nil }
        undatedTodosByNote = Dictionary(grouping: undated) { $0.noteID }
            .compactMap { id, items in lookup[id].map { (note: $0, items: items.sorted { $0.lineIndex < $1.lineIndex }) } }
            .sorted { $0.note.updatedAt > $1.note.updatedAt }
        openTodoCount = items.filter { $0.isTodo && !$0.isDone }.count
    }
}
