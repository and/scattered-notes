using System.Globalization;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Search;

/// <param name="Snippet">A short stretch of the body around the first match; null when only the title or tags matched.</param>
public sealed record SearchResult(Note Note, int Score, string? Snippet);

/// <summary>
/// Global note search. Every whitespace separated term must match somewhere in the note (title, body,
/// tags or destination), ignoring case and accents. A term starting with <c>#</c> matches tags only.
/// </summary>
public static class NoteSearch
{
    private const CompareOptions Options = CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace;
    private static readonly CompareInfo Compare = CultureInfo.InvariantCulture.CompareInfo;

    public static List<string> Terms(string query) =>
        query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Where(t => t != "#").ToList();

    public static List<SearchResult> Search(string query, IEnumerable<Note> notes, int limit = 50)
    {
        var terms = Terms(query);
        if (terms.Count == 0) return [];
        return notes
            .Select(n => Match(n, terms))
            .OfType<SearchResult>()
            .OrderByDescending(r => r.Score)
            .ThenByDescending(r => r.Note.UpdatedAt)
            .Take(limit)
            .ToList();
    }

    /// <summary>Index and length of the first match of <paramref name="term"/>, ignoring case and accents.</summary>
    public static (int Index, int Length)? Find(string text, string term, int startIndex = 0)
    {
        if (startIndex >= text.Length) return null;
        var index = Compare.IndexOf(text.AsSpan(startIndex), term.AsSpan(), Options, out var length);
        return index < 0 ? null : (index + startIndex, length);
    }

    private static SearchResult? Match(Note note, List<string> terms)
    {
        var score = 0;
        string? snippet = null;
        var title = note.DisplayTitle;
        var destination = note.DestinationDisplay;

        foreach (var term in terms)
        {
            if (term.StartsWith('#'))
            {
                var tag = term[1..];
                var hit = note.Tags.FirstOrDefault(t => Find(t, tag) is not null);
                if (hit is null) return null;
                score += Compare.Compare(hit, tag, Options) == 0 ? 12 : 8;
                continue;
            }

            var matched = false;
            if (Find(title, term) is { } titleHit)
            {
                matched = true;
                score += titleHit.Index == 0 ? 14 : 10;
            }
            if (note.Tags.Any(t => Find(t, term) is not null))
            {
                matched = true;
                score += 6;
            }
            if (Find(destination, term) is not null)
            {
                matched = true;
                score += 3;
            }
            if (Find(note.Content, term) is { } bodyHit)
            {
                matched = true;
                score += 1 + Math.Min(Occurrences(note.Content, term), 5);
                snippet ??= MakeSnippet(note.Content, bodyHit.Index, bodyHit.Length);
            }
            if (!matched) return null;
        }
        if (note.IsPinned) score += 1;
        return new SearchResult(note, score, snippet);
    }

    private static int Occurrences(string text, string term)
    {
        var count = 0;
        var from = 0;
        while (count < 6 && Find(text, term, from) is { } hit)
        {
            count++;
            from = hit.Index + Math.Max(hit.Length, 1);
        }
        return count;
    }

    /// <summary>About 90 characters of one line around the match, with ellipses where it was cut.</summary>
    public static string MakeSnippet(string text, int index, int length)
    {
        var lineStart = index == 0 ? 0 : text.LastIndexOfAny(['\n', '\r'], index - 1) + 1;
        var lineEndIndex = text.IndexOfAny(['\n', '\r'], index + length);
        var lineEnd = lineEndIndex < 0 ? text.Length : lineEndIndex;

        var start = SafeBoundary(text, Math.Max(index - 30, lineStart));
        var end = SafeBoundary(text, Math.Min(index + length + 60, lineEnd));

        var snippet = text[start..end].Trim(' ', '\t');
        if (start > lineStart) snippet = "…" + snippet;
        if (end < lineEnd) snippet += "…";
        return snippet;
    }

    /// <summary>Moves a cut point off the middle of a surrogate pair.</summary>
    private static int SafeBoundary(string text, int position) =>
        position > 0 && position < text.Length && char.IsLowSurrogate(text[position]) ? position - 1 : position;
}
