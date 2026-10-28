namespace ScatteredNotes.Core.Models;

/// <summary>
/// The inline marks a note can carry: <c>@person</c>, <c>#tag</c> and <c>+project</c>, with the same rules as the Mac app.
/// A mark counts only at the start of a word (after the start of the text, whitespace or an opening bracket or
/// quote) and when a letter follows the symbol, so "user@mail.com", "C#", "+91 98…" and "#1" are left alone.
/// A mark runs on through letters, digits, <c>-</c>, <c>_</c> and <c>.</c>, and loses a trailing <c>.</c>.
/// </summary>
public static class Mentions
{
    public enum Kind { Person, Tag, Project }

    public sealed record Mark(Kind Kind, string Name, int Start, int End);

    private static Kind? KindOf(char c) => c switch { '@' => Kind.Person, '#' => Kind.Tag, '+' => Kind.Project, _ => null };

    public static List<Mark> Marks(string text)
    {
        var marks = new List<Mark>();
        var i = 0;
        while (i < text.Length)
        {
            var startsWord = i == 0 || char.IsWhiteSpace(text[i - 1]) || "([{\"'".Contains(text[i - 1]);
            if (KindOf(text[i]) is { } kind && startsWord && i + 1 < text.Length && char.IsLetter(text[i + 1]))
            {
                var end = i + 1;
                while (end < text.Length && (char.IsLetterOrDigit(text[end]) || "-_.".Contains(text[end]))) end++;
                while (text[end - 1] == '.') end--;
                marks.Add(new Mark(kind, text[(i + 1)..end], i, end));
                i = end;
                continue;
            }
            i++;
        }
        return marks;
    }

    /// <summary>The distinct names of one kind, in the order they first appear; names differing only in case count once.</summary>
    public static List<string> Names(Kind kind, string text)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        return Marks(text).Where(m => m.Kind == kind).Select(m => m.Name).Where(seen.Add).ToList();
    }

    /// <summary>The tag an area becomes, as on the Mac: "Home Office" becomes "home-office".</summary>
    public static string TagNameForArea(string area)
    {
        var words = new List<string>();
        var word = new System.Text.StringBuilder();
        foreach (var c in area.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(c) || c is '-' or '_') word.Append(c);
            else if (word.Length > 0) { words.Add(word.ToString()); word.Clear(); }
        }
        if (word.Length > 0) words.Add(word.ToString());
        var name = string.Join("-", words);
        return name.Length > 0 && char.IsLetter(name[0]) ? name : "area-" + name;
    }
}
