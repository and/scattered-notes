using System.Globalization;
using System.Text.RegularExpressions;

namespace ScatteredNotes.Core.Models;

/// <summary>
/// Log notes: notes kept like a log file, where each line starts with the time it was written. Ported from the
/// Mac app's <c>LogLines</c> (see docs/log-notes.md), with two additions for notes written by other tools, such as
/// an Obsidian vault a script appends to:
/// <list type="bullet">
/// <item>A title ending in the word "Log" ("Orders Log", "Workout Log") also makes a log, besides one starting
/// with "Log -". "Backlog" and "Changelog" don't count.</item>
/// <item>A title that is only a date ("2026-11-19", a daily note) also makes a log.</item>
/// <item>A new line copies the time style of the note's last timed line, e.g. <c>- 2026-11-19 11:46 — </c>, so
/// lines typed in the app look like the tool's. Without one it is the app's own <c>2026-11-19T11:46:07+05:30 </c>.</item>
/// </list>
/// </summary>
public static partial class LogNotes
{
    /// <summary>"Log -" (any case, any dash) at the start, or the word "Log" at the end.</summary>
    [GeneratedRegex(@"^log\s*[-–—]|(^|\s)log$", RegexOptions.IgnoreCase)]
    private static partial Regex LogName();

    /// <summary>
    /// A time at the start of a line: an optional list bullet, a date and a time, an optional time zone, then a
    /// separator (spaces, or a dash between spaces). Group names say what each part is, to rebuild the style.
    /// </summary>
    [GeneratedRegex(@"^(?<lead>[ \t]*(?:[-*+][ \t]+)?)(?<date>\d{4}-\d{2}-\d{2})(?<sep>[T ])(?<time>\d{2}:\d{2})(?<sec>:\d{2})?(?<zone>Z|[+-]\d{2}:?\d{2})?(?<gap>[ \t]*[-–—][ \t]+|[ \t]+|$)")]
    private static partial Regex LeadingStamp();

    /// <summary>A title that is only a date, as in daily notes: 2026-11-19, 19-11-2026, 2026/11/19, 2026.11.19, optionally with a time.</summary>
    [GeneratedRegex(@"^\s*#*\s*(\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{4})([T ]\d{1,2}[:.]\d{2}([:.]\d{2})?)?\s*$")]
    private static partial Regex DateOnly();

    /// <summary>Whether a note is a log: its title or the first line of its text names it one, or its title is only a date.</summary>
    public static bool IsLog(string title, string content) =>
        IsLogName(title) || IsDateOnly(title) || IsLogName(FirstLine(content));

    /// <summary>A title made of just a date (and maybe a time), like a daily note's.</summary>
    public static bool IsDateOnly(string? title) => DateOnly().IsMatch(title ?? "");

    public static bool IsLog(Note note) => IsLog(note.Title, note.Content);

    /// <summary>A title or heading line that makes a log; a Markdown heading's "#" is ignored.</summary>
    public static bool IsLogName(string? text)
    {
        var name = (text ?? "").Trim().TrimStart('#').Trim();
        return name.Length > 0 && LogName().IsMatch(name);
    }

    private static string FirstLine(string content)
    {
        foreach (var line in content.Split('\n'))
        {
            if (line.Trim().Length > 0) return line.Trim();
        }
        return "";
    }

    /// <summary>The line without the time at its start, keeping its list bullet. Unchanged when it has none.</summary>
    public static string WithoutStamp(string line)
    {
        var match = LeadingStamp().Match(line);
        return match.Success ? match.Groups["lead"].Value + line[match.Length..] : line;
    }

    /// <summary>
    /// What a new line in a log note starts with, written at <paramref name="now"/>: the style of the last timed line
    /// before <paramref name="beforeOffset"/>, or the app's own style when there is none.
    /// </summary>
    public static string NewLinePrefix(string content, int beforeOffset, DateTimeOffset now)
    {
        var lines = content[..Math.Clamp(beforeOffset, 0, content.Length)].Split('\n');
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            var match = LeadingStamp().Match(lines[i].TrimEnd('\r'));
            if (match.Success) return Format(now, match);
        }
        return AppStamp(now) + " ";
    }

    /// <summary>The app's own time: <c>2026-11-05T11:34:07+05:30</c>, local time with its offset from UTC.</summary>
    public static string AppStamp(DateTimeOffset time) =>
        time.ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture) + Offset(time.Offset, colon: true);

    private static string Format(DateTimeOffset now, Match style)
    {
        var text = style.Groups["lead"].Value
            + now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
            + style.Groups["sep"].Value
            + now.ToString("HH:mm", CultureInfo.InvariantCulture);
        if (style.Groups["sec"].Success) text += now.ToString(":ss", CultureInfo.InvariantCulture);
        if (style.Groups["zone"].Success)
            text += style.Groups["zone"].Value == "Z" && now.Offset == TimeSpan.Zero ? "Z" : Offset(now.Offset, style.Groups["zone"].Value.Contains(':'));
        var gap = style.Groups["gap"].Value;
        return text + (gap.Length == 0 ? " " : gap);
    }

    private static string Offset(TimeSpan offset, bool colon)
    {
        var sign = offset < TimeSpan.Zero ? "-" : "+";
        var abs = offset.Duration();
        return $"{sign}{abs.Hours:00}{(colon ? ":" : "")}{abs.Minutes:00}";
    }
}
