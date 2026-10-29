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
    /// Start of the day relative words in the line are measured from: when the line was written
    public let writtenOn: Date
    /// Start of the day a checked line was ticked, from its ✅ marker
    public let doneOn: Date?
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
/// Relative words resolve against the day the line was written. The app writes that day into the line
/// when the note is saved (see `resolvingDates`), as `📅 2026-10-28` for the day a line refers to and
/// `✅ 2026-10-28` for the day it was ticked, the markers the Obsidian Tasks plugin uses. So "tomorrow"
/// written on Monday means Tuesday even when read or edited later. A line without a `📅` marker,
/// e.g. one written in another editor, resolves against the note's last update.
public enum AgendaExtractor {
    public static func items(from note: Note, calendar: Calendar = .current) -> [AgendaItem] {
        let fallback = calendar.startOfDay(for: note.updatedAt)
        var result: [AgendaItem] = []
        var previousDate: Date?

        for (index, rawLine) in note.content.components(separatedBy: .newlines).enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let checklist = checklistState(of: trimmed)
            let marks = markers(in: trimmed, calendar: calendar)
            let reference = fallback
            let date = marks.due ?? parseDate(in: withoutMarkers(trimmed), reference: reference, previous: previousDate, calendar: calendar)
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
                writtenOn: reference,
                doneOn: (checklist ?? false) ? marks.done : nil
            ))
        }
        return result
    }

    // MARK: - Date markers
    private static let dueMarkerRegex = try! NSRegularExpression(pattern: "\\s*📅\\s*(\\d{4})-(\\d{2})-(\\d{2})")
    private static let doneMarkerRegex = try! NSRegularExpression(pattern: "\\s*✅\\s*(\\d{4})-(\\d{2})-(\\d{2})")

    /// The days written into a line by `📅` and `✅`, as start of day.
    static func markers(in line: String, calendar: Calendar) -> (due: Date?, done: Date?) {
        func day(_ regex: NSRegularExpression) -> Date? {
            let ns = line as NSString
            guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let parts = (1...3).map { Int(ns.substring(with: m.range(at: $0))) }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        return (day(dueMarkerRegex), day(doneMarkerRegex))
    }

    /// The UTF-16 ranges of the `📅` and `✅` markers in a text, sorted.
    static func markerRanges(in text: String) -> [NSRange] {
        let whole = NSRange(text.startIndex..., in: text)
        return [dueMarkerRegex, doneMarkerRegex]
            .flatMap { $0.matches(in: text, range: whole).map(\.range) }
            .sorted { $0.location < $1.location }
    }

    /// Whether two texts are the same apart from the markers the app writes into lines.
    public static func sameIgnoringMarkers(_ a: String, _ b: String) -> Bool {
        a == b || withoutMarkers(a) == withoutMarkers(b)
    }

    /// The line without its `📅` and `✅` markers.
    static func withoutMarkers(_ line: String) -> String {
        var text = line
        for regex in [dueMarkerRegex, doneMarkerRegex] {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return text
    }

    private static func marker(_ symbol: String, _ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: " %@ %04d-%02d-%02d", symbol, c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The note text with the days written into it. A line whose date comes from a relative word, such as
    /// "call the bank tomorrow", gets `📅` and the day it resolves to; a ticked checklist line gets `✅` and
    /// the day it was ticked; an unticked one loses its `✅`. Lines are matched with `previous`, the text as
    /// last saved, by their words, so a line keeps its days when the editor's copy lacks the markers or the
    /// line is moved. A line already in `previous` without markers counts as written at `previousUpdatedAt`;
    /// any other line was written `now`. Only lines that need a marker change.
    public static func resolvingDates(
        in content: String, previous: String?, previousUpdatedAt: Date?, now: Date, calendar: Calendar = .current
    ) -> String {
        let today = calendar.startOfDay(for: now)
        let before = previousUpdatedAt.map { calendar.startOfDay(for: $0) } ?? today
        var known: [String: [(due: Date?, done: Date?)]] = [:]
        for raw in (previous ?? "").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            known[displayText(for: line), default: []].append(markers(in: line, calendar: calendar))
        }

        var lines = content.components(separatedBy: "\n")
        var previousDate: Date?
        for index in lines.indices {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let key = displayText(for: line)
            guard !key.isEmpty else { continue }
            let old = known[key]?.isEmpty == false ? known[key]?.removeFirst() : nil
            let marks = markers(in: line, calendar: calendar)

            var due = marks.due ?? old?.due
            let found = due == nil
                ? parseDay(in: withoutMarkers(line), reference: old == nil ? today : before, previous: previousDate, calendar: calendar)
                : nil
            if let found, found.isRelative { due = found.date }
            if let day = due ?? found?.date { previousDate = day }

            var done = marks.done
            switch checklistState(of: line) {
            case true?: done = marks.done ?? old?.done ?? (old == nil ? today : before)
            case false?: done = nil
            case nil: break
            }

            guard due != marks.due || done != marks.done else { continue }
            var text = withoutMarkers(lines[index])
            while let last = text.last, last.isWhitespace { text.removeLast() }
            if let due { text += marker("📅", due, calendar: calendar) }
            if let done { text += marker("✅", done, calendar: calendar) }
            lines[index] = text
        }
        return lines.joined(separator: "\n")
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
        var text = withoutMarkers(line)
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

    private static let dayOfMonthRegex = try! NSRegularExpression(
        pattern: "\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+of\\s+(?:the\\s+)?(next|this)\\s+month\\b", options: .caseInsensitive)
    private static let endOfMonthRegex = try! NSRegularExpression(
        pattern: "\\bend\\s+of\\s+(?:the\\s+)?(next\\s+|this\\s+)?month\\b", options: .caseInsensitive)
    private static let theOrdinalRegex = try! NSRegularExpression(
        pattern: "\\bthe\\s+(\\d{1,2})(?:st|nd|rd|th)\\b", options: .caseInsensitive)
    private static let dayAfterTomorrowRegex = try! NSRegularExpression(
        pattern: "\\bday\\s+after\\s+tomorrow\\b", options: .caseInsensitive)
    private static let dayAfterRegex = try! NSRegularExpression(
        pattern: "\\bday\\s+after\\b", options: .caseInsensitive)
    private static let inIntervalRegex = try! NSRegularExpression(
        pattern: "\\bin\\s+(\\d{1,3})\\s+(day|week)s?\\b", options: .caseInsensitive)
    private static let nextWeekRegex = try! NSRegularExpression(
        pattern: "\\bnext\\s+week\\b", options: .caseInsensitive)

    static func parseDate(in line: String, reference: Date, previous: Date? = nil, calendar: Calendar) -> Date? {
        parseDay(in: line, reference: reference, previous: previous, calendar: calendar)?.date
    }

    /// The day a line refers to, and whether it is relative to when the line was written ("tomorrow",
    /// "friday") rather than a fixed date ("2026-10-28", "oct 28").
    static func parseDay(in line: String, reference: Date, previous: Date? = nil, calendar: Calendar) -> (date: Date, isRelative: Bool)? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
            ns.substring(with: match.range(at: index)).lowercased()
        }

        if let m = isoRegex.firstMatch(in: line, range: range) {
            let comps = DateComponents(year: Int(group(m, 1)), month: Int(group(m, 2)), day: Int(group(m, 3)))
            if let date = calendar.date(from: comps) { return (date, false) }
        }

        if let m = monthDayRegex.firstMatch(in: line, range: range) {
            if let date = resolveMonthDay(month: group(m, 1), day: Int(group(m, 2)), reference: reference, calendar: calendar) {
                return (date, false)
            }
        }

        if let m = dayMonthRegex.firstMatch(in: line, range: range) {
            if let date = resolveMonthDay(month: group(m, 2), day: Int(group(m, 1)), reference: reference, calendar: calendar) {
                return (date, false)
            }
        }

        // "22nd of the next month", "22 of this month"
        if let m = dayOfMonthRegex.firstMatch(in: line, range: range), let day = Int(group(m, 1)),
           let date = dayOfMonth(day, monthsAhead: group(m, 2) == "next" ? 1 : 0, of: reference, calendar: calendar) {
            return relative(date)
        }

        // "end of the month", "end of next month"
        if let m = endOfMonthRegex.firstMatch(in: line, range: range) {
            let ahead = m.range(at: 1).location != NSNotFound && group(m, 1).hasPrefix("next") ? 1 : 0
            if let first = dayOfMonth(1, monthsAhead: ahead, of: reference, calendar: calendar),
               let days = calendar.range(of: .day, in: .month, for: first),
               let date = dayOfMonth(days.count, monthsAhead: ahead, of: reference, calendar: calendar) {
                return relative(date)
            }
        }

        // "on the 22nd": the next such day of a month, today included
        if let m = theOrdinalRegex.firstMatch(in: line, range: range), let day = Int(group(m, 1)) {
            for ahead in 0...2 {
                if let date = dayOfMonth(day, monthsAhead: ahead, of: reference, calendar: calendar), date >= reference {
                    return relative(date)
                }
            }
        }

        if dayAfterTomorrowRegex.firstMatch(in: line, range: range) != nil {
            return relative(calendar.date(byAdding: .day, value: 2, to: reference))
        }

        // "the day after" continues from the dated line above, e.g. "buy milk today" then "bake the day after"
        if dayAfterRegex.firstMatch(in: line, range: range) != nil {
            return relative(calendar.date(byAdding: .day, value: 1, to: previous ?? reference))
        }

        if let m = inIntervalRegex.firstMatch(in: line, range: range), let count = Int(group(m, 1)) {
            return relative(calendar.date(byAdding: .day, value: group(m, 2) == "week" ? count * 7 : count, to: reference))
        }

        if let m = relativeRegex.firstMatch(in: line, range: range) {
            let offset = group(m, 1) == "tomorrow" ? 1 : 0
            return relative(calendar.date(byAdding: .day, value: offset, to: reference))
        }

        if let m = weekdayRegex.firstMatch(in: line, range: range),
           let target = weekdays.firstIndex(of: group(m, 2)) {
            let current = calendar.component(.weekday, from: reference) - 1
            var offset = (target - current + 7) % 7
            if m.range(at: 1).location != NSNotFound {
                offset += 7
            }
            return relative(calendar.date(byAdding: .day, value: offset, to: reference))
        }

        if nextWeekRegex.firstMatch(in: line, range: range) != nil {
            return relative(calendar.date(byAdding: .day, value: 7, to: reference))
        }

        return nil
    }

    /// The `day` of the month `monthsAhead` months after the one `reference` is in; nil when the month has no such day.
    private static func dayOfMonth(_ day: Int, monthsAhead: Int, of reference: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day),
              let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: reference)),
              let month = calendar.date(byAdding: .month, value: monthsAhead, to: thisMonth) else { return nil }
        var parts = calendar.dateComponents([.year, .month], from: month)
        parts.day = day
        guard let date = calendar.date(from: parts),
              calendar.component(.month, from: date) == calendar.component(.month, from: month) else { return nil }
        return date
    }

    private static func relative(_ date: Date?) -> (date: Date, isRelative: Bool)? {
        date.map { ($0, true) }
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
