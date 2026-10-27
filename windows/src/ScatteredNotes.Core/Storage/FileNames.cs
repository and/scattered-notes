using System.Globalization;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Storage;

/// <summary>Names for note files and project and area folders that are valid on both Windows and macOS.</summary>
public static class FileNames
{
    private static readonly HashSet<string> Reserved = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    };

    private static bool IsInvalid(char ch) => ch < 32 || "\\/:*?\"<>|".Contains(ch);

    /// <summary>
    /// The title part of a note file name, as the Mac app makes it: runs of invalid characters and
    /// whitespace become "-", cut to 40 characters.
    /// </summary>
    public static string SanitizeTitle(string title)
    {
        var parts = title.Split(ch => IsInvalid(ch) || ch is ' ' or '\n' or '\t' or '\r');
        var joined = string.Join("-", parts.Where(p => p.Length > 0));
        return CutAt(joined, 40);
    }

    /// <summary><c>yyyy-MM-dd_&lt;title&gt;.md</c>, the date being when the note was created.</summary>
    public static string NoteFileName(Note note, bool withIdSuffix = false)
    {
        var baseName = SanitizeTitle(note.DisplayTitle);
        if (baseName.Length == 0) baseName = "note";
        var date = note.CreatedAt.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        return withIdSuffix ? $"{date}_{baseName}_{note.IdString[..6]}.md" : $"{date}_{baseName}.md";
    }

    /// <summary>
    /// A project or area folder name Windows accepts: no invalid characters, no trailing dots or spaces,
    /// not a reserved device name. Returns "" when nothing usable is left.
    /// </summary>
    public static string SanitizeFolderName(string name)
    {
        var cleaned = new string(name.Trim().Select(ch => IsInvalid(ch) ? '-' : ch).ToArray()).TrimEnd('.', ' ');
        if (cleaned.Length == 0) return "";
        var stem = cleaned.Split('.')[0];
        return Reserved.Contains(stem) ? cleaned + "_" : cleaned;
    }

    private static string[] Split(this string text, Func<char, bool> isSeparator)
    {
        var parts = new List<string>();
        var start = 0;
        for (var i = 0; i < text.Length; i++)
        {
            if (!isSeparator(text[i])) continue;
            parts.Add(text[start..i]);
            start = i + 1;
        }
        parts.Add(text[start..]);
        return parts.ToArray();
    }

    /// <summary>Cuts to at most <paramref name="max"/> characters without splitting a surrogate pair.</summary>
    private static string CutAt(string text, int max)
    {
        if (text.Length <= max) return text;
        var end = char.IsHighSurrogate(text[max - 1]) ? max - 1 : max;
        return text[..end];
    }
}
