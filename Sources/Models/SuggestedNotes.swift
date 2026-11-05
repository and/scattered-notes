import Foundation

/// A note whose meaning looks close to another's, from word meaning rather than shared words
public struct SuggestedNote: Hashable, Sendable {
    public let id: UUID
    /// Cosine similarity of the two notes' meaning vectors, from -1 to 1; in practice about 0.5 to 0.8 for notes worth showing
    public let similarity: Double
    /// The similarity plus the bonuses for shared marks and project; what notes are ranked and cut off by
    public let score: Double
}

/// Looks up the vector for a word, so the maths below can be tested without Apple's model
public protocol WordVectors {
    func vector(for word: String) -> [Double]?
}

/// Notes that are about the same thing in different words, such as "dentist" and "teeth appointment".
///
/// Each note becomes one vector: the average of the vectors of its words, found in a table of word meanings
/// (a word embedding: every word is a list of numbers, and words used in similar ways get similar lists). The
/// average is scaled to length 1, so two notes' similarity is their dot product, the cosine of the angle between
/// them. The vectors come from Apple's on-device model, so nothing leaves the Mac; the Windows and Android apps
/// have no such model built in, and results from a model would differ between devices, so this stays a Mac and
/// iPhone suggestion and never writes to the notes.
///
/// Apple's whole-sentence model was tried first and ranked "call the dentist" nearer "file the tax return" than
/// "teeth appointment", so averaged word vectors are used: they separated every related pair tried from the
/// unrelated ones.
public struct SuggestedIndex: Sendable {
    /// Below this score the notes are not close enough to suggest
    public static let minimumScore = 0.5
    /// A shared #tag or @person adds this to the score, up to twice: two notes about similar things that also share
    /// a mark are far more likely to be related
    static let sharedMarkBonus = 0.05
    /// Being in the same project adds this
    static let sameProjectBonus = 0.02

    private let vectors: [UUID: [Double]]
    private let marks: [UUID: Set<String>]
    private let projects: [UUID: String]
    private let order: [UUID: Date]

    public init(vectors: [UUID: [Double]], marks: [UUID: Set<String>] = [:], projects: [UUID: String] = [:], updated: [UUID: Date] = [:]) {
        self.vectors = vectors
        self.marks = marks
        self.projects = projects
        self.order = updated
    }

    /// The tags and people of a note, lower-cased, as `#tag` and `@name`
    public static func marks(of note: Note) -> Set<String> {
        Set(note.tags.map { "#" + $0.lowercased() } + note.people.map { "@" + $0.lowercased() })
    }

