namespace ScatteredNotes.Core.Models;

/// <summary>A note that looks related to another, and why.</summary>
/// <param name="SharedMarks">Marks the two notes share, as written: <c>#idea</c>, <c>@neil</c>.</param>
/// <param name="SharedWords">The words that tie them most, the rarest first.</param>
public sealed record RelatedNote(Guid Id, double Score, IReadOnlyList<string> SharedMarks, IReadOnlyList<string> SharedWords);

/// <summary>
/// Notes related to a note without reading their meaning: they carry the same <c>#tag</c> or <c>@person</c>, or they
/// use many of the same uncommon words. The same rules as the Mac app's <c>RelatedIndex</c>.
///
/// - A shared <c>#tag</c> or <c>@person</c> counts 0.2 each.
/// - Words are scored by TF-IDF (term frequency times inverse document frequency): a word counts more the more
///   often a note uses it and the fewer notes use it. Each note becomes a vector of such weights, scaled to length 1,
///   and two notes' similarity is the cosine of the angle between them, from 0 to 1.
/// - Words under 4 letters, numbers and a short list of common English words are ignored.
/// - A note is related when it shares a tag or person, or its word similarity is at least 0.2. Sharing only a
///   project is not enough, since a project holds notes of every kind; it only breaks ties.
///
/// Similarity is found through an inverted index (word to the notes that use it), so only notes that share at
/// least one word with the note are looked at.
/// </summary>
public sealed class RelatedIndex
{
    private const double MinimumWordSimilarity = 0.2;
    private const double MarkWeight = 0.2;
    private const double ProjectTieBreak = 0.01;
    private const int MinimumWordLength = 4;
    /// <summary>A word used by more than this share of the notes tells nothing apart, so it is not indexed.</summary>
    private const double CommonShare = 0.5;

    private static readonly HashSet<string> StopWords = new(
    [
        "about", "above", "after", "again", "also", "because", "been", "before", "being", "between", "both",
        "could", "does", "doing", "down", "during", "each", "from", "further", "have", "having", "here", "into",
        "just", "like", "more", "most", "much", "must", "only", "other", "over", "same", "should", "some", "such",
        "than", "that", "their", "them", "then", "there", "these", "they", "this", "those", "through", "under",
        "until", "very", "want", "were", "what", "when", "where", "which", "while", "will", "with", "would", "your",
    ]);

    private sealed record Entry(string? Project, Dictionary<string, string> Marks, Dictionary<string, double> Weights);

    private readonly Dictionary<Guid, Entry> _entries = [];
    private readonly Dictionary<string, List<(Guid Id, double Weight)>> _postings = [];
    private readonly Dictionary<Guid, DateTimeOffset> _order = [];

    public RelatedIndex(IEnumerable<Note> notes)
    {
        var all = notes.ToList();
        var total = Math.Max(all.Count, 1);
        var counts = new Dictionary<Guid, Dictionary<string, int>>();
        var documentFrequency = new Dictionary<string, int>();
        foreach (var note in all)
        {
            var own = new Dictionary<string, int>();
            foreach (var word in NoteLinkIndex.FoldedWords(note.DisplayTitle + "\n" + note.Content).Where(Counts))
                own[word] = own.GetValueOrDefault(word) + 1;
            counts[note.Id] = own;
            foreach (var word in own.Keys) documentFrequency[word] = documentFrequency.GetValueOrDefault(word) + 1;
        }
        foreach (var note in all)
        {
            var weights = new Dictionary<string, double>();
            foreach (var (word, count) in counts[note.Id])
            {
                var df = (double)documentFrequency.GetValueOrDefault(word, 1);
                // Words nearly every note uses say nothing; a word only one note uses cannot relate two notes, but
                // it still counts toward that note's length, so a note full of unique words matches few others
                if (all.Count > 2 && df / total > CommonShare) continue;
                weights[word] = (1 + Math.Log(count)) * Math.Log(1 + total / df);
            }
            var length = Math.Sqrt(weights.Values.Sum(w => w * w));
            if (length > 0) foreach (var word in weights.Keys.ToList()) weights[word] /= length;
            var marks = new Dictionary<string, string>();
            foreach (var tag in note.Tags) marks["#" + tag.ToLowerInvariant()] = "#" + tag;
            foreach (var person in note.People) marks["@" + person.ToLowerInvariant()] = "@" + person;
            var project = note.CategoryType == CategoryType.Project ? note.TargetName?.ToLowerInvariant() : null;
            _entries[note.Id] = new Entry(project, marks, weights);
            foreach (var (word, weight) in weights)
            {
                if (!_postings.TryGetValue(word, out var list)) _postings[word] = list = [];
                list.Add((note.Id, weight));
            }
            _order[note.Id] = note.UpdatedAt;
        }
    }

    private static bool Counts(string word) =>
        word.Length >= MinimumWordLength && !StopWords.Contains(word) && !word.All(char.IsDigit);

    /// <summary>Notes related to <paramref name="noteId"/>, best first, at most <paramref name="limit"/>, leaving out
    /// <paramref name="excluding"/> (such as notes already linked).</summary>
    public IReadOnlyList<RelatedNote> RelatedTo(Guid noteId, int limit = 5, IReadOnlySet<Guid>? excluding = null)
    {
        if (!_entries.TryGetValue(noteId, out var me)) return [];
        excluding ??= new HashSet<Guid>();

        // Word similarity: add up weight times weight over the words two notes share
        var dot = new Dictionary<Guid, double>();
        var sharedWords = new Dictionary<Guid, List<(string Word, double Weight)>>();
        foreach (var (word, weight) in me.Weights)
        {
            if (!_postings.TryGetValue(word, out var posting)) continue;
            foreach (var (id, otherWeight) in posting)
            {
                if (id == noteId) continue;
                var product = weight * otherWeight;
                dot[id] = dot.GetValueOrDefault(id) + product;
                if (!sharedWords.TryGetValue(id, out var list)) sharedWords[id] = list = [];
                list.Add((word, product));
            }
        }
        // Notes that share a mark but no word still count
        var candidates = new HashSet<Guid>(dot.Keys);
        if (me.Marks.Count > 0)
        {
            foreach (var (id, entry) in _entries)
            {
                if (id != noteId && entry.Marks.Keys.Any(me.Marks.ContainsKey)) candidates.Add(id);
            }
        }

        var found = new List<RelatedNote>();
        foreach (var id in candidates.Where(id => !excluding.Contains(id)))
        {
            var other = _entries[id];
            var shared = me.Marks.Keys.Where(other.Marks.ContainsKey).OrderBy(k => k, StringComparer.Ordinal).ToList();
            var similarity = dot.GetValueOrDefault(id);
            if (shared.Count == 0 && similarity < MinimumWordSimilarity) continue;
            var sameProject = me.Project is not null && me.Project == other.Project;
            var score = similarity + shared.Count * MarkWeight + (sameProject ? ProjectTieBreak : 0);
            var words = (sharedWords.GetValueOrDefault(id) ?? [])
                .OrderByDescending(w => w.Weight).ThenBy(w => w.Word, StringComparer.Ordinal)
                .Take(3).Select(w => w.Word).ToList();
            found.Add(new RelatedNote(id, score, shared.Select(k => me.Marks[k]).ToList(), words));
        }
        // Best first; newer notes, then the id, settle ties so the order never shuffles
        return found
            .OrderByDescending(r => r.Score)
            .ThenByDescending(r => _order.GetValueOrDefault(r.Id))
            .ThenBy(r => r.Id.ToString("D").ToUpperInvariant(), StringComparer.Ordinal)
            .Take(limit).ToList();
    }
}
