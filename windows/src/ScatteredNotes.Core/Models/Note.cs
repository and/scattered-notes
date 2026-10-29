using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Text;

namespace ScatteredNotes.Core.Models;

/// <summary>
/// A note: a Markdown file with YAML frontmatter. Immutable; edits make a copy with <c>with</c>, so the
/// store can tell whether anything changed.
/// </summary>
public sealed record Note
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Title { get; init; } = "";
    public string Content { get; init; } = "";
    public CategoryType CategoryType { get; init; } = CategoryType.Inbox;
    public string? TargetName { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; init; } = DateTimeOffset.UtcNow;
    public IReadOnlyList<string> Tags { get; init; } = [];
    public string? FilePath { get; init; }
    public bool IsPinned { get; init; }

    /// <summary>Frontmatter lines the app does not use, e.g. Obsidian properties, kept as written and saved back unchanged.</summary>
    public string ExtraFrontmatter { get; init; } = "";

    /// <summary>The ID as the Mac app writes it: an uppercase UUID.</summary>
    public string IdString => FormatId(Id);

    public static string FormatId(Guid id) => id.ToString("D").ToUpperInvariant();

    public string DisplayTitle
    {
        get
        {
            var title = Title.Trim();
            if (title.Length > 0) return title;
            // Fall back to the first non-blank line of the content
            foreach (var line in LineText.Split(Content))
            {
                // The dates the app writes into lines are for the dashboard, not for a title
                var trimmed = LineText.TrimWhitespace(AgendaExtractor.WithoutMarkers(line.Text));
                if (trimmed.StartsWith('#')) trimmed = trimmed.Trim('#', ' ');
                if (trimmed.Length > 0) return trimmed;
            }
            return "Untitled Note";
        }
    }

    public string PreviewExcerpt
    {
        get
        {
            var title = DisplayTitle;
            var preview = new List<string>();
            foreach (var line in LineText.Split(Content))
            {
                var trimmed = LineText.TrimWhitespace(AgendaExtractor.WithoutMarkers(line.Text));
                // Skip a heading that repeats the title
                if (trimmed.StartsWith('#') && trimmed.Contains(title, StringComparison.Ordinal)) continue;
                if (trimmed.Length == 0) continue;
                preview.Add(trimmed);
                if (preview.Count >= 2) break;
            }
            return string.Join(" ", preview);
        }
    }

    /// <summary>People mentioned as <c>@name</c>, in the order they first appear.</summary>
    public IReadOnlyList<string> People => Mentions.Names(Mentions.Kind.Person, Content);

    public string DestinationDisplay => CategoryType switch
    {
        CategoryType.Project => TargetName ?? "Project",
        CategoryType.Area => TargetName ?? "Area",
        _ => "Inbox",
    };

    public (int Completed, int Total)? ChecklistStats => Checklist.Stats(Content);

    /// <summary>Whether saving <paramref name="other"/> over this note would change the file.</summary>
    public bool HasSameContent(Note other) =>
        Title == other.Title &&
        Content == other.Content &&
        CategoryType == other.CategoryType &&
        TargetName == other.TargetName &&
        IsPinned == other.IsPinned &&
        Tags.SequenceEqual(other.Tags);
}
