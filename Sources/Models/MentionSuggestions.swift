import Foundation

/// Autocomplete for the marks a note can carry: `+project`, `#tag` and `@person`.
/// Pure logic, so it can be tested; the list on screen is `MentionCompleter`.
public enum MentionSuggestions {
    /// The mark being typed: its kind, what follows the symbol so far, and where it sits in the text (symbol included)
    public struct Token: Equatable, Sendable {
        public let kind: Mentions.Kind
        public let query: String
        public let range: NSRange
    }

    /// The mark the cursor is at the end of, or nil. Follows the rules of `Mentions`: the symbol starts a word,
    /// and the name runs on through letters, digits, `-`, `_` and `.`.
    public static func token(in text: String, caret: Int) -> Token? {
        let ns = text as NSString
        guard caret > 0, caret <= ns.length else { return nil }
        var start = caret
        while start > 0, isNameCharacter(ns.character(at: start - 1)) { start -= 1 }
        guard start > 0, let scalar = Unicode.Scalar(ns.character(at: start - 1)),
              let kind = Mentions.Kind(rawValue: Character(scalar)) else { return nil }
        let symbol = start - 1
        if symbol > 0 {
            guard let before = Unicode.Scalar(ns.character(at: symbol - 1)) else { return nil }
            let c = Character(before)
            guard c.isWhitespace || "([{\"'".contains(c) else { return nil }
        }
        let query = ns.substring(with: NSRange(location: start, length: caret - start))
        return Token(kind: kind, query: query, range: NSRange(location: symbol, length: caret - symbol))
    }

    /// Names to offer for `token`, best first: those starting with what was typed, then those that contain it.
    /// Within each, the ones used in more notes come first. A name equal to what was typed is left out.
    public static func suggestions(for token: Token, notes: [Note], projects: [String], limit: Int = 6) -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        func add(_ name: String, _ weight: Int = 1) {
            let key = fold(name)
            guard !key.isEmpty else { return }
            let seen = counts[key]
            counts[key] = (seen?.name ?? name, (seen?.count ?? 0) + weight)
        }
        switch token.kind {
        case .project:
            // Every project is offered, used or not; the ones with notes come first
            for name in projects { add(name, 0) }
            for note in notes where note.categoryType == .project {
                if let name = note.targetName { add(name) }
            }
        case .tag:
            for note in notes { for tag in Set(note.tags) { add(tag) } }
        case .person:
            for note in notes { for name in note.people { add(name) } }
        }
        let query = fold(token.query)
        let ranked = counts.values
            .filter { fold($0.name) != query }
            .compactMap { item -> (name: String, group: Int, count: Int)? in
                let name = fold(item.name)
                if query.isEmpty || name.hasPrefix(query) { return (item.name, 0, item.count) }
                if name.contains(query) { return (item.name, 1, item.count) }
                return nil
            }
            .sorted { a, b in
                if a.group != b.group { return a.group < b.group }
                if a.count != b.count { return a.count > b.count }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        return ranked.prefix(limit).map(\.name)
    }

    /// What goes into the text for `name`: a project name with spaces is written without them, as `+MyProject`,
    /// which still finds the project. The text ends with a space, so typing carries on.
    public static func insertion(for name: String, kind: Mentions.Kind) -> String {
        let written = kind == .project ? name.replacingOccurrences(of: " ", with: "") : name
        return String(kind.rawValue) + written + " "
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
    }

    private static func isNameCharacter(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        let c = Character(scalar)
        return c.isLetter || c.isNumber || "-_.".contains(c)
    }
}
