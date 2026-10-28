import Foundation

/// Remembers when each checklist or dated line of a note first appeared, so relative words such as
/// "tomorrow" keep the day they were written for, however much the note is edited later. Also
/// remembers when a line was ticked, so the dashboard can count what was done today.
///
/// Stored as `.agenda-log.json` in the notes folder:
/// `{ "notes": { "<note id>": { "<line key>": { "line": "...", "firstSeen": "2026-10-27T06:55:00Z", "doneAt": "..." } } } }`
struct AgendaLog: Codable, Equatable {
    static let fileName = ".agenda-log.json"

    struct Entry: Codable, Equatable {
        var line: String
        var firstSeen: Date
        /// When the line was first seen ticked; nil while it is open
        var doneAt: Date?
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

    /// When each ticked line of a note was ticked, by line key
    func doneDates(for noteID: UUID) -> [String: Date] {
        notes[noteID.uuidString]?.compactMapValues(\.doneAt) ?? [:]
    }

    /// Syncs a note's entries with its current lines. New lines are stamped `seenAt`; existing ones keep
    /// their date; lines no longer present are dropped. A line ticked since the last sync is stamped
    /// done at `seenAt`, and loses the stamp when unticked. Returns whether the log changed.
    mutating func update(noteID: UUID, lines: [(key: String, line: String, isDone: Bool)], seenAt: Date) -> Bool {
        let id = noteID.uuidString
        let before = notes[id]
        var entries = before ?? [:]
        let keys = Set(lines.map(\.key))
        for stale in entries.keys where !keys.contains(stale) {
            entries[stale] = nil
        }
        for (key, line, isDone) in lines {
            var entry = entries[key] ?? Entry(line: line, firstSeen: seenAt)
            if isDone, entry.doneAt == nil {
                entry.doneAt = seenAt
            } else if !isDone {
                entry.doneAt = nil
            }
            entries[key] = entry
        }
        notes[id] = entries.isEmpty ? nil : entries
        return notes[id] != before
    }
}
