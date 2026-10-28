import Foundation

/// The inline marks a note can carry: `@person`, `#tag` and `+project`.
///
/// A mark counts only at the start of a word (after the start of the line, a space or an opening
/// bracket) and when a letter follows the symbol, so "user@mail.com", "C#", "+91 98…" and "#1" are
/// left alone. A mark runs on through letters, digits, `-`, `_` and `.`, and loses a trailing `.`,
/// so "#idea." is the tag "idea". Shared by the Mac and iOS apps.
public enum Mentions {
    public enum Kind: Character, CaseIterable, Sendable {
        case person = "@"
        case tag = "#"
        case project = "+"
    }

    public struct Mark: Hashable, Sendable {
        public let kind: Kind
        public let name: String
        /// Where the mark, symbol included, sits in the text it was found in
        public let range: Range<String.Index>
    }

    /// Every mark in `text`, in order.
    public static func marks(in text: String) -> [Mark] {
        var marks: [Mark] = []
        var index = text.startIndex
        var previous: Character?
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if let kind = Kind(rawValue: character),
               previous.map(startsWord) ?? true,
               next < text.endIndex, text[next].isLetter {
                var end = next
                while end < text.endIndex, isNameCharacter(text[end]) { end = text.index(after: end) }
                var name = text[next..<end]
                while name.last == "." { name = name.dropLast() }
                let markEnd = name.endIndex
                marks.append(Mark(kind: kind, name: String(name), range: index..<markEnd))
                previous = text[text.index(before: markEnd)]
                index = markEnd
                continue
            }
            previous = character
            index = next
        }
        return marks
    }

    /// The distinct names of one kind of mark, in the order they first appear. Names that differ
    /// only in case count once, keeping the first spelling.
    public static func names(_ kind: Kind, in text: String) -> [String] {
        var seen = Set<String>()
        return marks(in: text)
            .filter { $0.kind == kind }
            .map(\.name)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private static func startsWord(_ character: Character) -> Bool {
        character.isWhitespace || "([{\"'".contains(character)
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "-_.".contains(character)
    }
}
