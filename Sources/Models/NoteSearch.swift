import Foundation

public struct SearchResult: Identifiable, Sendable {
    public var id: UUID { note.id }
    public let note: Note
    public let score: Int
    /// A short stretch of the body around the first match; nil when only the title or tags matched
    public let snippet: String?
}

/// Global note search. Every whitespace separated term must match somewhere in the note
/// (title, body, tags or destination), ignoring case and accents. A term starting with `#`
/// matches tags only.
public enum NoteSearch {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0 != "#" }
    }

    public static func search(_ query: String, in notes: [Note], limit: Int = 50) -> [SearchResult] {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return [] }

        var results: [SearchResult] = []
        for note in notes {
            if let result = match(note, terms: terms) { results.append(result) }
        }
        results.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.note.updatedAt > $1.note.updatedAt
        }
        return Array(results.prefix(limit))
    }

    private static func match(_ note: Note, terms: [String]) -> SearchResult? {
        var score = 0
        var snippet: String?
        let title = note.displayTitle
        let destination = note.destinationDisplay

        for term in terms {
            if term.hasPrefix("#") {
                let tag = String(term.dropFirst())
                guard let hit = note.tags.first(where: { $0.range(of: tag, options: options) != nil }) else { return nil }
                score += hit.compare(tag, options: options) == .orderedSame ? 12 : 8
                continue
            }

            var matched = false
            if let range = title.range(of: term, options: options) {
                matched = true
                score += range.lowerBound == title.startIndex ? 14 : 10
            }
            if note.tags.contains(where: { $0.range(of: term, options: options) != nil }) {
                matched = true
                score += 6
            }
            if destination.range(of: term, options: options) != nil {
                matched = true
                score += 3
            }
            if let range = note.content.range(of: term, options: options) {
                matched = true
                score += 1 + min(occurrences(of: term, in: note.content), 5)
                if snippet == nil { snippet = makeSnippet(in: note.content, around: range) }
            }
            if !matched { return nil }
        }
        if note.isPinned { score += 1 }
        return SearchResult(note: note, score: score, snippet: snippet)
    }

    private static func occurrences(of term: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while count < 6, let found = text.range(of: term, options: options, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<text.endIndex
        }
        return count
    }

    /// About 90 characters of one line around the match, with ellipses where it was cut.
    static func makeSnippet(in text: String, around range: Range<String.Index>) -> String {
        let lineStart = text[..<range.lowerBound].lastIndex(where: \.isNewline).map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[range.upperBound...].firstIndex(where: \.isNewline) ?? text.endIndex

        let start = text.index(range.lowerBound, offsetBy: -30, limitedBy: lineStart) ?? lineStart
        let end = text.index(range.upperBound, offsetBy: 60, limitedBy: lineEnd) ?? lineEnd

        var snippet = text[start..<end].trimmingCharacters(in: .whitespaces)
        if start > lineStart { snippet = "…" + snippet }
        if end < lineEnd { snippet += "…" }
        return snippet
    }
}
