namespace ScatteredNotes.Core.Models;

/// <summary>Where a captured note goes: the Inbox or a project.</summary>
public sealed record Destination(CategoryType Type, string? Name = null)
{
    public static readonly Destination Inbox = new(CategoryType.Inbox);

    public string DisplayName => Name ?? "Inbox";
}

/// <summary>The Quick Capture rules, the same as the Mac app's.</summary>
public static class QuickCapture
{
    /// <summary>
    /// Picks a project from the text, as the Mac app does: <c>[[Name]]</c>, <c>+Name</c> or <c>p:Name</c>. A name
    /// matching an existing project (ignoring case and spaces) gets its spelling; any other is a new project.
    /// <c>#tag</c> and <c>@person</c> never move a note. null when the text names no project.
    /// </summary>
    public static Destination? DetectDestination(string text, IReadOnlyList<ProjectArea> projects)
    {
        var wikiStart = text.IndexOf("[[", StringComparison.Ordinal);
        var wikiEnd = wikiStart < 0 ? -1 : text.IndexOf("]]", wikiStart + 2, StringComparison.Ordinal);
        string? name = null;
        if (wikiEnd > 0 && text[(wikiStart + 2)..wikiEnd].Trim() is { Length: > 0 } inside)
            name = inside;
        else if (Mentions.Marks(text).FirstOrDefault(m => m.Kind == Mentions.Kind.Project) is { } mark)
            name = mark.Name;
        else if (text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault(w => w.StartsWith("p:", StringComparison.Ordinal) && w.Length > 2) is { } word)
            name = TrimNonAlphanumerics(word[2..]);
        if (string.IsNullOrEmpty(name)) return null;

        return Match(projects, name, true) is { } project
            ? new Destination(CategoryType.Project, project.Name)
            : new Destination(CategoryType.Project, char.ToUpperInvariant(name[0]) + name[1..]);
    }

    private static ProjectArea? Match(IReadOnlyList<ProjectArea> folders, string name, bool ignoreSpaces) =>
        folders.FirstOrDefault(f =>
            f.Name.Equals(name, StringComparison.OrdinalIgnoreCase) ||
            (ignoreSpaces && f.Name.Replace(" ", "").Equals(name, StringComparison.OrdinalIgnoreCase)));

    /// <summary>The <c>#tags</c> in the text.</summary>
    public static List<string> Tags(string text) => Mentions.Names(Mentions.Kind.Tag, text);

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
