using System.Globalization;
using System.Text;

namespace ScatteredNotes.Core.Models;

/// <summary>
/// Reads and writes the note file format shared with the Mac app. See docs/windows-plan.md, "File format
/// contract". The body is always kept exactly as it is.
/// </summary>
public static class NoteFormat
{
    private const string WriteDateFormat = "yyyy-MM-dd'T'HH:mm:ss.fff'Z'";

    public static string FormatDate(DateTimeOffset date) =>
        date.UtcDateTime.ToString(WriteDateFormat, CultureInfo.InvariantCulture);

    /// <summary>ISO 8601 with or without fractional seconds, any offset.</summary>
    public static DateTimeOffset? ParseDate(string value)
    {
        string[] formats =
        [
            "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK",
            "yyyy-MM-dd'T'HH:mm:ssK",
        ];
        return DateTimeOffset.TryParseExact(value, formats, CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal, out var date)
            ? date.ToUniversalTime()
            : null;
    }

    public static string Serialize(Note note)
    {
        var fm = new StringBuilder("---\n");
        fm.Append("id: ").Append(note.IdString).Append('\n');
        fm.Append("title: \"").Append(EscapeYaml(note.Title)).Append("\"\n");
        fm.Append("type: ").Append(note.CategoryType.RawValue()).Append('\n');
        if (!string.IsNullOrEmpty(note.TargetName))
            fm.Append("target: \"").Append(EscapeYaml(note.TargetName)).Append("\"\n");
        fm.Append("created_at: ").Append(FormatDate(note.CreatedAt)).Append('\n');
        fm.Append("updated_at: ").Append(FormatDate(note.UpdatedAt)).Append('\n');
        if (note.IsPinned) fm.Append("pinned: true\n");
        if (note.Tags.Count > 0)
            fm.Append("tags: [").Append(string.Join(", ", note.Tags.Select(t => $"\"{t}\""))).Append("]\n");
        fm.Append("---\n\n");
        return fm + note.Content;
    }

    /// <summary>
    /// Splits <c>---</c> delimited frontmatter from the body without altering the body. Delimiters must be
    /// lines of their own, so "---" in a title or the body is never mistaken for one. null when the text
    /// has no complete frontmatter block.
    /// </summary>
    public static (string Yaml, string Body)? SplitFrontmatter(string raw)
    {
        if (!raw.StartsWith("---", StringComparison.Ordinal)) return null;

        var cursor = 0;
        (string Text, int Next)? NextLine()
        {
            if (cursor >= raw.Length) return null;
            var newline = raw.IndexOf('\n', cursor);
            return newline < 0 ? (raw[cursor..], raw.Length) : (raw[cursor..newline], newline + 1);
        }
        // Unlike the Mac app, a "\r" before the "\n" is allowed, so files saved with Windows line endings parse
        static bool IsDelimiter(string line) => line.TrimEnd('\r').Trim(' ', '\t') == "---";

        if (NextLine() is not { } opening || !IsDelimiter(opening.Text)) return null;
        cursor = opening.Next;
        var yamlStart = cursor;
        while (NextLine() is { } line)
        {
            if (IsDelimiter(line.Text))
            {
                var yaml = raw[yamlStart..cursor];
                var bodyStart = line.Next;
                // Serialize writes one blank line between the frontmatter and the body
                if (string.CompareOrdinal(raw, bodyStart, "\r\n", 0, 2) == 0) bodyStart += 2;
                else if (bodyStart < raw.Length && raw[bodyStart] == '\n') bodyStart += 1;
                return (yaml, raw[bodyStart..]);
            }
            cursor = line.Next;
        }
        return null;
    }

    public static string EscapeYaml(string value) => value
        .Replace("\\", "\\\\")
        .Replace("\"", "\\\"")
        .Replace("\n", "\\n")
        .Replace("\r", "\\r");

    public static string UnescapeYaml(string value)
    {
        var result = new StringBuilder(value.Length);
        for (var i = 0; i < value.Length; i++)
        {
            var ch = value[i];
            if (ch != '\\' || i + 1 >= value.Length)
            {
                result.Append(ch);
                continue;
            }
            var escaped = value[++i];
            switch (escaped)
            {
                case 'n': result.Append('\n'); break;
                case 'r': result.Append('\r'); break;
                case '"' or '\\': result.Append(escaped); break;
                // Not an escape the apps write: keep it, e.g. files edited by hand
                default: result.Append(ch).Append(escaped); break;
            }
        }
        return result.ToString();
    }

    /// <summary>
    /// Parses a note file. Dates missing from the frontmatter come from the file's timestamps when
    /// <paramref name="filePath"/> is given.
    /// </summary>
    public static Note Parse(string raw, string? filePath = null)
    {
        var id = Guid.NewGuid();
        var title = "";
        var category = CategoryType.Inbox;
        string? target = null;
        DateTimeOffset? created = null;
        DateTimeOffset? updated = null;
        var tags = new List<string>();
        var pinned = false;
        var body = raw;

        if (SplitFrontmatter(raw) is { } split)
        {
            body = split.Body;
            // Split on "\n" only: titles may hold other Unicode line separators
            foreach (var line in split.Yaml.Split('\n'))
            {
                var colon = line.IndexOf(':');
                if (colon < 0) continue;
                var key = line[..colon].Trim();
                var val = line[(colon + 1)..].Trim();
                if (key.Length == 0) continue;
                if (val.Length >= 2 && val.StartsWith('"') && val.EndsWith('"'))
                    val = UnescapeYaml(val[1..^1]);

                switch (key)
                {
                    case "id":
                        if (Guid.TryParseExact(val, "D", out var parsed)) id = parsed;
                        break;
                    case "title":
                        title = val;
                        break;
                    case "type":
                        if (CategoryTypeExtensions.FromRawValue(val) is { } type) category = type;
                        break;
                    case "target":
                        target = val;
                        break;
                    case "pinned":
                        pinned = val.Equals("true", StringComparison.OrdinalIgnoreCase);
                        break;
                    case "created_at":
                        created = ParseDate(val) ?? created;
                        break;
                    case "updated_at":
                        updated = ParseDate(val) ?? updated;
                        break;
                    case "tags":
                        tags = val.Trim('[', ']')
                            .Split(',')
                            .Select(t => t.Trim(' ', '\t').Trim('"'))
                            .Where(t => t.Length > 0)
                            .ToList();
                        break;
                }
            }
        }

        if (filePath is not null && (created is null || updated is null) && File.Exists(filePath))
        {
            updated ??= File.GetLastWriteTimeUtc(filePath);
            created ??= File.GetCreationTimeUtc(filePath);
        }
        var now = DateTimeOffset.UtcNow;

        // Tags written in the body count even when the frontmatter is older than the body
        var seenTags = new HashSet<string>(tags, StringComparer.OrdinalIgnoreCase);
        tags.AddRange(Mentions.Names(Mentions.Kind.Tag, body).Where(seenTags.Add));

        var note = new Note
        {
            Id = id,
            Title = title,
            Content = body,
            CategoryType = category,
            TargetName = target,
            CreatedAt = created ?? now,
            UpdatedAt = updated ?? now,
            Tags = tags,
            FilePath = filePath,
            IsPinned = pinned,
        };
        return note.Title.Length == 0 ? note with { Title = note.DisplayTitle } : note;
    }
}
