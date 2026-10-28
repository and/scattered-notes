using System.Globalization;
using System.Text.RegularExpressions;
using ScatteredNotes.Core.Models;
using ScatteredNotes.Core.Text;

namespace ScatteredNotes.Core.Agenda;

/// <summary>A line pulled out of a note for the dashboard: a checklist item, a dated plan, or both.</summary>
public sealed record AgendaItem(
    Guid NoteId,
    int LineIndex,
    string Text,
    bool IsTodo,
    bool IsDone,
    DateOnly? Date,
    DateOnly WrittenOn)
{
    public string Id => $"{Note.FormatId(NoteId)}-{LineIndex}";
}

/// <summary>
/// Scans note content for checklist lines, plain lines that read as plans (see <see cref="IsPlannedAction"/>),
/// and lines that mention a day. Recognised (case-insensitive):
/// <c>2026-10-28</c> (optionally with <c>@</c>), today, tonight, tomorrow, weekday names and
/// "next friday", "next week", "day after tomorrow", "in 3 days", "in 2 weeks", "the day after" (one day
/// after the closest dated line above), and month plus day such as "oct 28", "28 october", "Oct 28th".
///
/// Relative words resolve against the day the line was first written. <c>anchors</c> maps a line's log
/// key (see <see cref="LogKey"/>) to that moment; lines without one fall back to the note's creation date.
/// </summary>
public static class AgendaExtractor
{
    public static List<AgendaItem> Items(
        Note note,
        IReadOnlyDictionary<string, DateTimeOffset>? anchors = null,
        TimeZoneInfo? timeZone = null)
    {
        timeZone ??= TimeZoneInfo.Local;
        var created = DayOf(note.CreatedAt, timeZone);
        var result = new List<AgendaItem>();
        DateOnly? previous = null;

        var lines = LineText.Split(note.Content);
        for (var index = 0; index < lines.Count; index++)
        {
            var trimmed = LineText.TrimWhitespace(lines[index].Text);
            if (trimmed.Length == 0 || trimmed.StartsWith('#')) continue;

            var checklist = Checklist.State(trimmed);
            var reference = anchors is not null && anchors.TryGetValue(LogKey(trimmed), out var anchor)
                ? DayOf(anchor, timeZone)
                : created;
            var date = ParseDate(trimmed, reference, previous);
            if (date is not null) previous = date;

            var text = DisplayText(trimmed);
            if (text.Length == 0) continue;
            var isTodo = checklist is not null || IsPlannedAction(text);
            if (!isTodo && date is null) continue;

            result.Add(new AgendaItem(note.Id, index, text, isTodo, checklist ?? false, date, reference));
        }
        return result;
    }

