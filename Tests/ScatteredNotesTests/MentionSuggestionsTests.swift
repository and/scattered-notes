import XCTest
@testable import ScatteredNotes

final class MentionSuggestionsTests: XCTestCase {
    private func note(_ content: String, tags: [String] = [], project: String? = nil) -> Note {
        Note(title: "", content: content, categoryType: project == nil ? .inbox : .project, targetName: project, tags: tags)
    }

    // MARK: - Finding the mark under the cursor

    func testTokenAtTheEndOfAMark() {
        let token = MentionSuggestions.token(in: "call @ana", caret: 9)
        XCTAssertEqual(token?.kind, .person)
        XCTAssertEqual(token?.query, "ana")
        XCTAssertEqual(token?.range, NSRange(location: 5, length: 4))
    }

    func testBareSymbolIsAToken() {
        XCTAssertEqual(MentionSuggestions.token(in: "x +", caret: 3)?.query, "")
        XCTAssertEqual(MentionSuggestions.token(in: "#", caret: 1)?.kind, .tag)
    }

    func testNoTokenWhenTheSymbolDoesNotStartAWord() {
        XCTAssertNil(MentionSuggestions.token(in: "mail me at user@mail", caret: 20))
        XCTAssertNil(MentionSuggestions.token(in: "C#", caret: 2))
    }

    func testNoTokenWhenTheCursorIsPastTheMark() {
        XCTAssertNil(MentionSuggestions.token(in: "#idea ", caret: 6))
        XCTAssertNil(MentionSuggestions.token(in: "plain words", caret: 5))
        XCTAssertNil(MentionSuggestions.token(in: "", caret: 0))
    }

    func testTokenInTheMiddleOfAMarkUsesTextBeforeTheCursor() {
        let token = MentionSuggestions.token(in: "#ideas later", caret: 4)
        XCTAssertEqual(token?.query, "ide")
        XCTAssertEqual(token?.range, NSRange(location: 0, length: 4))
    }

    func testTokenAfterOpeningBracketAndOnALaterLine() {
        XCTAssertEqual(MentionSuggestions.token(in: "(see #plan", caret: 10)?.query, "plan")
        XCTAssertEqual(MentionSuggestions.token(in: "first\n+dsa", caret: 10)?.query, "dsa")
    }

    // MARK: - Choosing names

    func testTagsStartingWithWhatWasTypedComeFirstThenMostUsed() {
        let notes = [note("a", tags: ["ideas", "plan"]), note("b", tags: ["ideas"]), note("c", tags: ["bigidea", "idle"])]
        let token = MentionSuggestions.Token(kind: .tag, query: "id", range: NSRange(location: 0, length: 3))
        XCTAssertEqual(MentionSuggestions.suggestions(for: token, notes: notes, projects: []), ["ideas", "idle", "bigidea"])
    }

    func testTheNameJustTypedIsNotOffered() {
        let notes = [note("a", tags: ["plan"])]
        let token = MentionSuggestions.Token(kind: .tag, query: "Plan", range: NSRange(location: 0, length: 5))
        XCTAssertEqual(MentionSuggestions.suggestions(for: token, notes: notes, projects: []), [])
    }

    func testPeopleComeFromMentionsInNotes() {
        let notes = [note("ask @Ana about it"), note("@ana and @Bo"), note("no one")]
        let token = MentionSuggestions.Token(kind: .person, query: "", range: NSRange(location: 0, length: 1))
        XCTAssertEqual(MentionSuggestions.suggestions(for: token, notes: notes, projects: []), ["Ana", "Bo"])
    }

    func testProjectsIncludeEmptyOnesAndIgnoreSpacesAndAccents() {
        let notes = [note("x", project: "Café Plans")]
        let token = MentionSuggestions.Token(kind: .project, query: "cafep", range: NSRange(location: 0, length: 6))
        XCTAssertEqual(MentionSuggestions.suggestions(for: token, notes: notes, projects: ["Café Plans", "Dsa"]), ["Café Plans"])
        let all = MentionSuggestions.Token(kind: .project, query: "", range: NSRange(location: 0, length: 1))
        XCTAssertEqual(MentionSuggestions.suggestions(for: all, notes: notes, projects: ["Café Plans", "Dsa"]), ["Café Plans", "Dsa"])
    }

    func testListIsLimited() {
        let tags = (1...20).map { "tag\($0)" }
        let token = MentionSuggestions.Token(kind: .tag, query: "tag", range: NSRange(location: 0, length: 4))
        XCTAssertEqual(MentionSuggestions.suggestions(for: token, notes: [note("x", tags: tags)], projects: [], limit: 6).count, 6)
    }

    // MARK: - Writing the name

    func testInsertionEndsWithASpaceAndDropsSpacesFromProjects() {
        XCTAssertEqual(MentionSuggestions.insertion(for: "My Project", kind: .project), "+MyProject ")
        XCTAssertEqual(MentionSuggestions.insertion(for: "ideas", kind: .tag), "#ideas ")
        XCTAssertEqual(MentionSuggestions.insertion(for: "Ana", kind: .person), "@Ana ")
    }
}
