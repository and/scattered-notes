using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace ScatteredNotes.Core.Models;

/// <summary>
/// A place in a note's text that points at another note: either the other note's title written out, or an
/// explicit <c>[[Title]]</c>.
/// </summary>
/// <param name="Target">The note it points at. Null for a <c>[[Title]]</c> that no note has.</param>
/// <param name="Text">The words that were matched, as written in the text (for <c>[[Title]]</c>, the title between the brackets).</param>
/// <param name="Start">Where it sits in the note's text, brackets included, as a UTF-16 offset.</param>
/// <param name="Length">Its length in UTF-16 units.</param>
/// <param name="IsExplicit">True for <c>[[Title]]</c>, false for a title found in the running text.</param>
public sealed record NoteLink(Guid? Target, string Text, int Start, int Length, bool IsExplicit);

/// <summary>
/// Which notes mention which: titles found in the text, explicit <c>[[Title]]</c> links, and the backlinks that
/// follow from them. The same rules as the Mac app's <c>NoteLinkIndex</c>, so a note shows the same links on every device.
///
/// Rules:
/// - Titles are compared by whole words, ignoring case and accents and anything between the words that is not a
///   letter or digit. "Plan: Q4" is found in "the plan Q4 review", and "Plan" is not found in "planning".
/// - A title found in the running text must be at least 3 characters long, so a note called "a" does not link
///   everywhere. <c>[[Title]]</c> has no such limit.
/// - Where titles overlap, the longest one wins and the text it covers is used up.
/// - A note does not link to itself. Text inside <c>[[ ]]</c> is never also counted as a plain mention.
/// - Two notes with the same title both get the link.
///
/// Matching walks the text's words once and follows them through a trie of the titles' words, so the cost grows
/// with the length of the text and of the longest title, not with the number of notes.
/// </summary>
public sealed partial class NoteLinkIndex
{
    /// <summary>Titles with more words than this are not looked for in the running text.</summary>
    private const int LongestTitleWords = 12;

    private sealed class Node
    {
        public readonly Dictionary<string, int> Next = [];
        public readonly List<Guid> Ids = [];
    }

    private readonly Dictionary<Guid, Note> _notes = [];
    private readonly List<Node> _trie = [new Node()];
    private readonly Dictionary<string, List<Guid>> _byFullTitle = [];
    private readonly Dictionary<Guid, List<NoteLink>> _linksBySource = [];
    private readonly Dictionary<Guid, List<Guid>> _backlinksByTarget = [];

    public NoteLinkIndex(IEnumerable<Note> notes)
    {
        var all = notes.ToList();
        foreach (var note in all)
        {
            _notes[note.Id] = note;
            var title = note.DisplayTitle;
            // A note with no title and no text has nothing to be found by
            if (title == "Untitled Note") continue;
            var words = Words(title).Select(w => w.Folded).ToList();
            if (words.Count == 0) continue;
            var full = string.Join(' ', words);
            if (!_byFullTitle.TryGetValue(full, out var same)) _byFullTitle[full] = same = [];
            same.Add(note.Id);
            if (words.Sum(w => w.Length) >= 3 && words.Count <= LongestTitleWords)
            {
                var at = 0;
                foreach (var word in words)
                {
                    if (_trie[at].Next.TryGetValue(word, out var step))
                    {
                        at = step;
                    }
                    else
                    {
                        _trie.Add(new Node());
                        _trie[at].Next[word] = _trie.Count - 1;
                        at = _trie.Count - 1;
                    }
                }
                _trie[at].Ids.Add(note.Id);
            }
        }

        var backlinks = new Dictionary<Guid, HashSet<Guid>>();
        foreach (var note in all)
        {
            var found = Scan(note.Content, note.Id);
            _linksBySource[note.Id] = found;
            foreach (var link in found)
            {
                if (link.Target is not { } target) continue;
                if (!backlinks.TryGetValue(target, out var set)) backlinks[target] = set = [];
                set.Add(note.Id);
            }
        }
        // Newest note first, the order the note list uses; the id settles ties so the order never changes
        foreach (var (target, sources) in backlinks)
        {
            _backlinksByTarget[target] = sources
                .OrderByDescending(id => _notes[id].UpdatedAt)
                .ThenBy(id => id.ToString("D").ToUpperInvariant(), StringComparer.Ordinal)
                .ToList();
        }
    }

    /// <summary>What to write in place of a mention to make it an explicit link: <c>[[Title]]</c>. Null when the title
    /// cannot be written that way, because it holds a bracket or a line break.</summary>
    public static string? ExplicitText(string title)
    {
        if (title.Length == 0 || title.Any(c => c is '[' or ']' or '\n' or '\r')) return null;
        return $"[[{title}]]";
    }

    /// <summary>The content with the mention at <paramref name="link"/> replaced by <c>[[Title]]</c>; null when that cannot be done.</summary>
    public static string? MakingExplicit(NoteLink link, string title, string content)
    {
        if (link.IsExplicit || link.Start < 0 || link.Start + link.Length > content.Length) return null;
        return ExplicitText(title) is { } replacement ? content[..link.Start] + replacement + content[(link.Start + link.Length)..] : null;
    }

