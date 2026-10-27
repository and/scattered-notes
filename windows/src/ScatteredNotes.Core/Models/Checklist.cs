using ScatteredNotes.Core.Text;

namespace ScatteredNotes.Core.Models;

public static class Checklist
{
    private static readonly string[] Open = ["- [ ]", "* [ ]"];
    private static readonly string[] Done = ["- [x]", "- [X]", "* [x]", "* [X]"];

    /// <summary>null when the (trimmed) line is not a checklist item, otherwise whether it is checked.</summary>
    public static bool? State(string trimmedLine)
    {
        if (Open.Any(p => trimmedLine.StartsWith(p, StringComparison.Ordinal))) return false;
        if (Done.Any(p => trimmedLine.StartsWith(p, StringComparison.Ordinal))) return true;
        return null;
    }

    public static (int Completed, int Total)? Stats(string content)
    {
        var total = 0;
        var completed = 0;
        foreach (var line in LineText.Split(content))
        {
            var state = State(LineText.TrimWhitespace(line.Text));
            if (state is null) continue;
            total++;
            if (state.Value) completed++;
        }
        return total > 0 ? (completed, total) : null;
    }

    /// <summary>
    /// Flips the checkbox on line <paramref name="lineIndex"/>. A plain line becomes a checked item.
    /// Other lines, and every line ending, are left untouched.
    /// </summary>
    public static string ToggleLine(int lineIndex, string content)
    {
        var lines = LineText.Split(content);
        if (lineIndex < 0 || lineIndex >= lines.Count) return content;
        var line = lines[lineIndex].Text;

        string? toggled = null;
        foreach (var (from, to) in Toggles)
        {
            if (!line.Contains(from, StringComparison.Ordinal)) continue;
            toggled = line.Replace(from, to, StringComparison.Ordinal);
            break;
        }
        toggled ??= CompletingPlainLine(line);
        if (toggled is null) return content;

        lines[lineIndex] = lines[lineIndex] with { Text = toggled };
        return LineText.Join(lines);
    }

    private static readonly (string From, string To)[] Toggles =
    [
        ("- [ ]", "- [x]"), ("- [x]", "- [ ]"), ("- [X]", "- [ ]"),
        ("* [ ]", "* [x]"), ("* [x]", "* [ ]"), ("* [X]", "* [ ]"),
    ];

    /// <summary>
    /// "call the bank tomorrow" becomes "- [x] call the bank tomorrow", keeping indentation and replacing a
    /// bullet. null for blank lines and headings.
    /// </summary>
    private static string? CompletingPlainLine(string line)
    {
        var indentLength = 0;
        while (indentLength < line.Length && (line[indentLength] == ' ' || line[indentLength] == '\t')) indentLength++;
        var indent = line[..indentLength];
        var body = line[indentLength..];
        if (LineText.TrimWhitespace(body).Length == 0 || body.StartsWith('#')) return null;
        foreach (var bullet in new[] { "- ", "* ", "+ " })
        {
            if (!body.StartsWith(bullet, StringComparison.Ordinal)) continue;
            body = body[bullet.Length..];
            break;
        }
        return $"{indent}- [x] {body}";
    }
}