    public static DateOnly DayOf(DateTimeOffset instant, TimeZoneInfo timeZone) =>
        DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(instant, timeZone).DateTime);

    /// <summary>Identifies a line across edits that do not touch its words, e.g. ticking it or moving it.</summary>
    public static string LogKey(string line) => DisplayText(LineText.TrimWhitespace(line)).ToLowerInvariant();

    private static readonly string[] DisplayPrefixes =
        ["- [ ]", "* [ ]", "- [x]", "- [X]", "* [x]", "* [X]", "- ", "* ", "+ "];

    /// <summary>Verbs that start a line written as an instruction to oneself, e.g. "fix the login bug".</summary>
    private static readonly string[] ActionVerbs =
    [
        "add", "ask", "book", "build", "buy", "call", "cancel", "check", "clean", "confirm", "contact",
        "create", "debug", "delete", "deploy", "draft", "email", "figure", "finish", "fix", "follow",
        "get", "install", "investigate", "look", "make", "move", "pay", "pick", "ping", "prepare",
        "print", "publish", "read", "refactor", "remind", "renew", "reply", "research", "review",
        "schedule", "send", "share", "ship", "sign", "submit", "try", "update", "upload", "visit", "write",
    ];

    private static readonly Regex PlannedAction = new(
        @"^(?:to-?\s?do\b"
        + @"|(?:(?:i|we)\s+(?:am\s+|are\s+)?|(?:i|we)['’](?:m|re)\s+)?"
        + @"(?:needs?\s+to|ha(?:ve|s)\s+to|must|should|remember\s+to|don['’]?t\s+forget"
        + @"|plan(?:ning)?\s+to|going\s+to|gonna|want\s+to)\s"
        + @"|(?:i|we)(?:\s+will|['’]ll)\s"
        + "|(?:" + string.Join("|", ActionVerbs) + @")\s)",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// <summary>
    /// Whether a plain line reads like something the writer plans to do, so it counts as a to-do without
    /// checklist syntax: it starts with an action verb ("fix the login bug"), an intent ("need to renew
    /// passport", "I'll call Sam") or "todo". Questions and lines ending in ":" are left out.
    /// </summary>
    public static bool IsPlannedAction(string text) =>
        !text.EndsWith('?') && !text.EndsWith(':') && PlannedAction.IsMatch(text);

    private static readonly Regex IsoDateToken = new(@"\s*@?\b\d{4}-\d{2}-\d{2}\b");

    public static string DisplayText(string line)
    {
        var text = line;
        foreach (var prefix in DisplayPrefixes)
        {
            if (!text.StartsWith(prefix, StringComparison.Ordinal)) continue;
            text = text[prefix.Length..];
            break;
        }
        // An explicit @2026-10-28 marker is metadata; the dashboard shows the date separately
        var match = IsoDateToken.Match(text);
        if (match.Success && match.Value.Contains('@')) text = text.Remove(match.Index, match.Length);
        return LineText.TrimWhitespace(text);
    }

    private static readonly string[] Months =
        ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

    private const string MonthPattern =
        "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)";

    private static readonly string[] Weekdays =
        ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

    private const RegexOptions Options = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
    private static readonly Regex Iso = new(@"\b(\d{4})-(\d{2})-(\d{2})\b");
    private static readonly Regex MonthDay = new(@"\b" + MonthPattern + @"\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b", Options);
    private static readonly Regex DayMonth = new(@"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?" + MonthPattern + @"\b", Options);
    private static readonly Regex Relative = new(@"\b(today|tonight|tomorrow)\b", Options);
    private static readonly Regex Weekday = new(@"\b(next\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b", Options);
    private static readonly Regex DayAfterTomorrow = new(@"\bday\s+after\s+tomorrow\b", Options);
    private static readonly Regex DayAfter = new(@"\bday\s+after\b", Options);
    private static readonly Regex InInterval = new(@"\bin\s+(\d{1,3})\s+(day|week)s?\b", Options);
    private static readonly Regex NextWeek = new(@"\bnext\s+week\b", Options);

    public static DateOnly? ParseDate(string line, DateOnly reference, DateOnly? previous = null)
    {
        static int? Number(Group group) =>
            int.TryParse(group.Value, NumberStyles.None, CultureInfo.InvariantCulture, out var n) ? n : null;

        if (Iso.Match(line) is { Success: true } iso &&
            Number(iso.Groups[1]) is { } year && Number(iso.Groups[2]) is { } month && Number(iso.Groups[3]) is { } day &&
            year >= 1 && month is >= 1 and <= 12 && day >= 1 && day <= DateTime.DaysInMonth(year, month))
        {
            return new DateOnly(year, month, day);
        }

        if (MonthDay.Match(line) is { Success: true } md &&
            ResolveMonthDay(md.Groups[1].Value, Number(md.Groups[2]), reference) is { } monthDay)
        {
            return monthDay;
        }

        if (DayMonth.Match(line) is { Success: true } dm &&
            ResolveMonthDay(dm.Groups[2].Value, Number(dm.Groups[1]), reference) is { } dayMonth)
        {
            return dayMonth;
        }

        if (DayAfterTomorrow.IsMatch(line)) return reference.AddDays(2);

        // "the day after" continues from the dated line above, e.g. "buy milk today" then "bake the day after"
        if (DayAfter.IsMatch(line)) return (previous ?? reference).AddDays(1);

        if (InInterval.Match(line) is { Success: true } interval && Number(interval.Groups[1]) is { } count)
        {
            var isWeek = interval.Groups[2].Value.Equals("week", StringComparison.OrdinalIgnoreCase);
            return reference.AddDays(isWeek ? count * 7 : count);
        }

        if (Relative.Match(line) is { Success: true } relative)
        {
            var isTomorrow = relative.Groups[1].Value.Equals("tomorrow", StringComparison.OrdinalIgnoreCase);
            return reference.AddDays(isTomorrow ? 1 : 0);
        }

        if (Weekday.Match(line) is { Success: true } weekday)
        {
            var target = Array.IndexOf(Weekdays, weekday.Groups[2].Value.ToLowerInvariant());
            var offset = (target - (int)reference.DayOfWeek + 7) % 7;
            if (weekday.Groups[1].Success) offset += 7;
            return reference.AddDays(offset);
        }

        if (NextWeek.IsMatch(line)) return reference.AddDays(7);

        return null;
    }

    private static DateOnly? ResolveMonthDay(string month, int? day, DateOnly reference)
    {
        var monthIndex = Array.IndexOf(Months, month.ToLowerInvariant()[..3]);
        if (day is not { } d || d < 1 || monthIndex < 0) return null;
        if (d > DateTime.DaysInMonth(reference.Year, monthIndex + 1)) return null;
        var date = new DateOnly(reference.Year, monthIndex + 1, d);
        // A date more than six months before the line was written most likely means next year
        return date < reference.AddMonths(-6) ? date.AddYears(1) : date;
    }
}
