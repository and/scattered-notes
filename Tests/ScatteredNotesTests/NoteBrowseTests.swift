import XCTest
@testable import ScatteredNotes

final class NoteBrowseTests: XCTestCase {
    private func note(_ content: String, in category: CategoryType = .inbox, target: String? = nil) -> Note {
        var note = Note(title: "t", content: content, categoryType: category, targetName: target)
        note.tags = Note.tags(in: content)
        return note
    }

    func testPlacesListTheirOwnNotes() {
        let inbox = note("call @Neil about #plans")
        let work = note("ship it", in: .project, target: "Work")
        let notes = [inbox, work]
        XCTAssertEqual(NoteBrowse.notes(in: .inbox, of: notes).map(\.id), [inbox.id])
        XCTAssertEqual(NoteBrowse.notes(in: .project("Work"), of: notes).map(\.id), [work.id])
        XCTAssertEqual(NoteBrowse.notes(in: .person("neil"), of: notes).map(\.id), [inbox.id], "names ignore case")
        XCTAssertEqual(NoteBrowse.notes(in: .tag("PLANS"), of: notes).map(\.id), [inbox.id])
        XCTAssertEqual(NoteBrowse.notes(in: .all, of: notes).count, 2)
    }

    func testCountsAreByNoteAndSortedByUse() {
        let notes = [note("@ana @Ana hi"), note("@ana again"), note("@Zed"), note("@bo")]
        let people = NoteBrowse.counted(in: notes) { $0.people }
        XCTAssertEqual(people.map(\.name), ["ana", "bo", "Zed"])
        XCTAssertEqual(people.map(\.count), [2, 1, 1], "a name twice in one note counts the note once")
    }

    func testProjectCount() {
        let notes = [note("a", in: .project, target: "Home"), note("b", in: .project, target: "Home"), note("c")]
        XCTAssertEqual(NoteBrowse.count(project: "Home", in: notes), 2)
        XCTAssertEqual(NoteBrowse.count(project: "Work", in: notes), 0)
    }

    func testANoteStartedHereIsFiledAndMarkedSoItIsListedHere() {
        XCTAssertEqual(NoteBrowse.Place.project("Home").destination.category, .project)
        XCTAssertEqual(NoteBrowse.Place.project("Home").destination.targetName, "Home")
        XCTAssertEqual(NoteBrowse.Place.inbox.destination.category, .inbox)
        XCTAssertEqual(NoteBrowse.Place.person("neil").starterText, "@neil ")
        XCTAssertEqual(NoteBrowse.Place.tag("plans").starterText, "#plans ")
        XCTAssertNil(NoteBrowse.Place.project("Home").starterText)
    }
}
