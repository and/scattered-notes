import Foundation

/// Where the cursor was in each note, so a note opens with the cursor where it was left. Positions are UTF-16
/// offsets, as in NSRange. Only the most recently used notes are kept, so the list never grows without limit.
public struct CursorMemory: Equatable, Sendable, Codable {
    public static let limit = 500

    /// Note ids as text, oldest first, and the position of each
    private var order: [String] = []
    private var offsets: [String: Int] = [:]

    public init() {}

    public func offset(for noteID: UUID) -> Int? {
        offsets[noteID.uuidString]
    }

    public var count: Int { order.count }

    public mutating func remember(_ offset: Int, for noteID: UUID) {
        let key = noteID.uuidString
        guard offsets[key] != offset || order.last != key else { return }
        if offsets[key] != nil, let index = order.lastIndex(of: key) { order.remove(at: index) }
        order.append(key)
        offsets[key] = max(0, offset)
        while order.count > Self.limit {
            offsets[order.removeFirst()] = nil
        }
    }

    public mutating func forget(_ noteID: UUID) {
        let key = noteID.uuidString
        offsets[key] = nil
        order.removeAll { $0 == key }
    }
}
