using System.Globalization;

namespace ScatteredNotes.Core.Text;

/// <summary>One line of a text and the line break that ended it ("" for the last line).</summary>
public readonly record struct Line(string Text, string Break);

/// <summary>
/// Line handling shared by every feature that works line by line. Unlike the Mac app, "\r\n" counts as a
/// single break, so Windows files keep their line endings when a line is edited.
/// </summary>
public static class LineText
{
    public static List<Line> Split(string text)
    {
        var lines = new List<Line>();
        var start = 0;
        for (var i = 0; i < text.Length; i++)
        {
            var ch = text[i];
            if (ch != '\n' && ch != '\r') continue;
            var length = ch == '\r' && i + 1 < text.Length && text[i + 1] == '\n' ? 2 : 1;
            lines.Add(new Line(text[start..i], text.Substring(i, length)));
            i += length - 1;
            start = i + 1;
        }
        lines.Add(new Line(text[start..], ""));
        return lines;
    }

    public static string Join(IEnumerable<Line> lines) => string.Concat(lines.Select(l => l.Text + l.Break));

    /// <summary>The line ending a text mostly uses, "\n" when it has none.</summary>
    public static string DominantBreak(string text)
    {
        var crlf = 0;
        var lf = 0;
        foreach (var line in Split(text))
        {
            if (line.Break == "\r\n") crlf++;
            else if (line.Break == "\n") lf++;
        }
        return crlf > lf ? "\r\n" : "\n";
    }

    /// <summary>Trims spaces and tabs, like Swift's <c>.whitespaces</c> set, but never line breaks.</summary>
    public static string TrimWhitespace(string text) => TrimEndWhitespace(TrimStartWhitespace(text));

    public static string TrimStartWhitespace(string text)
    {
        var start = 0;
        while (start < text.Length && IsWhitespace(text[start])) start++;
        return text[start..];
    }

    public static string TrimEndWhitespace(string text)
    {
        var end = text.Length;
        while (end > 0 && IsWhitespace(text[end - 1])) end--;
        return text[..end];
    }

    public static bool IsWhitespace(char ch) =>
        ch == '\t' || CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.SpaceSeparator;
}
