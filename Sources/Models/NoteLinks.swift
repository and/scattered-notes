import Foundation

/// A place in a note's text that points at another note: either the other note's title written out, or an
/// explicit `[[Title]]`.
public struct NoteLink: Hashable, Sendable {
    /// The note it points at. Nil for a `[[Title]]` that no note has
    public let target: UUID?
    /// The words that were matched, as written in the text (for `[[Title]]`, the title between the brackets)
    public let text: String
    /// Where it sits in the note's text, brackets included, as a UTF-16 range
    public let range: NSRange
    /// True for `[[Title]]`, false for a title found in the running text
    public let isExplicit: Bool
}

/// Which notes mention which: titles found in the text, explicit `[[Title]]` links, and the backlinks that
/// follow from them. A plain value built from the notes, with no files read and nothing written, so it gives the
/// same answer on every device, and the Windows and Android apps port the same rules.
///
/// Rules:
/// - Titles are compared by whole words, ignoring case and accents and anything between the words that is not a
///   letter or digit. "Plan: Q4" is found in "the plan Q4 review", and "Plan" is not found in "planning".
/// - A title found in the running text must be at least 3 characters long, so a note called "a" does not link
///   everywhere. `[[Title]]` has no such limit.
/// - Where titles overlap, the longest one wins and the text it covers is used up.
/// - A note does not link to itself. Text inside `[[ ]]` is never also counted as a plain mention.
/// - Two notes with the same title both get the link.
///
/// Matching walks the text's words once and follows them through a trie of the titles' words (a tree with one
/// branch per next word), so the cost grows with the length of the text and of the longest title, not with the
/// number of notes, even when many titles start with the same word.
public struct NoteLinkIndex: Sendable {
    /// Titles with more words than this are not looked for in the running text
    private static let longestTitleWords = 12

    /// One step in the table of titles: the titles that end here, and where each next word leads
    private struct Node: Sendable {
        var next: [String: Int] = [:]
        var ids: [UUID] = []
    }

    private let notes: [UUID: Note]
    /// Titles as a trie of words, node 0 being the start: following the text's words through it finds every
    /// title that begins there, however many titles share a first word
    private let trie: [Node]
    /// Titles by their whole text, for `[[Title]]`
    private let byFullTitle: [String: [UUID]]
    private let linksBySource: [UUID: [NoteLink]]
    private let backlinksByTarget: [UUID: [UUID]]

    public init(notes: [Note]) {
        var byID: [UUID: Note] = [:]
        var trie = [Node()]
        var full: [String: [UUID]] = [:]
        for note in notes {
            byID[note.id] = note
            let title = note.displayTitle
            // A note with no title and no text has nothing to be found by
            guard title != "Untitled Note" else { continue }
            let words = Self.words(in: title).map(\.folded)
            guard !words.isEmpty else { continue }
            full[words.joined(separator: " "), default: []].append(note.id)
            let characters = words.reduce(0) { $0 + $1.count }
            if characters >= 3, words.count <= Self.longestTitleWords {
                var at = 0
                for word in words {
                    if let step = trie[at].next[word] {
                        at = step
                    } else {
                        trie.append(Node())
                        trie[at].next[word] = trie.count - 1
                        at = trie.count - 1
                    }
                }
                trie[at].ids.append(note.id)
            }
        }
        self.notes = byID
        self.trie = trie
        self.byFullTitle = full

        var links: [UUID: [NoteLink]] = [:]
        var backlinks: [UUID: Set<UUID>] = [:]
        let draft = NoteLinkIndex(notes: byID, trie: trie, byFullTitle: full)
        for note in notes {
            let found = draft.scan(note.content, from: note.id)
            links[note.id] = found
            for link in found {
                if let target = link.target { backlinks[target, default: []].insert(note.id) }
            }
        }
        self.linksBySource = links
        // Newest note first, the order the note list uses; the id settles ties so the order never changes
        self.backlinksByTarget = backlinks.mapValues { sources in
            sources.sorted {
                let (a, b) = (byID[$0]!, byID[$1]!)
                return a.updatedAt != b.updatedAt ? a.updatedAt > b.updatedAt : $0.uuidString < $1.uuidString
            }
        }
    }

