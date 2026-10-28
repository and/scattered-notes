import Foundation

/// A single line pulled out of a note for the dashboard: a checklist item, a dated plan, or both.
public struct AgendaItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(noteID.uuidString)-\(lineIndex)" }
    public let noteID: UUID
    public let lineIndex: Int
    public let text: String
    public let isTodo: Bool
    public let isDone: Bool
    /// Start of the day the line refers to, if it mentions one
    public let date: Date?
    /// Start of the day relative words in the line are measured from: when the line first appeared
    public let writtenOn: Date
}

/// Scans note content for checklist lines, plain lines that read as plans (see `isPlannedAction(_:)`),
/// and lines that mention a day.
///
/// Recognised day formats (case-insensitive):
/// - `2026-10-28` (optionally prefixed with `@`)
/// - `today`, `tonight`, `tomorrow`
/// - weekday names, e.g. `friday`, `next friday`
/// - `next week` (seven days after the line was written)
/// - `day after tomorrow`, `in 3 days`, `in 2 weeks`
/// - `the day after`, one day after the closest dated line above it
/// - month and day, e.g. `oct 28`, `28 october`, `Oct 28th`
///
/// Relative words resolve against the day the line was first written. `anchors` maps a line's
/// log key (see `logKey(for:)`) to that moment; lines without an anchor fall back to the note's
/// creation date. So "tomorrow" written on Monday means Tuesday even when read or edited later.
public enum AgendaExtractor {
    public static func items(from note: Note, anchors: [String: Date] = [:], calendar: Calendar = .current) -> [AgendaItem] {
        let created = calendar.startOfDay(for: note.createdAt)
        var result: [AgendaItem] = []
        var previousDate: Date?

        for (index, rawLine) in note.content.components(separatedBy: .newlines).enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let checklist = checklistState(of: trimmed)
            let reference = anchors[logKey(for: trimmed)].map { calendar.startOfDay(for: $0) } ?? created
            let date = parseDate(in: trimmed, reference: reference, previous: previousDate, calendar: calendar)
            if let date { previousDate = date }

            let text = displayText(for: trimmed)
            guard !text.isEmpty else { continue }
            let isTodo = checklist != nil || isPlannedAction(text)
            guard isTodo || date != nil else { continue }

            result.append(AgendaItem(
                noteID: note.id,
                lineIndex: index,
                text: text,
                isTodo: isTodo,
                isDone: checklist ?? false,
                date: date,
                writtenOn: reference
            ))
        }
        return result
    }

    /// Identifies a line across edits that do not touch its words, e.g. ticking its checkbox or moving it.
    public static func logKey(for line: String) -> String {
        displayText(for: line.trimmingCharacters(in: .whitespaces)).lowercased()
    }

    /// nil when the line is not a checklist item, otherwise whether it is checked.
    static func checklistState(of line: String) -> Bool? {
        for prefix in ["- [ ]", "* [ ]"] where line.hasPrefix(prefix) { return false }
        for prefix in ["- [x]", "- [X]", "* [x]", "* [X]"] where line.hasPrefix(prefix) { return true }
        return nil
    }

    /// Verbs that start a line written as an instruction to oneself, e.g. "fix the login bug"
    private static let actionVerbs = [
        "add", "ask", "book", "build", "buy", "call", "cancel", "check", "clean", "confirm", "contact",
        "create", "debug", "delete", "deploy", "draft", "email", "figure", "finish", "fix", "follow",
        "get", "install", "investigate", "look", "make", "move", "pay", "pick", "ping", "prepare",
        "print", "publish", "read", "refactor", "remind", "renew", "reply", "research", "review",
        "schedule", "send", "share", "ship", "sign", "submit", "try", "update", "upload", "visit", "write"
    ]
    private static let plannedActionRegex = try! NSRegularExpression(
        pattern: "^(?:to-?\\s?do\\b"
            + "|(?:(?:i|we)\\s+(?:am\\s+|are\\s+)?|(?:i|we)['’](?:m|re)\\s+)?"
            + "(?:needs?\\s+to|ha(?:ve|s)\\s+to|must|should|remember\\s+to|don['’]?t\\s+forget"
            + "|plan(?:ning)?\\s+to|going\\s+to|gonna|want\\s+to)\\s"
            + "|(?:i|we)(?:\\s+will|['’]ll)\\s"
            + "|(?:" + actionVerbs.joined(separator: "|") + ")\\s)",
        options: .caseInsensitive)

    /// Whether a plain line reads like something the writer plans to do, so it counts as a to-do without
    /// checklist syntax: it starts with an action verb ("fix the login bug"), an intent ("need to renew
    /// passport", "I'll call Sam") or "todo". Questions and lines ending in ":" are left out.
    static func isPlannedAction(_ text: String) -> Bool {
        guard !text.hasSuffix("?"), !text.hasSuffix(":") else { return false }
        return plannedActionRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let isoDateTokenRegex = try! NSRegularExpression(pattern: "\\s*@?\\b\\d{4}-\\d{2}-\\d{2}\\b")

    static func displayText(for line: String) -> String {
        var text = line
        for prefix in ["- [ ]", "* [ ]", "- [x]", "- [X]", "* [x]", "* [X]", "- ", "* ", "+ "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        // An explicit @2026-10-28 marker is metadata; the dashboard shows the date separately
        let range = NSRange(text.startIndex..., in: text)
        if let match = isoDateTokenRegex.firstMatch(in: text, range: range),
           let swiftRange = Range(match.range, in: text),
           text[swiftRange].contains("@") {
            text.removeSubrange(swiftRange)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Date Parsing
    private static let months = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
    ]
    private static let monthPattern =
        "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    private static let isoRegex = try! NSRegularExpression(pattern: "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b")
    private static let monthDayRegex = try! NSRegularExpression(
        pattern: "\\b" + monthPattern + "\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b", options: .caseInsensitive)
    private static let dayMonthRegex = try! NSRegularExpression(
        pattern: "\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?" + monthPattern + "\\b", options: .caseInsensitive)
    private static let relativeRegex = try! NSRegularExpression(
        pattern: "\\b(today|tonight|tomorrow)\\b", options: .caseInsensitive)
    private static let weekdayRegex = try! NSRegularExpression(
        pattern: "\\b(next\\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\\b", options: .caseInsensitive)

    private static let dayAfterTomorrowRegex = try! NSRegularExpression(
        pattern: "\\bday\\s+after\\s+tomorrow\\b", options: .caseInsensitive)
    private static let dayAfterRegex = try! NSRegularExpression(
        pattern: "\\bday\\s+after\\b", options: .caseInsensitive)
    private static let inIntervalRegex = try! NSRegularExpression(
        pattern: "\\bin\\s+(\\d{1,3})\\s+(day|week)s?\\b", options: .caseInsensitive)
    private static let nextWeekRegex = try! NSRegularExpression(
        pattern: "\\bnext\\s+week\\b", options: .caseInsensitive)

    static func parseDate(in line: String, reference: Date, previous: Date? = nil, calendar: Calendar) -> Date? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
            ns.substring(with: match.range(at: index)).lowercased()
        }

        if let m = isoRegex.firstMatch(in: line, range: range) {
            let comps = DateComponents(year: Int(group(m, 1)), month: Int(group(m, 2)), day: Int(group(m, 3)))
            if let date = calendar.date(from: comps) { return date }
        }

        if let m = monthDayRegex.firstMatch(in: line, range: range) {
            if let date = resolveMonthDay(month: group(m, 1), day: Int(group(m, 2)), reference: reference, calendar: calendar) {
                return date
            }
        }

        if let m = dayMonthRegex.firstMatch(in: line, range: range) {
            if let date = resolveMonthDay(month: group(m, 2), day: Int(group(m, 1)), reference: reference, calendar: calendar) {
                return date
            }
        }

        if dayAfterTomorrowRegex.firstMatch(in: line, range: range) != nil {
            return calendar.date(byAdding: .day, value: 2, to: reference)
        }

        // "the day after" continues from the dated line above, e.g. "buy milk today" then "bake the day after"
        if dayAfterRegex.firstMatch(in: line, range: range) != nil {
            return calendar.date(byAdding: .day, value: 1, to: previous ?? reference)
        }

        if let m = inIntervalRegex.firstMatch(in: line, range: range), let count = Int(group(m, 1)) {
            return calendar.date(byAdding: .day, value: group(m, 2) == "week" ? count * 7 : count, to: reference)
        }

        if let m = relativeRegex.firstMatch(in: line, range: range) {
            let offset = group(m, 1) == "tomorrow" ? 1 : 0
            return calendar.date(byAdding: .day, value: offset, to: reference)
        }

        if let m = weekdayRegex.firstMatch(in: line, range: range),
           let target = weekdays.firstIndex(of: group(m, 2)) {
            let current = calendar.component(.weekday, from: reference) - 1
            var offset = (target - current + 7) % 7
            if m.range(at: 1).location != NSNotFound {
                offset += 7
            }
            return calendar.date(byAdding: .day, value: offset, to: reference)
        }

        if nextWeekRegex.firstMatch(in: line, range: range) != nil {
            return calendar.date(byAdding: .day, value: 7, to: reference)
        }

        return nil
    }

    private static func resolveMonthDay(month: String, day: Int?, reference: Date, calendar: Calendar) -> Date? {
        guard let day, (1...31).contains(day),
              let monthIndex = months.firstIndex(of: String(month.prefix(3))) else { return nil }
        let year = calendar.component(.year, from: reference)
        guard let date = calendar.date(from: DateComponents(year: year, month: monthIndex + 1, day: day)),
              calendar.component(.day, from: date) == day else { return nil }
        // A date more than six months before the note was written most likely means next year
        if let cutoff = calendar.date(byAdding: .month, value: -6, to: reference), date < cutoff {
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
        return date
    }
}
