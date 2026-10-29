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
    DateOnly WrittenOn,
    DateOnly? DoneOn)
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
/// Relative words resolve against the day the line was written. The app writes that day into the line when
/// the note is saved (see <see cref="ResolvingDates"/>), as <c>📅 2026-10-28</c> for the day a line refers to
/// and <c>✅ 2026-10-28</c> for the day it was ticked, the markers the Obsidian Tasks plugin uses. A line
/// without a <c>📅</c> marker, e.g. one written in another editor, resolves against the note's last update.
/// </summary>
public static class AgendaExtractor
{
    public static List<AgendaItem> Items(Note note, TimeZoneInfo? timeZone = null)
    {
        timeZone ??= TimeZoneInfo.Local;
        var reference = DayOf(note.UpdatedAt, timeZone);
        var result = new List<AgendaItem>();
        DateOnly? previous = null;

        var lines = LineText.Split(note.Content);
        for (var index = 0; index < lines.Count; index++)
        {
            var trimmed = LineText.TrimWhitespace(lines[index].Text);
            if (trimmed.Length == 0 || trimmed.StartsWith('#')) continue;

            var checklist = Checklist.State(trimmed);
            var marks = Markers(trimmed);
            var date = marks.Due ?? ParseDate(WithoutMarkers(trimmed), reference, previous);
            if (date is not null) previous = date;

            var text = DisplayText(trimmed);
            if (text.Length == 0) continue;
            var isTodo = checklist is not null || IsPlannedAction(text);
            if (!isTodo && date is null) continue;

            result.Add(new AgendaItem(note.Id, index, text, isTodo, checklist ?? false, date, reference,
                checklist == true ? marks.Done : null));
        }
        return result;
    }

