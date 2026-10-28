using System.Text.RegularExpressions;
using ScatteredNotes.Core.Text;

namespace ScatteredNotes.Core.Models;

public static class ProjectTags
{
    /// <summary>
    /// Removes inline project marks (<c>+project</c>, <c>p:project</c>, <c>[[project]]</c>)
    /// for <paramref name="targetName"/> from captured text, so the body stays clean.
    /// </summary>
    public static string Remove(string text, string? targetName)
    {
        var target = targetName?.Trim();
        if (string.IsNullOrEmpty(target)) return text;

        var noSpace = target.Replace(" ", "");
        var noPunct = noSpace.Replace("-", "").Replace("_", "");
        var targetPart = string.Join("|", new[] { target, noSpace, noPunct }.Distinct().Select(Regex.Escape));

        const RegexOptions options = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
        var p1 = new Regex($@"^(?:\+|p:)(?:{targetPart})(?::\s*|\s+)", options);
        var p2 = new Regex($@"\s+(?:\+|p:)(?:{targetPart})([.,;:])(?=\s|$)", options);
        var p3 = new Regex($@"\s+(?:\+|p:)(?:{targetPart})(?=[.,;:]?(\s|$))", options);
        var p4 = new Regex($@"^(?:\+|p:)(?:{targetPart})[.,;:]?$", options);
        var wiki = new Regex($@"\[\[(?:{targetPart})\]\]", options);
        var spaces = new Regex("  +");

        var lines = LineText.Split(text).Select(l => l.Text).ToList();
        for (var i = 0; i < lines.Count; i++)
        {
            var line = lines[i];
            line = wiki.Replace(line, "");
            line = p4.Replace(line, "");
            line = p1.Replace(line, "");
            line = p2.Replace(line, "$1");
            line = p3.Replace(line, "");
            line = spaces.Replace(line, " ");
            lines[i] = LineText.TrimWhitespace(line);
        }

        while (lines.Count > 1 && lines[0].Length == 0) lines.RemoveAt(0);
        while (lines.Count > 1 && lines[^1].Length == 0) lines.RemoveAt(lines.Count - 1);
        return string.Join("\n", lines);
    }
}
