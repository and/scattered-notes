import Foundation

/// One change of the day a to-do refers to. The log of these is append-only: a change is never edited
/// or removed, so two devices can each add their own without ever disagreeing about the past.
public struct DateChange: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    /// When the change was made
    public let at: Date
    public let noteID: UUID
    /// The line's words (see `AgendaExtractor.lineKey`), because its line number moves
    public let lineText: String
    /// Start of the day before the change; nil when the line had no day
    public let from: Date?
    /// Start of the day after the change
    public let to: Date
    /// The device that made the change, which names the log file it was written to
    public let device: String

    public init(id: UUID = UUID(), at: Date, noteID: UUID, lineText: String, from: Date?, to: Date, device: String) {
        self.id = id
        self.at = at
        self.noteID = noteID
        self.lineText = lineText
        self.from = from
        self.to = to
        self.device = device
    }
}

/// The days the date picker offers without opening the calendar.
public enum QuickDates {
    public struct Option: Equatable, Sendable {
        public let title: String
        public let day: Date
    }

    /// Today, tomorrow and the coming Monday, as start of day
    public static func options(today: Date, calendar: Calendar = .current) -> [Option] {
        let start = calendar.startOfDay(for: today)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let nextMonday = calendar.nextDate(
            after: start, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime
        )!
        return [
            Option(title: "Today", day: start),
            Option(title: "Tomorrow", day: tomorrow),
            Option(title: "Next Monday", day: nextMonday),
        ]
    }
}

extension DateChange {
    /// One line for a history list, such as "Oct 28 → Nov 2 · 3 Nov, 10:44"
    public var summary: String {
        let day = Date.FormatStyle().month(.abbreviated).day()
        let when = Date.FormatStyle().day().month(.abbreviated).hour().minute()
        return "\(from.map { $0.formatted(day) } ?? "No day") → \(to.formatted(day)) · \(at.formatted(when))"
    }
}
