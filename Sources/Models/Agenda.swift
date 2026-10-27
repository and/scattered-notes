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
}

/// Scans note content for checklist lines and lines that mention a day.
///
/// Recognised day formats (case-insensitive):
/// - `2026-10-28` (optionally prefixed with `@`)
/// - `today`, `tonight`, `tomorrow`
/// - weekday names, e.g. `friday`, `next friday`
/// - `next week` (seven days after the note was written)
/// - month and day, e.g. `oct 28`, `28 october`, `Oct 28th`
///
/// Relative words resolve against the note's creation date, so "tomorrow" in a note
/// written on Monday means Tuesday even when read later in the week.
public enum AgendaExtractor {
    public static func items(from note: Note, calendar: Calendar = .current) -> [AgendaItem] {
        let reference = calendar.startOfDay(for: note.createdAt)
        var result: [AgendaItem] = []

        for (index, rawLine) in note.content.components(separatedBy: .newlines).enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let checklist = checklistState(of: trimmed)
            let date = parseDate(in: trimmed, reference: reference, calendar: calendar)
            guard checklist != nil || date != nil else { continue }

            let text = displayText(for: trimmed)
            guard !text.isEmpty else { continue }

            result.append(AgendaItem(
                noteID: note.id,
                lineIndex: index,
                text: text,
                isTodo: checklist != nil,
                isDone: checklist ?? false,
                date: date
            ))
        }
        return result
    }

    /// nil when the line is not a checklist item, otherwise whether it is checked.
    static func checklistState(of line: String) -> Bool? {
        for prefix in ["- [ ]", "* [ ]"] where line.hasPrefix(prefix) { return false }
        for prefix in ["- [x]", "- [X]", "* [x]", "* [X]"] where line.hasPrefix(prefix) { return true }
        return nil
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

    private static let nextWeekRegex = try! NSRegularExpression(
        pattern: "\\bnext\\s+week\\b", options: .caseInsensitive)

    static func parseDate(in line: String, reference: Date, calendar: Calendar) -> Date? {
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
