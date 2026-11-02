import XCTest
@testable import ScatteredNotes

final class NoteDragTests: XCTestCase {
    func testAPayloadFindsItsNoteAndOtherTextIsIgnored() {
        let note = Note(title: "a", content: "b")
        XCTAssertEqual(NoteDrag.noteID(from: NoteDrag.payload(for: note)), note.id)
        XCTAssertNil(NoteDrag.noteID(from: note.id.uuidString), "a bare ID from somewhere else is not a note drag")
        XCTAssertNil(NoteDrag.noteID(from: "scatterednotes-note:nonsense"))
        XCTAssertNil(NoteDrag.noteID(from: "some dragged text"))
    }

    func testOnlyProjectsAndTheInboxTakeDrops() {
        XCTAssertEqual(NoteDrag.destination(for: .inbox)?.category, .inbox)
        XCTAssertNil(NoteDrag.destination(for: .inbox)?.targetName)
        XCTAssertEqual(NoteDrag.destination(for: .project(name: "Sn"))?.category, .project)
        XCTAssertEqual(NoteDrag.destination(for: .project(name: "Sn"))?.targetName, "Sn")
        for selection in [SidebarSelection.dashboard, .all, .person(name: "ana"), .tag(name: "plans")] {
            XCTAssertNil(NoteDrag.destination(for: selection), "\(selection)")
        }
    }
}
