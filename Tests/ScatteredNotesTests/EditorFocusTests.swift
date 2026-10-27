import XCTest
@testable import ScatteredNotes

@MainActor
final class EditorFocusTests: XCTestCase {
    func testCursorGoesToEndOfTextWithoutSearch() {
        XCTAssertEqual(EditorFocus.cursorOffset(in: "hello world", terms: []), 11)
        XCTAssertEqual(EditorFocus.cursorOffset(in: "", terms: []), 0)
    }

    func testCursorGoesAfterSearchedWord() {
        let text = "buy tomatoes today\nand go hiking"
        XCTAssertEqual(EditorFocus.cursorOffset(in: text, terms: ["tomatoes"]), 12)
        XCTAssertEqual(EditorFocus.cursorOffset(in: text, terms: ["HIKING"]), text.utf16.count)
        XCTAssertEqual(EditorFocus.cursorOffset(in: text, terms: ["go"]), 25)
    }

    func testFirstTermFoundWinsAndMissingTermsAreSkipped() {
        let text = "alpha beta gamma"
        XCTAssertEqual(EditorFocus.cursorOffset(in: text, terms: ["zzz", "beta", "alpha"]), 10)
        XCTAssertEqual(EditorFocus.cursorOffset(in: text, terms: ["zzz"]), text.utf16.count)
    }

    func testIgnoresCaseAndAccentsAndCountsUTF16() {
        XCTAssertEqual(EditorFocus.cursorOffset(in: "Café 🍅 plans", terms: ["CAFE"]), 4)
        XCTAssertEqual(EditorFocus.cursorOffset(in: "🍅 plans", terms: ["plans"]), 8)
    }

    func testTagTermsMatchTheHashtagInText() {
        XCTAssertEqual(EditorFocus.cursorOffset(in: "todo #work later", terms: ["#work"]), 10)
    }
}
