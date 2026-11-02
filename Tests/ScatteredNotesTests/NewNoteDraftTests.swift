import XCTest
@testable import ScatteredNotes

/// A note made from the ✎ button or ⌘N starts where the person is looking.
final class NewNoteDraftTests: XCTestCase {
    func testProjectNoteBelongsToTheProject() {
        let d = NewNoteDraft(for: .project(name: "Garden"))
        XCTAssertEqual(d.category, .project)
        XCTAssertEqual(d.targetName, "Garden")
        XCTAssertEqual(d.content, "")
    }

    func testPersonAndTagNotesStartWithTheirMark() {
        XCTAssertEqual(NewNoteDraft(for: .person(name: "ana")).content, "@ana ")
        XCTAssertEqual(NewNoteDraft(for: .tag(name: "ideas")).content, "#ideas ")
        XCTAssertEqual(NewNoteDraft(for: .tag(name: "ideas")).category, .inbox)
    }

    func testEverywhereElseStartsInTheInbox() {
        for selection in [SidebarSelection.all, .inbox, .dashboard] {
            let d = NewNoteDraft(for: selection)
            XCTAssertEqual(d.category, .inbox)
            XCTAssertNil(d.targetName)
            XCTAssertEqual(d.content, "")
        }
    }
}
