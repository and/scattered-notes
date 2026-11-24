import Foundation

/// The text of the phone's morning notification for one day: what is planned that day and how many to-dos
/// are overdue. Worked out from the notes as they are, for the day given, so the notification for a coming
/// day can be prepared ahead (a repeating to-do has an item on each of its days).
public struct MorningSummary: Equatable, Sendable {
    public let title: String
    public let body: String
    /// Open items planned for the day, and overdue to-dos (each line counted once)
    public let todayCount: Int
    public let overdueCount: Int

    /// How many of the day's items are named in the body before "+N more"
    public static let namedItems = 3

    /// The summary for `day`, or nil when nothing is planned that day and nothing is overdue
    public static func make(notes: [Note], day: Date, calendar: Calendar = .current) -> MorningSummary? {
        let start = calendar.startOfDay(for: day)
        var today: [AgendaItem] = []
        var overdueLines = Set<String>()
        for note in notes {
            // Read as on that day, so a repeating to-do has that day's item
            for item in AgendaExtractor.items(from: note, calendar: calendar, now: start) where !item.isDone {
                guard let date = item.date else { continue }
                if calendar.isDate(date, inSameDayAs: start) {
                    today.append(item)
                } else if date < start, item.isTodo {
                    // A repeating to-do missed on many days is one thing to catch up on, not many
                    overdueLines.insert("\(item.noteID.uuidString)-\(item.lineIndex)")
                }
            }
        }
        return make(today: today, overdueCount: overdueLines.count)
    }

    static func make(today: [AgendaItem], overdueCount: Int) -> MorningSummary? {
        guard !today.isEmpty || overdueCount > 0 else { return nil }
        // To-dos first, in the order they are written
        let ordered = today.filter(\.isTodo) + today.filter { !$0.isTodo }
        var title: String
        if ordered.isEmpty {
            title = "Nothing planned today"
        } else {
            let noun = ordered.allSatisfy(\.isTodo) ? (ordered.count == 1 ? "to-do" : "to-dos") : (ordered.count == 1 ? "thing" : "things")
            title = "\(ordered.count) \(noun) today"
        }
        if overdueCount > 0 { title += ", \(overdueCount) overdue" }

        var body: String
        if ordered.isEmpty {
            body = overdueCount == 1 ? "1 to-do is waiting from an earlier day." : "\(overdueCount) to-dos are waiting from earlier days."
        } else {
            body = ordered.prefix(namedItems).map(\.text).joined(separator: " · ")
            if ordered.count > namedItems { body += " · +\(ordered.count - namedItems) more" }
        }
        return MorningSummary(title: title, body: body, todayCount: ordered.count, overdueCount: overdueCount)
    }
}
