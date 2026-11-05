import Foundation

/// Where the cursor last was: a note and the position in its text (a UTF-16 offset, as in NSRange). The app
/// opens there the next time it starts.
public struct LastPlace: Equatable, Sendable {
    public let noteID: UUID
    public let offset: Int

    public init(noteID: UUID, offset: Int) {
        self.noteID = noteID
        self.offset = offset
    }
}
