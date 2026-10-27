import Foundation

/// Remembers when each checklist or dated line of a note first appeared, so relative words such as
/// "tomorrow" keep the day they were written for, however much the note is edited later.
///
/// Stored as `.agenda-log.json` in the notes folder:
/// `{ "notes": { "<note id>": { "<line key>": { "line": "...", "firstSeen": "2026-10-27T06:55:00Z" } } } }`
struct AgendaLog: Codable, Equatable {
    static let fileName = ".agenda-log.json"

    struct Entry: Codable, Equatable {
        var line: String
        var firstSeen: Date
    }

    var notes: [String: [String: Entry]] = [:]

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func anchors(for noteID: UUID) -> [String: Date] {
        notes[noteID.uuidString]?.mapValues(\.firstSeen) ?? [:]
    }

    /// Syncs a note's entries with its current lines. New lines are stamped `seenAt`; existing ones keep
    /// their date; lines no longer present are dropped. Returns whether the log changed.
    mutating func update(noteID: UUID, lines: [(key: String, line: String)], seenAt: Date) -> Bool {
        let id = noteID.uuidString
        let before = notes[id]
        var entries = before ?? [:]
        let keys = Set(lines.map(\.key))
        for stale in entries.keys where !keys.contains(stale) {
            entries[stale] = nil
        }
        for (key, line) in lines where entries[key] == nil {
            entries[key] = Entry(line: line, firstSeen: seenAt)
        }
        notes[id] = entries.isEmpty ? nil : entries
        return notes[id] != before
    }
}
