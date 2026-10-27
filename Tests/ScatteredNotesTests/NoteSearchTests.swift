import XCTest
@testable import ScatteredNotes

final class NoteSearchTests: XCTestCase {
    private func note(_ title: String, _ content: String, tags: [String] = [], category: CategoryType = .inbox, target: String? = nil, updated: TimeInterval = 0) -> Note {
        Note(title: title, content: content, categoryType: category, targetName: target,
             updatedAt: Date(timeIntervalSince1970: updated), tags: tags)
    }

    func testAllTermsMustMatchAnywhereInNote() {
        let notes = [note("Groceries", "buy tomatoes and basil"), note("Garage", "tomatoes are not here")]
        XCTAssertEqual(NoteSearch.search("tomatoes basil", in: notes).map(\.note.title), ["Groceries"])
        XCTAssertTrue(NoteSearch.search("tomatoes zebra", in: notes).isEmpty)
    }

    func testIgnoresCaseAndAccents() {
        let notes = [note("Café plans", "Meet at the CAFÉ")]
        XCTAssertEqual(NoteSearch.search("cafe", in: notes).count, 1)
        XCTAssertEqual(NoteSearch.search("MEET", in: notes).count, 1)
    }

    func testTitleMatchesRankAboveBodyMatches() {
        let notes = [note("Misc", "motor bike parts", updated: 100), note("Motor bike", "service due", updated: 1)]
        XCTAssertEqual(NoteSearch.search("motor", in: notes).map(\.note.title), ["Motor bike", "Misc"])
    }

    func testHashTermsMatchTagsOnly() {
        let notes = [note("Tagged", "nothing", tags: ["work"]), note("Mentions", "talk about work")]
        XCTAssertEqual(NoteSearch.search("#work", in: notes).map(\.note.title), ["Tagged"])
    }

    func testProjectNameIsSearchable() {
        let notes = [note("Plan", "outline", category: .project, target: "Sandtimer")]
        XCTAssertEqual(NoteSearch.search("sandtimer", in: notes).count, 1)
    }

    func testBlankQueryReturnsNothing() {
        XCTAssertTrue(NoteSearch.search("   ", in: [note("a", "b")]).isEmpty)
        XCTAssertTrue(NoteSearch.search("#", in: [note("a", "b")]).isEmpty)
    }

    func testSnippetStaysOnMatchLineAndIsTrimmed() throws {
        let long = String(repeating: "x", count: 200)
        let result = try XCTUnwrap(NoteSearch.search("needle", in: [note("t", "first line\n\(long) needle \(long)\nlast")]).first)
        let snippet = try XCTUnwrap(result.snippet)
        XCTAssertTrue(snippet.contains("needle"))
        XCTAssertTrue(snippet.hasPrefix("…") && snippet.hasSuffix("…"))
        XCTAssertFalse(snippet.contains("first line") || snippet.contains("last"))
        XCTAssertLessThan(snippet.count, 110)
    }

    func testTitleOnlyMatchHasNoSnippet() throws {
        let result = try XCTUnwrap(NoteSearch.search("groceries", in: [note("Groceries", "milk")]).first)
        XCTAssertNil(result.snippet)
    }
}