    private init(notes: [UUID: Note], trie: [Node], byFullTitle: [String: [UUID]]) {
        self.notes = notes
        self.trie = trie
        self.byFullTitle = byFullTitle
        self.linksBySource = [:]
        self.backlinksByTarget = [:]
    }

    /// Every link in the note, in the order they appear in its text
    public func links(from noteID: UUID) -> [NoteLink] {
        linksBySource[noteID] ?? []
    }

    /// The notes that link to this one, newest first, each once
    public func backlinks(to noteID: UUID) -> [UUID] {
        backlinksByTarget[noteID] ?? []
    }

    /// The notes this one links to, in the order they first appear, each once
    public func linkedNotes(from noteID: UUID) -> [UUID] {
        var seen = Set<UUID>()
        return links(from: noteID).compactMap { $0.target }.filter { seen.insert($0).inserted }
    }

    // MARK: Scanning

    /// A word of a text: where it is, and the same word with case and accents removed
    private struct Word {
        let range: NSRange
        let folded: String
    }

    private static let explicitLink = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+)\]\]"#)

    /// The words of a text: runs of letters and digits, which is the same rule on every device (the system's own
    /// word splitting varies with the language, and is several times slower)
    /// The folded words of a text, for the related-notes rules, which count words the same way
    static func foldedWords(in text: String) -> [String] {
        words(in: text).map(\.folded)
    }

    private static func words(in text: String) -> [Word] {
        var result: [Word] = []
        var current = ""
        var start = 0
        var offset = 0
        var currentLength = 0
        var ascii = true
        func finish() {
            guard currentLength > 0 else { return }
            let folded = ascii ? current.lowercased() : current.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            result.append(Word(range: NSRange(location: start, length: currentLength), folded: folded))
            current = ""
            currentLength = 0
            ascii = true
        }
        for scalar in text.unicodeScalars {
            let width = scalar.utf16.count
            if wordCharacters.contains(scalar) {
                if currentLength == 0 { start = offset }
                current.unicodeScalars.append(scalar)
                currentLength += width
                if scalar.value >= 0x80 { ascii = false }
            } else {
                finish()
            }
            offset += width
        }
        finish()
        return result
    }

    private static let wordCharacters = CharacterSet.alphanumerics

    private func scan(_ text: String, from source: UUID) -> [NoteLink] {
        let nsText = text as NSString
        var found: [NoteLink] = []

        // `[[Title]]` first: what is inside the brackets is not looked at again as running text
        var covered: [NSRange] = []
        let whole = NSRange(location: 0, length: nsText.length)
        for match in Self.explicitLink.matches(in: text, range: whole) {
            covered.append(match.range)
            let inner = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let key = Self.words(in: inner).map(\.folded).joined(separator: " ")
            let targets = (byFullTitle[key] ?? []).filter { $0 != source }
            if targets.isEmpty {
                // No note has this title, or only the note itself does
                if byFullTitle[key] == nil { found.append(NoteLink(target: nil, text: inner, range: match.range, isExplicit: true)) }
            } else {
                for target in targets {
                    found.append(NoteLink(target: target, text: inner, range: match.range, isExplicit: true))
                }
            }
        }

        // Titles in the running text
        let words = Self.words(in: text).filter { word in
            !covered.contains { NSIntersectionRange($0, word.range).length > 0 }
        }
        var index = 0
        while index < words.count {
            // Walk the text's words through the trie, keeping the longest title that ends along the way
            var at = 0
            var best: (length: Int, ids: [UUID])?
            var length = 0
            while index + length < words.count, let step = trie[at].next[words[index + length].folded] {
                at = step
                length += 1
                if !trie[at].ids.isEmpty { best = (length, trie[at].ids) }
            }
            guard let match = best else {
                index += 1
                continue
            }
            let start = words[index].range.location
            let end = words[index + match.length - 1].range
            let range = NSRange(location: start, length: end.location + end.length - start)
            for id in match.ids where id != source {
                found.append(NoteLink(target: id, text: nsText.substring(with: range), range: range, isExplicit: false))
            }
            index += match.length
        }
        return found.sorted { $0.range.location < $1.range.location }
    }
}
