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
    /// Ticked items the sections above do not show, newest tick first; ones with no `✅` day come last
    public let completed: [AgendaItem]
    /// Items ticked today, including ones hidden by `showCompleted`
    public let completedTodayCount: Int
    /// Items planned for today that are ticked, including hidden ones
    public let doneForTodayCount: Int

    public var overdueCount: Int { overdue.filter { !$0.isDone }.count }
    public var openTodayCount: Int { dueToday.filter { !$0.isDone }.count }
    /// Whether something was planned for today and all of it is ticked
    public var isTodayDone: Bool { openTodayCount == 0 && doneForTodayCount > 0 }
    public var upcomingCount: Int { upcomingByDay.reduce(0) { $0 + $1.items.count } }
    public var isEmpty: Bool { overdue.isEmpty && dueToday.isEmpty && upcomingByDay.isEmpty && undatedTodosByNote.isEmpty }

    /// `doneToday` holds the IDs of items ticked today. With `showCompleted`, they stay in their
    /// section, struck through, until the day is over; without it, every ticked item is left out.
    public init(notes: [Note], items: [AgendaItem], today: Date, upcomingDays: Int, calendar: Calendar,
                doneToday: Set<String> = [], showCompleted: Bool = true) {
        let lookup = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        notesByID = lookup
        let shown = { (item: AgendaItem) in !item.isDone || (showCompleted && doneToday.contains(item.id)) }
        overdue = items
            .filter { $0.isTodo && shown($0) && ($0.date.map { $0 < today } ?? false) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        let datedToday = items.filter { $0.date.map { calendar.isDate($0, inSameDayAs: today) } ?? false }
        dueToday = datedToday
            .filter { !$0.isDone || showCompleted }
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
        let undated = items.filter { $0.isTodo && shown($0) && $0.date == nil }
        undatedTodosByNote = Dictionary(grouping: undated) { $0.noteID }
            .compactMap { id, items in lookup[id].map { (note: $0, items: items.sorted { $0.lineIndex < $1.lineIndex }) } }
            .sorted { $0.note.updatedAt > $1.note.updatedAt }
        openTodoCount = items.filter { $0.isTodo && !$0.isDone }.count
        let inPlace = Set((overdue + dueToday + undated).map(\.id))
        completed = items
            .filter { $0.isDone && !inPlace.contains($0.id) }
            .sorted { a, b in
                switch (a.doneOn, b.doneOn) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    let (ua, ub) = (lookup[a.noteID]?.updatedAt ?? .distantPast, lookup[b.noteID]?.updatedAt ?? .distantPast)
                    return ua != ub ? ua > ub : (a.noteID == b.noteID ? a.lineIndex < b.lineIndex : a.noteID.uuidString < b.noteID.uuidString)
                }
            }
        doneForTodayCount = datedToday.filter(\.isDone).count
        completedTodayCount = doneToday.union(datedToday.filter(\.isDone).map(\.id)).count
    }
}
