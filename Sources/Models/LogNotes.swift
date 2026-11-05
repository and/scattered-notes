import Foundation

/// A log note: a note whose first line starts with "Log -", kept like a log file, with the time each line was
/// written shown in a column at the left of the editor.
///
/// The times live in the note's file, at the start of each line, the way a log file has them:
/// `2026-11-05T11:34:07+05:30 ran 5k`. That is the ISO 8601 / RFC 3339 form with the writer's time zone offset, so
/// other log readers (`tail`, `lnav`, Console and the like) can read the file as it is. The editor takes the times
/// off the text and shows them in the column, so what is typed and what is read never includes them; saving puts
/// them back. A line gets its time when it first has text, and keeps it however it is edited afterwards. The
/// "Log -" heading line has no time. Lines written before the note became a log, or in another app, have no time
/// until they are edited. The first version wrote the time at the end of the line (`ran 5k ⏱ 2026-11-05 11:34`);
/// those are still read, and written in the new place when the line is next saved.
public enum LogLines {
    /// The time itself: date, `T` or a space, hours and minutes, optional seconds, optional `Z` or `+05:30`
    static let stampPattern = "(\\d{4})-(\\d{2})-(\\d{2})[T ](\\d{2}):(\\d{2})(?::(\\d{2}))?(Z|[+-]\\d{2}:?\\d{2})?"

    /// The time at the start of a line: always the full form, so an ordinary line is not mistaken for a stamped one
    private static let strictStamp = "(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(Z|[+-]\\d{2}:\\d{2})"
    private static let leadingRegex = try! NSRegularExpression(pattern: "^[ \\t]*" + strictStamp + "(?:[ \\t]|$)")
    private static let anyLeadingRegex = try! NSRegularExpression(pattern: "^[ \\t]*" + strictStamp + "(?:[ \\t]|$)", options: .anchorsMatchLines)

    /// The first version's marker at the end of a line, with the optional variation selector some keyboards add
    private static let markerRegex = try! NSRegularExpression(
        pattern: "[ \\t]*\u{23F1}\u{FE0F}?[ \\t]*" + stampPattern + "[ \\t]*$")

    private static let startRegex = try! NSRegularExpression(pattern: "^log\\s*[-\u{2013}\u{2014}]", options: .caseInsensitive)

