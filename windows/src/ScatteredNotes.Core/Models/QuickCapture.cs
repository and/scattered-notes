namespace ScatteredNotes.Core.Models;

/// <summary>Where a captured note goes: the Inbox, a project or an area.</summary>
public sealed record Destination(CategoryType Type, string? Name = null)
{
    public static readonly Destination Inbox = new(CategoryType.Inbox);

    public string DisplayName => Name ?? "Inbox";
}

/// <summary>The Quick Capture rules, the same as the Mac app's.</summary>
public static class QuickCapture
{
    /// <summary>
    /// Picks a destination from inline tags in the text: <c>[[Name]]</c>, <c>+Name</c>, <c>@Name</c>,
    /// <c>p:Name</c>, or <c>#Name</c> matching an existing project or area. An explicit prefix naming no
    /// existing folder means a new project. null when the text names none.
    /// </summary>
    public static Destination? DetectDestination(string text, IReadOnlyList<ProjectArea> projects, IReadOnlyList<ProjectArea> areas)
    {
        var wikiStart = text.IndexOf("[[", StringComparison.Ordinal);
        var wikiEnd = wikiStart < 0 ? -1 : text.IndexOf("]]", wikiStart + 2, StringComparison.Ordinal);
        if (wikiEnd > 0)
        {
            var inside = text[(wikiStart + 2)..wikiEnd].Trim();
            if (inside.Length > 0)
            {
                return Match(projects, inside, false) is { } p ? new Destination(CategoryType.Project, p.Name)
                    : Match(areas, inside, false) is { } a ? new Destination(CategoryType.Area, a.Name)
                    : new Destination(CategoryType.Project, inside);
            }
        }

        foreach (var word in text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
        {
            var (candidate, explicitPrefix) = word switch
            {
                _ when word.StartsWith('+') && word.Length > 1 => (word[1..], true),
                _ when word.StartsWith('@') && word.Length > 1 => (word[1..], true),
                _ when word.StartsWith("p:", StringComparison.Ordinal) && word.Length > 2 => (word[2..], true),
                _ when word.StartsWith('#') && word.Length > 1 => (word[1..], false),
                _ => ("", false),
            };
            var cleaned = TrimNonAlphanumerics(candidate);
            if (cleaned.Length == 0) continue;

            if (Match(projects, cleaned, true) is { } project) return new Destination(CategoryType.Project, project.Name);
            if (Match(areas, cleaned, true) is { } area) return new Destination(CategoryType.Area, area.Name);
            if (explicitPrefix && cleaned.Length >= 2) return new Destination(CategoryType.Project, char.ToUpperInvariant(cleaned[0]) + cleaned[1..]);
        }
        return null;
    }

    private static ProjectArea? Match(IReadOnlyList<ProjectArea> folders, string name, bool ignoreSpaces) =>
        folders.FirstOrDefault(f =>
            f.Name.Equals(name, StringComparison.OrdinalIgnoreCase) ||
            (ignoreSpaces && f.Name.Replace(" ", "").Equals(name, StringComparison.OrdinalIgnoreCase)));

    /// <summary>Hashtags in the text, without the destination's own name.</summary>
    public static List<string> Tags(string text, string? destinationName) =>
        text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .Where(w => w.StartsWith('#') && w.Length > 1)
            .Select(w => TrimNonAlphanumerics(w[1..]))
            .Where(t => t.Length > 0 && !t.Equals(destinationName, StringComparison.OrdinalIgnoreCase))
            .ToList();

    /// <summary>The note body: the trimmed text without the inline destination tag.</summary>
    public static string Content(string text, Destination destination)
    {
        var trimmed = text.Trim();
        var cleaned = ProjectTags.Remove(trimmed, destination.Name);
        return cleaned.Length == 0 ? destination.Name ?? trimmed : cleaned;
    }

    public static string TrimNonAlphanumerics(string text)
    {
        var start = 0;
        var end = text.Length;
        while (start < end && !char.IsLetterOrDigit(text[start])) start++;
        while (end > start && !char.IsLetterOrDigit(text[end - 1])) end--;
        return text[start..end];
    }
}
