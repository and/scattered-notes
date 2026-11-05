import Foundation

/// A log note: a note whose first line starts with "Log -", kept like a log file, with the time each line was
/// written shown in a column at the right of the editor.
///
/// The times live in the note's file, as a marker at the end of each line: `⏱ 2026-11-05 11:34`, in the
/// writer's own time zone, like the `📅` and `✅` markers. The editor takes the markers off the text and shows them
/// in the column, so what is typed and what is read never includes them; saving puts them back. A line gets its
/// time when it first has text, and keeps it however it is edited afterwards. Lines written before the note became
/// a log, or in another app, have no time until they are edited.
public enum LogLines {
    /// The marker at the end of a line, with the optional variation selector some keyboards add after the symbol
    private static let markerRegex = try! NSRegularExpression(
        pattern: "[ \\t]*\u{23F1}\u{FE0F}?[ \\t]*(\\d{4})-(\\d{2})-(\\d{2}) (\\d{2}):(\\d{2})[ \\t]*$")

    private static let startRegex = try! NSRegularExpression(pattern: "^log\\s*[-\u{2013}\u{2014}]", options: .caseInsensitive)

    /// Whether the text is a log note: its first line that is not blank starts with "Log -" (any case, and a
    /// longer dash is fine)
    public static func isLog(_ content: String) -> Bool {
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            return startRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
        }
        return false
    }

    /// Whether a note is a log: "Log -" starts its title, or the first line of its text when it has no title of that kind
    public static func isLog(title: String, content: String) -> Bool {
        isLog(title) || isLog(content)
    }

    /// Whether the text holds a time marker, so `parse` has something to take off
    public static func hasStamps(_ content: String) -> Bool {
        content.unicodeScalars.contains { $0.value == 0x23F1 }
    }

    /// The text of a log note without its time markers, and the time of each line, `nil` for a line without one.
    /// There is one entry per line, always.
    public static func parse(_ content: String, calendar: Calendar = .current) -> (text: String, stamps: [Date?]) {
        var lines: [String] = []
        var stamps: [Date?] = []
        for line in content.components(separatedBy: "\n") {
            let ns = line as NSString
            if let match = markerRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let parts = (1...5).map { Int(ns.substring(with: match.range(at: $0))) ?? 0 }
                stamps.append(calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])))
                lines.append(ns.substring(to: match.range.location))
            } else {
                stamps.append(nil)
                lines.append(line)
            }
        }
        return (lines.joined(separator: "\n"), stamps)
    }

    /// The note's file text: each line that has text and a time gets its marker at the end. The reverse of `parse`.
    public static func serialize(text: String, stamps: [Date?], calendar: Calendar = .current) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        for (index, line) in lines.enumerated() {
            guard index < stamps.count, let stamp = stamps[index], !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                out.append(line)
                continue
            }
            var body = line
            while let last = body.last, last == " " || last == "\t" { body.removeLast() }
            out.append(body + " \u{23F1} " + format(stamp, calendar: calendar))
        }
        return out.joined(separator: "\n")
    }

    private static func format(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
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
        for index in startLine...min(startLine + inserted, after.count - 1) {
            let hasText = !after[index].trimmingCharacters(in: .whitespaces).isEmpty
            if hasText, stamps[index] == nil { stamps[index] = now }
            if !hasText { stamps[index] = nil }
        }
    }
}
