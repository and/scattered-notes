import Foundation

/// How often a to-do repeats: "every day", "every 3 days", "every weekday", "every monday and thursday",
/// "every 2 weeks", "every month", "every year".
///
/// A person writes it in plain words anywhere on a to-do line ("log daily food", "water plants every
/// 3 days"); `find(in:)` reads those words. The app then writes the rule into the line as `🔁 every day`, and
/// `parse(_:)` reads that back. Both go through the same patterns, so what the app writes it also understands.
public struct Recurrence: Equatable, Sendable {
    public enum Unit: Sendable { case day, week, month, year }

    public let unit: Unit
    /// Every `interval` days, weeks, months or years
    public let interval: Int
    /// For a weekly rule that names days, those days as `Calendar` weekday numbers (1 is Sunday), sorted
    public let weekdays: [Int]

    public init(unit: Unit, interval: Int = 1, weekdays: [Int] = []) {
        self.unit = unit
        self.interval = max(1, interval)
        self.weekdays = Array(Set(weekdays)).sorted()
    }

    // MARK: - Text

    private static let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let weekdayNumbers: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tues": 3, "tue": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thurs": 5, "thur": 5, "thu": 5,
        "friday": 6, "fri": 6, "saturday": 7, "sat": 7,
    ]

    /// The rule as the app writes it into a line. `parse(text)` gives the same rule back.
    public var text: String {
        switch unit {
        case .day: return interval == 1 ? "every day" : "every \(interval) days"
        case .week:
            if weekdays == [2, 3, 4, 5, 6] { return "every weekday" }
            if weekdays == [1, 7] { return "every weekend" }
            if !weekdays.isEmpty {
                // Monday first, as the week is read
                let ordered = weekdays.sorted { (($0 + 5) % 7) < (($1 + 5) % 7) }.map { Self.dayNames[$0 - 1] }
                if ordered.count == 1 { return "every \(ordered[0])" }
                return "every " + ordered.dropLast().joined(separator: ", ") + " and " + ordered.last!
            }
            return interval == 1 ? "every week" : "every \(interval) weeks"
        case .month: return interval == 1 ? "every month" : "every \(interval) months"
        case .year: return interval == 1 ? "every year" : "every \(interval) years"
        }
    }

    // MARK: - Reading words

    private static let namePattern = "(?:monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat|sunday|sun)s?"
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }
    private static let everyOther = regex("\\bevery\\s+(?:other|second)\\s+(day|week|month|year)\\b")
    private static let everyN = regex("\\bevery\\s+(\\d{1,3})\\s+(day|week|month|year)s?\\b")
    private static let everyUnit = regex("\\b(?:every|each)\\s+(day|week|month|year)\\b|\\b(everyday)\\b")
    private static let everyWeekday = regex("\\bevery\\s+weekdays?\\b")
    private static let everyWeekend = regex("\\bevery\\s+weekends?\\b")
    private static let everyNames = regex("\\bevery\\s+(" + namePattern + "(?:\\s*(?:,|&|\\band\\b)\\s*" + namePattern + ")*)\\b")
    private static let everyPartOfDay = regex("\\bevery\\s+(?:morning|afternoon|evening|night)\\b")
    private static let adverb = regex("\\b(daily|weekly|monthly|yearly|annually|fortnightly|bi-?weekly)\\b")
    private static let nameInList = regex(namePattern)

    private static func unit(_ word: String) -> Unit {
        switch word.lowercased() {
        case "week": return .week
        case "month": return .month
        case "year": return .year
        default: return .day
        }
    }

    /// The rule written in plain words somewhere in `text`, or nil. "log daily food" is every day, "water
    /// plants every 3 days" is every 3 days, "gym every monday and thursday" is those two days.
    public static func find(in text: String) -> Recurrence? {
        guard text.count >= 5 else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : (text as NSString).substring(with: range)
        }
        if let m = everyOther.firstMatch(in: text, range: whole), let u = group(m, 1) {
            return Recurrence(unit: unit(u), interval: 2)
        }
        if let m = everyN.firstMatch(in: text, range: whole), let n = group(m, 1).flatMap({ Int($0) }), let u = group(m, 2), n >= 1 {
            return Recurrence(unit: unit(u), interval: n)
        }
        if let m = everyUnit.firstMatch(in: text, range: whole) {
            return Recurrence(unit: unit(group(m, 1) ?? "day"))
        }
        if everyWeekday.firstMatch(in: text, range: whole) != nil { return Recurrence(unit: .week, weekdays: [2, 3, 4, 5, 6]) }
        if everyWeekend.firstMatch(in: text, range: whole) != nil { return Recurrence(unit: .week, weekdays: [1, 7]) }
        if let m = everyNames.firstMatch(in: text, range: whole), let list = group(m, 1) {
            let listRange = NSRange(list.startIndex..., in: list)
            let days = nameInList.matches(in: list, range: listRange).compactMap { match -> Int? in
                var word = (list as NSString).substring(with: match.range).lowercased()
                if weekdayNumbers[word] == nil, word.hasSuffix("s") { word.removeLast() }
                return weekdayNumbers[word]
            }
            if !days.isEmpty { return Recurrence(unit: .week, weekdays: days) }
        }
        if everyPartOfDay.firstMatch(in: text, range: whole) != nil { return Recurrence(unit: .day) }
        if let m = adverb.firstMatch(in: text, range: whole), let word = group(m, 1)?.lowercased() {
            switch word {
            case "daily": return Recurrence(unit: .day)
            case "weekly": return Recurrence(unit: .week)
            case "monthly": return Recurrence(unit: .month)
            case "fortnightly", "biweekly", "bi-weekly": return Recurrence(unit: .week, interval: 2)
            default: return Recurrence(unit: .year)
            }
        }
        return nil
    }

    // MARK: - Days

    /// The first day on or after `day` the rule falls on. Only a rule that names weekdays can skip days.
    public func firstDay(onOrAfter day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        guard unit == .week, !weekdays.isEmpty else { return start }
        for offset in 0..<7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { break }
            if weekdays.contains(calendar.component(.weekday, from: candidate)) { return candidate }
        }
        return start
    }

    /// The days from `start` through `end` the rule falls on, oldest first. `start` is the first day of the
    /// series: every step is counted from it, so "every 3 days" keeps its rhythm. Bounded, so a series
    /// started years ago cannot make a huge list.
    public func days(from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard first <= last else { return [] }
        var result: [Date] = []
        let limit = 4000

        if unit == .week, !weekdays.isEmpty {
            var day = first
            var steps = 0
            // Counting from the series start, only the most recent days matter for a very old series
            if let span = calendar.dateComponents([.day], from: first, to: last).day, span > limit,
               let recent = calendar.date(byAdding: .day, value: -limit, to: last) {
                day = recent
            }
            while day <= last, steps < limit + 7 {
                if weekdays.contains(calendar.component(.weekday, from: day)) { result.append(day) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                steps += 1
            }
            return result
        }

        let component: Calendar.Component
        var step = interval
        switch unit {
        case .day: component = .day
        case .week: component = .day; step = interval * 7
        case .month: component = .month
        case .year: component = .year
        }
        var k = 0
        // Skip ahead for an old series so only the last `limit` steps are walked
        if unit == .day || unit == .week, let span = calendar.dateComponents([.day], from: first, to: last).day {
            let steps = span / step
            if steps > limit { k = steps - limit }
        }
        var count = 0
        while count < limit * 2 {
            count += 1
            // Each day is counted from the start, so the end of a short month never shifts later ones
            guard let day = calendar.date(byAdding: component, value: k * step, to: first) else { break }
            if day > last { break }
            result.append(day)
            k += 1
        }
        return result
    }

    /// The first day after `day` the rule falls on, counting from the series start `start`
    public func next(after day: Date, from start: Date, calendar: Calendar = .current) -> Date? {
        let after = calendar.startOfDay(for: day)
        let horizon: Int
        switch unit {
        case .day: horizon = interval + 1
        case .week: horizon = weekdays.isEmpty ? interval * 7 + 7 : 8
        case .month: horizon = interval * 31 + 31
        case .year: horizon = interval * 366 + 366
        }
        guard let end = calendar.date(byAdding: .day, value: horizon, to: after) else { return nil }
        // A start still ahead of `day` is itself the next day
        let from = calendar.startOfDay(for: start)
        if from > after { return firstDay(onOrAfter: from, calendar: calendar) }
        return days(from: from, through: end, calendar: calendar).first { $0 > after }
    }
}