    /// <summary>Every link in the note, in the order they appear in its text.</summary>
    public IReadOnlyList<NoteLink> LinksFrom(Guid noteId) => _linksBySource.TryGetValue(noteId, out var links) ? links : [];

    /// <summary>The notes that link to this one, newest first, each once.</summary>
    public IReadOnlyList<Guid> BacklinksTo(Guid noteId) => _backlinksByTarget.TryGetValue(noteId, out var ids) ? ids : [];

    /// <summary>The notes this one links to, in the order they first appear, each once.</summary>
    public IReadOnlyList<Guid> LinkedNotesFrom(Guid noteId)
    {
        var seen = new HashSet<Guid>();
        return LinksFrom(noteId).Where(l => l.Target is not null).Select(l => l.Target!.Value).Where(seen.Add).ToList();
    }

    // MARK: Scanning

    private readonly record struct Word(int Start, int Length, string Folded);

    [GeneratedRegex(@"\[\[([^\[\]\n\r]+)\]\]")]
    private static partial Regex ExplicitLink();

    /// <summary>The folded words of a text, for the related-notes rules, which count words the same way.</summary>
    internal static List<string> FoldedWords(string text) => Words(text).Select(w => w.Folded).ToList();

    /// <summary>The words of a text: runs of letters, marks and digits, which is the same rule on every device.</summary>
    private static List<Word> Words(string text)
    {
        var result = new List<Word>();
        var current = new StringBuilder();
        var start = 0;
        var offset = 0;
        var length = 0;
        var ascii = true;
        void Finish()
        {
            if (length == 0) return;
            result.Add(new Word(start, length, ascii ? current.ToString().ToLowerInvariant() : Fold(current.ToString())));
            current.Clear();
            length = 0;
            ascii = true;
        }
        foreach (var rune in text.EnumerateRunes())
        {
            var width = rune.Utf16SequenceLength;
            if (IsWordCharacter(rune))
            {
                if (length == 0) start = offset;
                current.Append(rune.ToString());
                length += width;
                if (rune.Value >= 0x80) ascii = false;
            }
            else
            {
                Finish();
            }
            offset += width;
        }
        Finish();
        return result;
    }

    private static bool IsWordCharacter(Rune rune) => Rune.GetUnicodeCategory(rune) switch
    {
        UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter or UnicodeCategory.TitlecaseLetter
            or UnicodeCategory.ModifierLetter or UnicodeCategory.OtherLetter
            or UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark
            or UnicodeCategory.DecimalDigitNumber or UnicodeCategory.LetterNumber or UnicodeCategory.OtherNumber => true,
        _ => false,
    };

    /// <summary>Lower case with the accents taken off.</summary>
    private static string Fold(string word)
    {
        var decomposed = word.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        }
        return sb.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    private List<NoteLink> Scan(string text, Guid source)
    {
        var found = new List<NoteLink>();

        // [[Title]] first: what is inside the brackets is not looked at again as running text
        var covered = new List<(int Start, int End)>();
        foreach (Match match in ExplicitLink().Matches(text))
        {
            covered.Add((match.Index, match.Index + match.Length));
            var inner = match.Groups[1].Value.Trim(' ', '\t');
            var key = string.Join(' ', Words(inner).Select(w => w.Folded));
            _byFullTitle.TryGetValue(key, out var ids);
            var targets = (ids ?? []).Where(id => id != source).ToList();
            if (targets.Count == 0)
            {
                // No note has this title, or only the note itself does
                if (ids is null) found.Add(new NoteLink(null, inner, match.Index, match.Length, true));
            }
            else
            {
                foreach (var target in targets) found.Add(new NoteLink(target, inner, match.Index, match.Length, true));
            }
        }

        // Titles in the running text
        var words = Words(text).Where(w => !covered.Any(c => Math.Min(c.End, w.Start + w.Length) > Math.Max(c.Start, w.Start))).ToList();
        var index = 0;
        while (index < words.Count)
        {
            // Walk the text's words through the trie, keeping the longest title that ends along the way
            var at = 0;
            (int Length, List<Guid> Ids)? best = null;
            var length = 0;
            while (index + length < words.Count && _trie[at].Next.TryGetValue(words[index + length].Folded, out var step))
            {
                at = step;
                length++;
                if (_trie[at].Ids.Count > 0) best = (length, _trie[at].Ids);
            }
            if (best is not { } hit)
            {
                index++;
                continue;
            }
            var start = words[index].Start;
            var last = words[index + hit.Length - 1];
            var end = last.Start + last.Length;
            foreach (var id in hit.Ids.Where(id => id != source))
                found.Add(new NoteLink(id, text[start..end], start, end - start, false));
            index += hit.Length;
        }
        return found.OrderBy(l => l.Start).ToList();
    }
}
