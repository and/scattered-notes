import Foundation

/// A note whose meaning looks close to another's, from word meaning rather than shared words
public struct SuggestedNote: Hashable, Sendable {
    public let id: UUID
    /// Cosine similarity of the two notes' meaning vectors, from -1 to 1; in practice about 0.5 to 0.8 for notes worth showing
    public let similarity: Double
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
    /// Below this the notes are not close enough to suggest
    public static let minimumSimilarity = 0.5

    private let vectors: [UUID: [Double]]
    private let order: [UUID: Date]

    public init(vectors: [UUID: [Double]], updated: [UUID: Date] = [:]) {
        self.vectors = vectors
        self.order = updated
    }

    /// Words that carry no meaning of their own and would pull every note toward every other
    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "have", "has", "had", "are", "was", "were", "will",
        "would", "could", "should", "about", "into", "than", "then", "them", "they", "their", "there", "these",
        "those", "what", "when", "where", "which", "while", "your", "you", "not", "but", "can", "its", "also",
        "just", "like", "more", "most", "much", "some", "such", "only", "over", "very", "been", "being", "does",
        "doing", "each", "here", "other", "tomorrow", "today", "every", "help", "make", "made", "get", "got",
    ]

    /// The vector for a text: the average of its words' vectors, length 1. Nil when no word is known.
    public static func vector(for text: String, using words: WordVectors) -> [Double]? {
        var sum: [Double] = []
        var found = 0
        for word in NoteLinkIndex.foldedWords(in: text) where word.count >= 3 && !stopWords.contains(word) && !word.allSatisfy(\.isNumber) {
            guard let vector = words.vector(for: word) else { continue }
            if sum.isEmpty { sum = [Double](repeating: 0, count: vector.count) }
            guard vector.count == sum.count else { continue }
            for index in vector.indices { sum[index] += vector[index] }
            found += 1
        }
        guard found > 0 else { return nil }
        let length = sum.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? sum.map { $0 / length } : nil
    }

    /// The text a note is read by: its title and the start of its text. The agenda markers are left out.
    public static func text(of note: Note) -> String {
        let body = AgendaExtractor.withoutMarkers(String(note.content.prefix(800)))
        return note.displayTitle + "\n" + body
    }

    /// Notes close in meaning to `noteID`, best first, at most `limit`, leaving out `excluding`
    public func suggestions(for noteID: UUID, limit: Int = 5, excluding: Set<UUID> = []) -> [SuggestedNote] {
        guard let mine = vectors[noteID] else { return [] }
        var found: [SuggestedNote] = []
        for (id, other) in vectors where id != noteID && !excluding.contains(id) && other.count == mine.count {
            var dot = 0.0
            for index in mine.indices { dot += mine[index] * other[index] }
            if dot >= Self.minimumSimilarity { found.append(SuggestedNote(id: id, similarity: dot)) }
        }
        found.sort {
            if $0.similarity != $1.similarity { return $0.similarity > $1.similarity }
            let (a, b) = (order[$0.id] ?? .distantPast, order[$1.id] ?? .distantPast)
            return a != b ? a > b : $0.id.uuidString < $1.id.uuidString
        }
        return Array(found.prefix(limit))
    }
}