    public static DateOnly DayOf(DateTimeOffset instant, TimeZoneInfo timeZone) =>
        DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(instant, timeZone).DateTime);

    private static readonly Regex DueMarker = new(@"\s*📅\s*(\d{4})-(\d{2})-(\d{2})");
    private static readonly Regex DoneMarker = new(@"\s*✅\s*(\d{4})-(\d{2})-(\d{2})");

    private static DateOnly? MarkedDay(Regex regex, string line)
    {
        if (regex.Match(line) is not { Success: true } m) return null;
        int Part(int group) => int.Parse(m.Groups[group].Value, CultureInfo.InvariantCulture);
        int year = Part(1), month = Part(2), day = Part(3);
        return year >= 1 && month is >= 1 and <= 12 && day >= 1 && day <= DateTime.DaysInMonth(year, month)
            ? new DateOnly(year, month, day)
            : null;
    }

    /// <summary>The days written into a line by <c>📅</c> and <c>✅</c>.</summary>
    public static (DateOnly? Due, DateOnly? Done) Markers(string line) => (MarkedDay(DueMarker, line), MarkedDay(DoneMarker, line));

    /// <summary>Whether two texts are the same apart from the markers the app writes into lines.</summary>
    public static bool SameIgnoringMarkers(string a, string b) => a == b || WithoutMarkers(a) == WithoutMarkers(b);

    /// <summary>
    /// Where a position in <paramref name="old"/> lands in <paramref name="updated"/> when the latter is the
    /// former with date markers written into its lines: the same place in the words, so a caret typing at the
    /// end of a line stays before the marker written there, and one right after a marker stays after it.
    /// </summary>
    public static int MappedOffset(int offset, string old, string updated)
    {
        var oldMarkers = DueMarker.Matches(old).Concat(DoneMarker.Matches(old)).ToList();
        var newMarkers = DueMarker.Matches(updated).Concat(DoneMarker.Matches(updated)).ToList();
        static bool InMarker(int index, List<Match> markers) => markers.Any(m => index >= m.Index && index < m.Index + m.Length);
        var wordsBefore = Enumerable.Range(0, Math.Min(offset, old.Length)).Count(i => !InMarker(i, oldMarkers));
        var afterMarker = oldMarkers.Any(m => m.Index + m.Length == offset);
        var words = 0;
        int? result = null;
        for (var index = 0; index <= updated.Length; index++)
        {
            if (words == wordsBefore)
            {
                result = index;
                if (!afterMarker) break;
            }
            if (index < updated.Length && !InMarker(index, newMarkers)) words++;
            if (words > wordsBefore) break;
        }
        return result ?? Math.Min(offset, updated.Length);
    }

    /// <summary>The line without its <c>📅</c> and <c>✅</c> markers.</summary>
    public static string WithoutMarkers(string line) => DoneMarker.Replace(DueMarker.Replace(line, ""), "");

    private static string Marker(string symbol, DateOnly day) =>
        $" {symbol} {day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)}";

    /// <summary>
    /// The note text with the days written into it. A line whose date comes from a relative word, such as
    /// "call the bank tomorrow", gets <c>📅</c> and the day it resolves to; a ticked checklist line gets <c>✅</c>
    /// and the day it was ticked; an unticked one loses its <c>✅</c>. Lines are matched with
    /// <paramref name="previous"/>, the text as last saved, by their words, so a line keeps its days when the
    /// editor's copy lacks the markers or the line is moved. A line already in <paramref name="previous"/>
    /// without markers counts as written at <paramref name="previousUpdatedAt"/>; any other line was written
    /// <paramref name="now"/>. Only lines that need a marker change.
    /// </summary>
    public static string ResolvingDates(
        string content, string? previous, DateTimeOffset? previousUpdatedAt, DateTimeOffset now, TimeZoneInfo? timeZone = null)
    {
        timeZone ??= TimeZoneInfo.Local;
        var today = DayOf(now, timeZone);
        var before = previousUpdatedAt is { } at ? DayOf(at, timeZone) : today;
        var known = new Dictionary<string, Queue<(DateOnly? Due, DateOnly? Done)>>();
        foreach (var raw in LineText.Split(previous ?? ""))
        {
            var line = LineText.TrimWhitespace(raw.Text);
            if (line.Length == 0 || line.StartsWith('#')) continue;
            var key = DisplayText(line);
            if (!known.TryGetValue(key, out var queue)) known[key] = queue = new();
            queue.Enqueue(Markers(line));
        }

        var lines = LineText.Split(content);
        DateOnly? previousDate = null;
        for (var index = 0; index < lines.Count; index++)
        {
            var line = LineText.TrimWhitespace(lines[index].Text);
            if (line.Length == 0 || line.StartsWith('#')) continue;
            var key = DisplayText(line);
            if (key.Length == 0) continue;
            (DateOnly? Due, DateOnly? Done)? old = known.TryGetValue(key, out var queue) && queue.Count > 0 ? queue.Dequeue() : null;
            var marks = Markers(line);

            var due = marks.Due ?? old?.Due;
            DateOnly? found = null;
            if (due is null)
            {
                found = ParseDate(WithoutMarkers(line), old is null ? today : before, previousDate, out var isRelative);
                if (found is not null && isRelative) due = found;
            }
            if ((due ?? found) is { } day) previousDate = day;

            var done = marks.Done;
            switch (Checklist.State(line))
            {
                case true: done = marks.Done ?? old?.Done ?? (old is null ? today : before); break;
                case false: done = null; break;
            }

            if (due == marks.Due && done == marks.Done) continue;
            var text = LineText.TrimEndWhitespace(WithoutMarkers(lines[index].Text));
            if (due is { } d) text += Marker("📅", d);
            if (done is { } c) text += Marker("✅", c);
            lines[index] = lines[index] with { Text = text };
        }
        return LineText.Join(lines);
    }

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
        var text = WithoutMarkers(line);
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

    public static DateOnly? ParseDate(string line, DateOnly reference, DateOnly? previous = null) =>
        ParseDate(line, reference, previous, out _);

    /// <summary>
    /// The day a line refers to. <paramref name="isRelative"/> says whether it depends on when the line was
    /// written ("tomorrow", "friday") rather than being fixed ("2026-10-28", "oct 28").
    /// </summary>
    public static DateOnly? ParseDate(string line, DateOnly reference, DateOnly? previous, out bool isRelative)
    {
        isRelative = false;
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

        if (DayAfterTomorrow.IsMatch(line)) return AsRelative(reference.AddDays(2), out isRelative);

        // "the day after" continues from the dated line above, e.g. "buy milk today" then "bake the day after"
        if (DayAfter.IsMatch(line)) return AsRelative((previous ?? reference).AddDays(1), out isRelative);

        if (InInterval.Match(line) is { Success: true } interval && Number(interval.Groups[1]) is { } count)
        {
            var isWeek = interval.Groups[2].Value.Equals("week", StringComparison.OrdinalIgnoreCase);
            return AsRelative(reference.AddDays(isWeek ? count * 7 : count), out isRelative);
        }

        if (Relative.Match(line) is { Success: true } relative)
        {
            var isTomorrow = relative.Groups[1].Value.Equals("tomorrow", StringComparison.OrdinalIgnoreCase);
            return AsRelative(reference.AddDays(isTomorrow ? 1 : 0), out isRelative);
        }

        if (Weekday.Match(line) is { Success: true } weekday)
        {
            var target = Array.IndexOf(Weekdays, weekday.Groups[2].Value.ToLowerInvariant());
            var offset = (target - (int)reference.DayOfWeek + 7) % 7;
            if (weekday.Groups[1].Success) offset += 7;
            return AsRelative(reference.AddDays(offset), out isRelative);
        }

        if (NextWeek.IsMatch(line)) return AsRelative(reference.AddDays(7), out isRelative);

        return null;
    }

    private static DateOnly AsRelative(DateOnly day, out bool isRelative)
    {
        isRelative = true;
        return day;
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
