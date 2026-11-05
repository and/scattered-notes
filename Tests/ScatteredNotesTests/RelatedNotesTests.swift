import XCTest
@testable import ScatteredNotes

final class RelatedNotesTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ title: String, _ content: String = "", tags: [String] = [], project: String? = nil, minutes: Int = 0) -> Note {
        Note(title: title, content: content, categoryType: project == nil ? .inbox : .project, targetName: project,
             updatedAt: base.addingTimeInterval(Double(minutes) * 60), tags: tags)
    }

    /// Some filler notes so a word shared by two of them is rare among all
    private var filler: [Note] {
        (0..<8).map { note("Filler \($0)", "nothing special about number\($0) here at all") }
    }

    func testNotesWithTheSameTagAreRelated() {
        let a = note("Garden", "water the beds", tags: ["home"])
        let b = note("Paint", "buy brushes", tags: ["home"])
        let c = note("Work", "send the invoice", tags: ["office"])
        let result = RelatedIndex(notes: [a, b, c] + filler).related(to: a.id)
        XCTAssertEqual(result.map(\.id), [b.id])
        XCTAssertEqual(result[0].sharedMarks, ["#home"])
    }

    func testNotesMentioningTheSamePersonAreRelated() {
        let a = note("Call", "ask @neil about the deck")
        let b = note("Lunch", "lunch with @Neil on friday")
        let result = RelatedIndex(notes: [a, b] + filler).related(to: a.id)
        XCTAssertEqual(result.map(\.id), [b.id])
        XCTAssertEqual(result[0].sharedMarks, ["@neil"])
    }

    func testNotesUsingTheSameUncommonWordsAreRelated() {
        let a = note("Trip", "booking flights and a hotel in lisbon, lisbon trams, lisbon food")
        let b = note("Packing", "things to take to lisbon: a coat, lisbon is windy")
        let c = note("Taxes", "form for the accountant")
        let result = RelatedIndex(notes: [a, b, c] + filler).related(to: a.id)
        XCTAssertEqual(result.map(\.id), [b.id])
        XCTAssertTrue(result[0].sharedWords.contains("lisbon"))
    }

    func testCommonWordsAndShortWordsDoNotRelateNotes() {
        let a = note("One", "this would have been about that with your things")
        let b = note("Two", "this would have been about that with your stuff")
        XCTAssertTrue(RelatedIndex(notes: [a, b] + filler).related(to: a.id).isEmpty)
    }

    func testNumbersDoNotRelateNotes() {
        let a = note("One", "123456 now")
        let b = note("Two", "123456 later")
        XCTAssertTrue(RelatedIndex(notes: [a, b] + filler).related(to: a.id).isEmpty)
    }

    func testSharingOnlyAProjectIsNotEnough() {
        let a = note("Alpha", "apples", project: "Home")
        let b = note("Bravo", "bicycles", project: "Home")
        XCTAssertTrue(RelatedIndex(notes: [a, b] + filler).related(to: a.id).isEmpty)
    }

    func testTheSameProjectBreaksATie() {
        let me = note("Me", "x", tags: ["t"], project: "Home")
        let near = note("Near", "y", tags: ["t"], project: "Home", minutes: 0)
        let far = note("Far", "z", tags: ["t"], project: "Work", minutes: 5)
        let result = RelatedIndex(notes: [me, near, far] + filler).related(to: me.id)
        XCTAssertEqual(result.map(\.id), [near.id, far.id], "same project wins even though the other note is newer")
    }

    func testMoreSharedMarksRankHigher() {
        let me = note("Me", "", tags: ["a", "b"])
        let one = note("One", "", tags: ["a"])
        let two = note("Two", "", tags: ["a", "b"])
        XCTAssertEqual(RelatedIndex(notes: [me, one, two] + filler).related(to: me.id).map(\.id), [two.id, one.id])
    }

    func testANoteIsNotRelatedToItselfAndExcludedNotesAreLeftOut() {
        let a = note("A", "", tags: ["x"])
        let b = note("B", "", tags: ["x"])
        let index = RelatedIndex(notes: [a, b] + filler)
        XCTAssertFalse(index.related(to: a.id).contains { $0.id == a.id })
        XCTAssertTrue(index.related(to: a.id, excluding: [b.id]).isEmpty)
    }

    func testLimitAndOrderAreStable() {
        let notes = (0..<9).map { note("N\($0)", "", tags: ["same"], minutes: $0) }
        let first = RelatedIndex(notes: notes + filler).related(to: notes[0].id, limit: 3)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.id), [notes[8].id, notes[7].id, notes[6].id], "equal scores: newest first")
        XCTAssertEqual(RelatedIndex(notes: notes + filler).related(to: notes[0].id, limit: 3).map(\.id), first.map(\.id))
    }

    func testUnknownNoteAndNoNotesGiveNothing() {
        XCTAssertTrue(RelatedIndex(notes: []).related(to: UUID()).isEmpty)
        XCTAssertTrue(RelatedIndex(notes: filler).related(to: UUID()).isEmpty)
    }

    func testManyNotesStayFast() {
        let notes = (0..<2000).map { note("Topic \($0)", String(repeating: "alpha beta gamma delta ", count: 40) + "unique\($0 % 50) shared\($0 % 7)", tags: ["t\($0 % 20)"]) }
        measure { _ = RelatedIndex(notes: notes).related(to: notes[0].id) }
    }
}
