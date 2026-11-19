using System.Globalization;
using System.Text;

namespace ScatteredNotes.Core.Search;

/// <summary>What a place in the Go to palette is, for narrowing with a leading <c>#</c> or <c>@</c>.</summary>
public enum GoToKind
{
    Place,
    Person,
    Tag,
}

/// <summary>
/// How typing narrows the Go to palette (Ctrl+O), ported from the Mac's <c>GoToTargets.matching</c>. Case and
/// accents are ignored. A name that starts with the text comes before one with a word that does, and that before
/// one that only contains it; ties keep the given order. A leading <c>#</c> looks only at tags and <c>@</c> only
/// at people.
/// </summary>
public static class GoToMatching
{
    public static List<T> Matching<T>(string query, IEnumerable<T> targets, Func<T, string> title, Func<T, GoToKind> kind)
    {
        var text = query.Trim();
        var candidates = targets.ToList();
        if (text.StartsWith('#'))
        {
            text = text[1..];
            candidates = candidates.Where(t => kind(t) == GoToKind.Tag).ToList();
        }
        else if (text.StartsWith('@'))
        {
            text = text[1..];
            candidates = candidates.Where(t => kind(t) == GoToKind.Person).ToList();
        }
        var needle = Fold(text);
        if (needle.Length == 0) return candidates;

        int? Rank(T target)
        {
            var name = Fold(title(target));
            if (name.StartsWith(needle, StringComparison.Ordinal)) return 0;
            var words = name.Split(c => !char.IsLetterOrDigit(c));
            if (words.Any(w => w.StartsWith(needle, StringComparison.Ordinal))) return 1;
            return name.Contains(needle, StringComparison.Ordinal) ? 2 : null;
        }

        return candidates
            .Select((target, index) => (Rank: Rank(target), Index: index, Target: target))
            .Where(r => r.Rank is not null)
            .OrderBy(r => r.Rank)
            .ThenBy(r => r.Index)
            .Select(r => r.Target)
            .ToList();
    }

    /// <summary>Lower case without accents, so "Café" matches "cafe".</summary>
    private static string Fold(string text)
    {
        var decomposed = text.ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var folded = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) folded.Append(c);
        }
        return folded.ToString().Normalize(NormalizationForm.FormC);
    }

    private static string[] Split(this string text, Func<char, bool> isSeparator)
    {
        var words = new List<string>();
        var start = 0;
        for (var i = 0; i <= text.Length; i++)
        {
            if (i < text.Length && !isSeparator(text[i])) continue;
            if (i > start) words.Add(text[start..i]);
            start = i + 1;
        }
        return [.. words];
    }
}