    /// Words that carry no meaning of their own and would pull every note toward every other
    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "have", "has", "had", "are", "was", "were", "will",
        "would", "could", "should", "about", "into", "than", "then", "them", "they", "their", "there", "these",
        "those", "what", "when", "where", "which", "while", "your", "you", "not", "but", "can", "its", "also",
        "just", "like", "more", "most", "much", "some", "such", "only", "over", "very", "been", "being", "does",
        "doing", "each", "here", "other", "tomorrow", "today", "every", "help", "make", "made", "get", "got",
        "untitled", "note", "notes",
    ]

    /// The words of a text that count: three letters or more, not a stop word, not a number
    public static func meaningfulWords(in text: String) -> [String] {
        NoteLinkIndex.foldedWords(in: text).filter { $0.count >= 3 && !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    /// Title words count double: a note is mostly about what it is called
    static let titleWeight = 2.0

    /// A note's words' vectors added up, each scaled by how much the word says (`weight`, 1 for every word if not
    /// given; the title's words count double). Not yet scaled to length 1: see `init(sums:...)`. Nil when fewer than
    /// `minimumWords` known words are found.
    public static func sum(title: String, body: String, using words: WordVectors, weight: (String) -> Double = { _ in 1 }) -> [Double]? {
        var sum: [Double] = []
        var found = 0
        func add(_ text: String, times: Double) {
            for word in meaningfulWords(in: text) {
                guard let vector = words.vector(for: word) else { continue }
                if sum.isEmpty { sum = [Double](repeating: 0, count: vector.count) }
                guard vector.count == sum.count else { continue }
                let scale = times * weight(word)
                for index in vector.indices { sum[index] += vector[index] * scale }
                found += 1
            }
        }
        add(title, times: titleWeight)
        add(body, times: 1)
        return found >= minimumWords ? sum : nil
    }

    /// Fewer known words than this and a note is left out: one word says too little, and the one-word notes that real
    /// collections hold ("test", "ideas") would match each other perfectly
    static let minimumWords = 2

    /// The same as `sum`, scaled to length 1
    public static func vector(title: String, body: String, using words: WordVectors, weight: (String) -> Double = { _ in 1 }) -> [Double]? {
        guard let total = sum(title: title, body: body, using: words, weight: weight) else { return nil }
        return unit(total)
    }

    static func unit(_ vector: [Double]) -> [Double]? {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? vector.map { $0 / length } : nil
    }

    /// Builds the index from the notes' summed vectors. Every word vector shares a large common part, which makes
    /// any two notes look alike; the average of all the notes' vectors is taken off each one first, so what is left
    /// is what sets a note apart. Then each is scaled to length 1.
    public init(sums: [UUID: [Double]], marks: [UUID: Set<String>] = [:], projects: [UUID: String] = [:], updated: [UUID: Date] = [:]) {
        // Each note is scaled to length 1 first, so a long note does not pull the average toward itself
        let scaled = sums.compactMapValues { Self.unit($0) }
        var mean: [Double] = []
        for vector in scaled.values {
            if mean.isEmpty { mean = [Double](repeating: 0, count: vector.count) }
            guard vector.count == mean.count else { continue }
            for index in vector.indices { mean[index] += vector[index] }
        }
        let count = Double(max(scaled.count, 1))
        mean = mean.map { $0 / count }
        var centred: [UUID: [Double]] = [:]
        for (id, vector) in scaled where vector.count == mean.count {
            // With a single note there is nothing to compare, so the average is not taken off
            let adjusted = scaled.count > 1 ? zip(vector, mean).map { $0 - $1 } : vector
            if let unit = Self.unit(adjusted) { centred[id] = unit }
        }
        self.init(vectors: centred, marks: marks, projects: projects, updated: updated)
    }

    /// The vector for a plain text, every word counting the same
    public static func vector(for text: String, using words: WordVectors) -> [Double]? {
        vector(title: "", body: text, using: words)
    }

    /// How much a word says, from how many of the notes use it: a word in every note says nothing, a word in one
    /// says a lot. `documentFrequency` is the number of notes using each word, `count` the number of notes.
    public static func weight(of word: String, documentFrequency: [String: Int], count: Int) -> Double {
        let used = Double(max(documentFrequency[word] ?? 1, 1))
        return log(1 + Double(max(count, 1)) / used)
    }

    /// The start of a note's text, the part it is read by. The agenda markers are left out.
    public static func body(of note: Note) -> String {
        AgendaExtractor.withoutMarkers(String(note.content.prefix(800)))
    }

    /// The text a note is read by: its title and the start of its text
    public static func text(of note: Note) -> String {
        note.displayTitle + "\n" + body(of: note)
    }

    /// Notes close in meaning to `noteID`, best first, at most `limit`, leaving out `excluding`
    public func suggestions(for noteID: UUID, limit: Int = 5, excluding: Set<UUID> = []) -> [SuggestedNote] {
        guard let mine = vectors[noteID] else { return [] }
        var found: [SuggestedNote] = []
        let myMarks = marks[noteID] ?? []
        for (id, other) in vectors where id != noteID && !excluding.contains(id) && other.count == mine.count {
            var dot = 0.0
            for index in mine.indices { dot += mine[index] * other[index] }
            let shared = myMarks.intersection(marks[id] ?? []).count
            var score = dot + Double(min(shared, 2)) * Self.sharedMarkBonus
            if let project = projects[noteID], project == projects[id] { score += Self.sameProjectBonus }
            if score >= Self.minimumScore { found.append(SuggestedNote(id: id, similarity: dot, score: score)) }
        }
        found.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            let (a, b) = (order[$0.id] ?? .distantPast, order[$1.id] ?? .distantPast)
            return a != b ? a > b : $0.id.uuidString < $1.id.uuidString
        }
        return Array(found.prefix(limit))
    }
}
