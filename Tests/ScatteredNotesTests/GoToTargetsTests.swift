import XCTest
@testable import ScatteredNotes

final class GoToTargetsTests: XCTestCase {
    private let projects = [
        ProjectArea(name: "Sandtimer", type: .project),
        ProjectArea(name: "Sn", type: .project),
        ProjectArea(name: "Scattered Notes", type: .project),
        ProjectArea(name: "Café", type: .project),
    ]
    private var notes: [Note] {
        [
            Note(title: "a", content: "ask @ana about it #plans", categoryType: .project, targetName: "Sn", tags: ["plans"]),
            Note(title: "b", content: "call @Ana #Plans #ideas", categoryType: .project, targetName: "Sn", tags: ["Plans", "ideas"]),
            Note(title: "c", content: "hello", categoryType: .inbox),
        ]
    }

    private func titles(_ query: String) -> [String] {
        GoToTargets.matching(query, in: GoToTargets.all(projects: projects, notes: notes)).map(\.title)
    }

    func testListsEveryPlaceInTheSidebarsOrderWithCounts() {
        let all = GoToTargets.all(projects: projects, notes: notes)
        XCTAssertEqual(all.map(\.title), ["Dashboard", "All Notes", "Inbox", "Sandtimer", "Sn", "Scattered Notes", "Café", "ana", "ideas", "plans"])
        XCTAssertEqual(all.first { $0.title == "Sn" }?.count, 2)
        XCTAssertEqual(all.first { $0.title == "Inbox" }?.count, 1)
        XCTAssertEqual(all.first { $0.title == "ana" }?.count, 2, "names that differ only in case count once")
        XCTAssertNil(all.first?.count)
    }

    func testNothingTypedOffersEverything() {
        XCTAssertEqual(titles("").count, 10)
        XCTAssertEqual(titles("   ").count, 10)
    }

    func testPrefixMatchesComeBeforeWordAndInnerMatches() {
        XCTAssertEqual(titles("sn"), ["Sn"], "only Sn contains it")
        XCTAssertEqual(titles("s").first, "Sandtimer", "the sidebar's order breaks ties")
        XCTAssertEqual(titles("notes"), ["All Notes", "Scattered Notes"], "both have a word that starts with it; the sidebar's order breaks the tie")
    }

    func testIgnoresCaseAndAccents() {
        XCTAssertEqual(titles("CAFE"), ["Café"])
        XCTAssertEqual(titles("café"), ["Café"])
    }

    func testHashLooksAtTagsAndAtLooksAtPeople() {
        XCTAssertEqual(titles("#pl"), ["plans"])
        XCTAssertEqual(titles("#"), ["ideas", "plans"])
        XCTAssertEqual(titles("@an"), ["ana"])
        XCTAssertEqual(titles("@"), ["ana"])
        XCTAssertEqual(titles("pl"), ["plans"], "without a mark, everything is searched")
    }

    func testNoMatchGivesNothing() {
        XCTAssertEqual(titles("zzz"), [])
    }
}
