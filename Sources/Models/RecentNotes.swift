import Foundation

/// The notes listed under Recent in the sidebar: the ones edited last, minus any taken off the list
public enum RecentNotes {
    public static let limit = 5

    /// The `limit` most recently edited notes, newest first. A note taken off the list stays off until it is
    /// edited again: `hidden` holds the time each was last edited when it was taken off.
    public static func latest(_ notes: [Note], hidden: [UUID: Date], limit: Int = RecentNotes.limit) -> [Note] {
        notes
            .filter { note in hidden[note.id].map { $0 < note.updatedAt } ?? true }
            .sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
            .prefix(limit)
            .map { $0 }
    }
}
