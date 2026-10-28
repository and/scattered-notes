import XCTest

/// Goes through the Notes screens as a person would, on an empty notes folder of the test's own.
final class NoteEditingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.tabBars.buttons["Notes"].tap()
    }

    func testANewNoteStaysOpenWhileNothingIsTyped() {
        app.buttons["New Note"].tap()
        // Longer than the editor waits before saving
        sleep(2)
        XCTAssertTrue(app.textFields["Title"].exists)
        XCTAssertFalse(app.staticTexts["Note not found"].exists)
    }

    func testATypedNoteIsKept() {
        app.buttons["New Note"].tap()
        app.textViews.firstMatch.tap()
        app.textViews.firstMatch.typeText("Buy oat milk")
        sleep(2)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Buy oat milk"].waitForExistence(timeout: 3))
    }

    func testLeavingANewNoteEmptyKeepsNothing() {
        app.buttons["New Note"].tap()
        sleep(2)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 3))
    }

    func testEmptyingANoteRemovesItWhenLeaving() {
        app.buttons["New Note"].tap()
        let text = app.textViews.firstMatch
        text.tap()
        text.typeText("Temporary")
        sleep(2)
        text.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Temporary".count))
        sleep(2)
        XCTAssertTrue(app.textFields["Title"].exists, "the note stays open while it is empty")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 3))
    }

    func testSearchIsVisibleWithoutPullingTheListDown() {
        XCTAssertTrue(app.searchFields["Search all notes"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.searchFields["Search all notes"].isHittable)
    }

    func testSearchFindsATypedNote() {
        app.buttons["New Note"].tap()
        app.textViews.firstMatch.tap()
        app.textViews.firstMatch.typeText("Renew the passport")
        sleep(2)
        app.navigationBars.buttons.firstMatch.tap()
        let search = app.searchFields["Search all notes"]
        search.tap()
        search.typeText("passport")
        XCTAssertTrue(app.staticTexts["Renew the passport"].waitForExistence(timeout: 3))
        search.typeText("zzz")
        XCTAssertFalse(app.staticTexts["Renew the passport"].waitForExistence(timeout: 1))
    }
}
