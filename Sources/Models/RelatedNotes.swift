import Foundation

/// A note that looks related to another, and why
public struct RelatedNote: Hashable, Sendable {
    public let id: UUID
    public let score: Double
    /// Marks the two notes share, as written: `#idea`, `@neil`
    public let sharedMarks: [String]
    /// The words that tie them most, the rarest first
    public let sharedWords: [String]
}

/// Notes related to a note without reading their meaning: they carry the same `#tag` or `@person`, or they use many
/// of the same uncommon words. The same rules on every device; the Windows and Android apps port them.
///
/// - A shared `#tag` or `@person` counts 0.2 each.
/// - Words are scored by TF-IDF (term frequency times inverse document frequency): a word counts more the more
///   often a note uses it and the fewer notes use it. Each note becomes a vector of such weights, scaled to length 1,
///   and two notes' similarity is the cosine of the angle between them (their dot product), from 0 to 1.
/// - Words under 4 letters, numbers and a short list of common English words are ignored.
/// - A note is related when it shares a tag or person, or its word similarity is at least 0.2. Sharing only a
///   project is not enough, since a project holds notes of every kind; it only breaks ties.
///
/// Similarity is found through an inverted index (word to the notes that use it), so only notes that share
/// at least one word with the note are looked at, however many notes there are.
public struct RelatedIndex: Sendable {
    private static let minimumWordSimilarity = 0.2
    private static let markWeight = 0.2
    private static let projectTieBreak = 0.01
    private static let minimumWordLength = 4
    /// A word used by more than this share of the notes tells nothing apart, so it is not indexed
    private static let commonShare = 0.5

    private static let stopWords: Set<String> = [
        "about", "above", "after", "again", "also", "because", "been", "before", "being", "between", "both",
        "could", "does", "doing", "down", "during", "each", "from", "further", "have", "having", "here", "into",
        "just", "like", "more", "most", "much", "must", "only", "other", "over", "same", "should", "some", "such",
        "than", "that", "their", "them", "then", "there", "these", "they", "this", "those", "through", "under",
        "until", "very", "want", "were", "what", "when", "where", "which", "while", "will", "with", "would", "your",
    ]

    private struct Entry: Sendable {
        let project: String?
        let marks: [String: String]   // folded mark -> mark as written
        let weights: [String: Double]
    }

    private let entries: [UUID: Entry]
    /// Word -> the notes that use it, with the word's weight in each
    private let postings: [String: [(id: UUID, weight: Double)]]
    private let order: [UUID: Date]

    public init(notes: [Note]) {
        let total = Double(max(notes.count, 1))
        var counts: [UUID: [String: Int]] = [:]
        var documentFrequency: [String: Int] = [:]
        for note in notes {
            var own: [String: Int] = [:]
            for word in NoteLinkIndex.foldedWords(in: note.displayTitle + "\n" + note.content) where Self.counts(word) {
                own[word, default: 0] += 1
            }
            counts[note.id] = own
            for word in own.keys { documentFrequency[word, default: 0] += 1 }
        }
        var entries: [UUID: Entry] = [:]
        var postings: [String: [(id: UUID, weight: Double)]] = [:]
        var order: [UUID: Date] = [:]
        for note in notes {
            var weights: [String: Double] = [:]
            for (word, count) in counts[note.id] ?? [:] {
                let df = Double(documentFrequency[word] ?? 1)
                // Words nearly every note uses say nothing; a word only one note uses cannot relate two notes, but
                // it still counts toward that note's length, so a note full of unique words matches few others
                if notes.count > 2, df / total > Self.commonShare { continue }
                weights[word] = (1 + log(Double(count))) * log(1 + total / df)
            }
            let length = weights.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
            if length > 0 { weights = weights.mapValues { $0 / length } }
            var marks: [String: String] = [:]
            for tag in note.tags { marks["#" + tag.lowercased()] = "#" + tag }
            for person in note.people { marks["@" + person.lowercased()] = "@" + person }
            let project = note.categoryType == .project ? note.targetName?.lowercased() : nil
            entries[note.id] = Entry(project: project, marks: marks, weights: weights)
            for (word, weight) in weights { postings[word, default: []].append((note.id, weight)) }
            order[note.id] = note.updatedAt
        }
        self.entries = entries
        self.postings = postings
        self.order = order
    }

    private static func counts(_ word: String) -> Bool {
        word.count >= minimumWordLength && !stopWords.contains(word) && !word.allSatisfy(\.isNumber)
    }

    /// Notes related to `noteID`, best first, at most `limit`, leaving out `excluding` (such as notes already linked)
    public func related(to noteID: UUID, limit: Int = 5, excluding: Set<UUID> = []) -> [RelatedNote] {
        guard let me = entries[noteID] else { return [] }

        // Word similarity: add up weight times weight over the words two notes share
        var dot: [UUID: Double] = [:]
        var sharedWords: [UUID: [(word: String, weight: Double)]] = [:]
        for (word, weight) in me.weights {
            for posting in postings[word] ?? [] where posting.id != noteID {
                let product = weight * posting.weight
                dot[posting.id, default: 0] += product
                sharedWords[posting.id, default: []].append((word, product))
            }
        }
        // Notes that share a mark but no word still count
        var candidates = Set(dot.keys)
        if !me.marks.isEmpty {
            for (id, entry) in entries where id != noteID && !entry.marks.keys.filter({ me.marks[$0] != nil }).isEmpty {
                candidates.insert(id)
            }
        }

        var found: [RelatedNote] = []
        for id in candidates where !excluding.contains(id) {
            guard let other = entries[id] else { continue }
            let shared = me.marks.keys.filter { other.marks[$0] != nil }.sorted()
            let similarity = dot[id] ?? 0
            guard !shared.isEmpty || similarity >= Self.minimumWordSimilarity else { continue }
            let sameProject = me.project != nil && me.project == other.project
            let score = similarity + Double(shared.count) * Self.markWeight + (sameProject ? Self.projectTieBreak : 0)
            let words = (sharedWords[id] ?? []).sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.word < $1.word }
                .prefix(3).map(\.word)
            found.append(RelatedNote(id: id, score: score, sharedMarks: shared.compactMap { me.marks[$0] }, sharedWords: Array(words)))
        }
        // Best first; newer notes, then the id, settle ties so the order never shuffles
        found.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            let (a, b) = (order[$0.id] ?? .distantPast, order[$1.id] ?? .distantPast)
            return a != b ? a > b : $0.id.uuidString < $1.id.uuidString
        }
        return Array(found.prefix(limit))
    }
}