    /// Whether the text is a log note: its first line that is not blank starts with "Log -" (any case, and a
    /// longer dash is fine)
    public static func isLog(_ content: String) -> Bool {
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            return isHeading(trimmed)
        }
        return false
    }

    /// The index of the "Log -" heading line, which is never given a time: the first line that is not blank, when it
    /// starts with "Log -". Later lines that start that way are entries like any other.
    static func headingIndex(in lines: [String]) -> Int? {
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        return isHeading(lines[first]) ? first : nil
    }

    private static func isHeading(_ line: String) -> Bool {
        let trimmed = withoutStamp(line).trimmingCharacters(in: .whitespaces)
        return startRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
    }

    /// A quick test that a line could start with a time, before the pattern is tried
    static func mayStartWithStamp(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first(where: { $0 != " " && $0 != "\t" }) else { return false }
        return first.value >= 0x30 && first.value <= 0x39 && text.utf8.count >= 20
    }

    /// The line without a time at its start or, in the first version's form, at its end
    public static func withoutStamp(_ line: String) -> String {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        if let match = leadingRegex.firstMatch(in: line, range: whole) { return ns.substring(from: match.range.upperBound) }
        if let match = markerRegex.firstMatch(in: line, range: whole) { return ns.substring(to: match.range.location) }
        return line
    }

    /// Whether a note is a log: "Log -" starts its title, or the first line of its text when it has no title of that kind
    public static func isLog(title: String, content: String) -> Bool {
        isLog(title) || isLog(content)
    }

    /// Whether the text holds a time marker, so `parse` has something to take off
    public static func hasStamps(_ content: String) -> Bool {
        content.unicodeScalars.contains { $0.value == 0x23F1 }
            || anyLeadingRegex.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) != nil
    }

    /// The text of a log note without its time markers, and the time of each line, `nil` for a line without one.
    /// There is one entry per line, always.
    public static func parse(_ content: String, calendar: Calendar = .current) -> (text: String, stamps: [Date?]) {
        var lines: [String] = []
        var stamps: [Date?] = []
        for line in content.components(separatedBy: "\n") {
            let ns = line as NSString
            let whole = NSRange(location: 0, length: ns.length)
            if let match = leadingRegex.firstMatch(in: line, range: whole) {
                stamps.append(date(match, in: ns, calendar: calendar))
                lines.append(ns.substring(from: match.range.upperBound))
            } else if let match = markerRegex.firstMatch(in: line, range: whole) {
                stamps.append(date(match, in: ns, calendar: calendar))
                lines.append(ns.substring(to: match.range.location))
            } else {
                stamps.append(nil)
                lines.append(line)
            }
        }
        return (lines.joined(separator: "\n"), stamps)
    }

    /// The time in a match of either marker form: groups 1 to 7 are year, month, day, hour, minute, seconds, offset
    private static func date(_ match: NSTextCheckingResult, in ns: NSString, calendar: Calendar) -> Date? {
        func part(_ group: Int) -> String? {
            let range = match.range(at: group)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        var zoned = calendar
        if let offset = part(7) { zoned.timeZone = timeZone(offset) ?? calendar.timeZone }
        return zoned.date(from: DateComponents(
            year: Int(part(1)!), month: Int(part(2)!), day: Int(part(3)!),
            hour: Int(part(4)!), minute: Int(part(5)!), second: Int(part(6) ?? "0")))
    }

    /// The note's file text: each line that has text and a time gets its marker at the end. The reverse of `parse`.
    public static func serialize(text: String, stamps: [Date?], calendar: Calendar = .current) -> String {
        let lines = text.components(separatedBy: "\n")
        let heading = headingIndex(in: lines)
        var out: [String] = []
        for (index, line) in lines.enumerated() {
            guard index < stamps.count, let stamp = stamps[index], !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  index != heading else {
                out.append(line)
                continue
            }
            out.append(format(stamp, calendar: calendar) + " " + line)
        }
        return out.joined(separator: "\n")
    }

    /// "Z", "+05:30" or "+0530" as a time zone
    private static func timeZone(_ offset: String) -> TimeZone? {
        if offset == "Z" { return TimeZone(secondsFromGMT: 0) }
        let digits = offset.dropFirst().filter(\.isNumber)
        guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else { return nil }
        return TimeZone(secondsFromGMT: (offset.hasPrefix("-") ? -1 : 1) * (hours * 3600 + minutes * 60))
    }

    /// `2026-11-05T11:34:07+05:30`: local time with its offset from UTC
    static func format(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let seconds = calendar.timeZone.secondsFromGMT(for: date)
        let offset = String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0) + offset
    }

    /// Brings `stamps` in step with a change to `text`: `replacement` takes the place of `range`. `text` is the text
    /// before the change. Lines pushed down by a new line keep their time, lines that go away lose theirs, and a
    /// line that gets its first text in this change is given `now`. Typing in a line never changes its time.
    public static func edit(stamps: inout [Date?], in text: String, replacing range: NSRange, with replacement: String, now: Date) {
        let old = text as NSString
        let lineCount = text.components(separatedBy: "\n").count
        while stamps.count < lineCount { stamps.append(nil) }
        if stamps.count > lineCount { stamps.removeLast(stamps.count - lineCount) }

        let range = NSRange(location: min(range.location, old.length), length: min(range.length, old.length - min(range.location, old.length)))
        let before = old.substring(to: range.location)
        let startLine = before.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
        let removed = old.substring(with: range).reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
        let inserted = replacement.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }

        // A new line typed at the very start of a line pushes that line down, and the line pushed down keeps its time
        let atLineStart = range.location == 0 || old.character(at: range.location - 1) == 0x0A
        let pushesDown = atLineStart && range.length == 0 && inserted > 0 && replacement.hasSuffix("\n")

        if removed > 0 {
            // Deleting whole lines, from the start of one: those lines go and the line after them keeps its own time.
            // Otherwise the line the deleted text began in keeps its time, and the lines joined onto it lose theirs.
            let wholeLines = atLineStart && replacement.isEmpty
            let first = wholeLines ? startLine : min(startLine + 1, stamps.count)
            let last = min(wholeLines ? startLine + removed - 1 : startLine + removed, stamps.count - 1)
            if first <= last { stamps.removeSubrange(first...last) }
        }
        if inserted > 0 {
            let at = pushesDown ? startLine : min(startLine + 1, stamps.count)
            stamps.insert(contentsOf: [Date?](repeating: nil, count: inserted), at: at)
        }

        let after = old.replacingCharacters(in: range, with: replacement).components(separatedBy: "\n")
        while stamps.count < after.count { stamps.append(nil) }
        if stamps.count > after.count { stamps.removeLast(stamps.count - after.count) }
        let heading = headingIndex(in: after)
        for index in startLine...min(startLine + inserted, after.count - 1) {
            let hasText = !after[index].trimmingCharacters(in: .whitespaces).isEmpty
            if hasText, stamps[index] == nil, index != heading { stamps[index] = now }
            if !hasText || index == heading { stamps[index] = nil }
        }
    }
}
