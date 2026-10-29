import XCTest

/// Uses the Mac app as a person would, on a notes folder of the test's own: the app is started
/// with `-uiTesting`, so it never sees real notes, iCloud or update checks.
final class MacAppUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("sn-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Inbox"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Projects/Work"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: folder)
    }

    private func launch(_ arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launchEnvironment["SN_UITEST_NOTES"] = folder.path
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    /// Writes a note file the way the app does, so the app finds it when it starts
    @discardableResult
    private func writeNote(_ text: String, in subfolder: String = "Inbox", id: UUID = UUID()) throws -> URL {
        let url = folder.appendingPathComponent(subfolder).appendingPathComponent("2026-10-28_\(id.uuidString.prefix(8)).md")
        let markdown = """
        ---
        id: \(id.uuidString)
        title: ""
        type: inbox
        created_at: 2026-10-28T09:00:00Z
        updated_at: 2026-10-28T09:00:00Z
        ---

        \(text)
        """
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The text of every note file in the folder, by the folder it is in, e.g. "Projects/Work"
    private func noteFiles() -> [(folder: String, text: String)] {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        return files.filter { $0.pathExtension == "md" }.map { url in
            let parent = url.deletingLastPathComponent().path.replacingOccurrences(of: folder.path + "/", with: "")
            return (parent, (try? String(contentsOf: url, encoding: .utf8)) ?? "")
        }
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    /// Text on screen; SwiftUI shows it as the value of a static text, not its label
    private func text(_ string: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", string, string)).firstMatch
    }

    /// A row in the sidebar, such as "All Notes", a project, a person or a tag
    private func sidebarItem(_ name: String) -> XCUIElement {
        app.outlines["Sidebar"].buttons[name].firstMatch
    }

    private func quickNoteStatus() -> String {
        let status = app.descendants(matching: .any)["quickNoteStatus"].firstMatch
        guard status.exists else { return "" }
        return [status.label, status.value as? String ?? ""].joined(separator: " ")
    }

    private func openNote(titled title: String) {
        sidebarItem("All Notes").click()
        let row = text(title)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(app.textViews["noteText"].waitForExistence(timeout: 5))
    }

    // MARK: - Quick Note

    func testQuickNoteSavesAsYouTypeAndFilesItOnEscape() throws {
        launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Quick Capture'")).firstMatch.click()
        let text = app.textViews["quickNoteText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.typeText("Plant tulips +garden #spring @ana")

        // Saved to the Inbox while typing, before the panel closes
        XCTAssertTrue(waitUntil { self.quickNoteStatus().contains("Saved to Inbox") }, "status: \(quickNoteStatus())")
        XCTAssertTrue(noteFiles().contains { $0.folder == "Inbox" && $0.text.contains("Plant tulips") })
        XCTAssertFalse(app.buttons["Save Note"].exists, "auto-save hides the Save button")

        text.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.noteFiles().contains { $0.folder == "Projects/Garden" } }, "the note is filed under +garden")
        let filed = try XCTUnwrap(noteFiles().first { $0.folder == "Projects/Garden" })
        XCTAssertFalse(filed.text.contains("+garden"))
        XCTAssertTrue(filed.text.contains("#spring @ana"))
        XCTAssertEqual(noteFiles().count, 1, "no copy is left in the Inbox")

        XCTAssertTrue(sidebarItem("Garden").waitForExistence(timeout: 5))
        XCTAssertTrue(sidebarItem("spring").exists)
        XCTAssertTrue(sidebarItem("ana").exists)
    }

    func testQuickNoteLeavesNothingWhenEverythingTypedIsDeleted() throws {
        launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Quick Capture'")).firstMatch.click()
        let text = app.textViews["quickNoteText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.typeText("never mind")
        XCTAssertTrue(waitUntil { self.quickNoteStatus().contains("Saved to Inbox") })
        text.typeKey("a", modifierFlags: .command)
        text.typeKey(.delete, modifierFlags: [])
        text.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.noteFiles().isEmpty })
    }

    func testQuickNoteWithManualSavingShowsASaveButtonAndDiscardsOnEscape() throws {
        launch(["-manualQuickNote"])
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Quick Capture'")).firstMatch.click()
        let text = app.textViews["quickNoteText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save Note"].exists)
        text.typeText("thrown away")
        sleep(2)
        XCTAssertTrue(noteFiles().isEmpty, "nothing is saved before Save is pressed")
        text.typeKey(.escape, modifierFlags: [])
        sleep(1)
        XCTAssertTrue(noteFiles().isEmpty)
    }

    // MARK: - Editor

    func testMovingANoteFromTheEditorKeepsWhatWasTyped() throws {
        try writeNote("Quarterly plan")
        launch()
        openNote(titled: "Quarterly plan")
        let text = app.textViews["noteText"]
        text.click()
        text.typeKey(.downArrow, modifierFlags: .command)
        text.typeText("\nhire two people")
        XCTAssertTrue(waitUntil { self.noteFiles().first?.text.contains("hire two people") == true })

        app.descendants(matching: .any)["noteDestination"].firstMatch.click()
        app.menuItems["Work"].click()
        XCTAssertTrue(waitUntil { self.noteFiles().first?.folder == "Projects/Work" })
        XCTAssertTrue(noteFiles().first?.text.contains("hire two people") == true, "typing survives the move")

        // Typing after the move keeps the note where it was moved to
        text.click()
        text.typeKey(.downArrow, modifierFlags: .command)
        text.typeText("\nbook a room")
        XCTAssertTrue(waitUntil { self.noteFiles().first?.text.contains("book a room") == true })
        XCTAssertEqual(noteFiles().map(\.folder), ["Projects/Work"])
    }

    func testAnOpenNoteShowsAVersionSavedElsewhere() throws {
        let id = UUID()
        let file = try writeNote("Shopping list", id: id)
        launch()
        openNote(titled: "Shopping list")
        let text = app.textViews["noteText"]

        // Another device saves the note while it is open here
        sleep(1)
        let newer = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: "Shopping list", with: "Shopping list\nadded on the iPhone")
        try newer.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(waitUntil { (text.value as? String)?.contains("added on the iPhone") == true }, "the editor shows the newer version")

        // Typing now adds to that version instead of putting the old one back
        text.click()
        text.typeKey(.downArrow, modifierFlags: .command)
        text.typeText("\nand on the Mac")
        XCTAssertTrue(waitUntil {
            let saved = self.noteFiles().first?.text ?? ""
            return saved.contains("added on the iPhone") && saved.contains("and on the Mac")
        })
    }

    // MARK: - Dashboard

    func testProjectDashboardListsItsNotesAndChipsScroll() throws {
        try writeNote("- [ ] send the report today\nKickoff notes", in: "Projects/Work")
        launch()
        sidebarItem("Work").click()
        XCTAssertTrue(text("Notes").waitForExistence(timeout: 5), "the notes log is on the project dashboard")
        XCTAssertTrue(text("send the report today").exists)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'today'")).firstMatch.click()
    }

    func testArrowKeysWalkBetweenTheProjectListAndItsNotes() throws {
        try writeNote("Kickoff notes for the project", in: "Projects/Work")
        launch()
        openNote(titled: "Kickoff notes for the project")

        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(sidebarItem("Work").waitForExistence(timeout: 5))
        XCTAssertTrue(text("Work Dashboard").waitForExistence(timeout: 5), "left from a note opens the note's project")
        XCTAssertTrue(text("Notes").waitForExistence(timeout: 5))

        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.textViews["noteText"].waitForExistence(timeout: 5), "right then down opens the project's first note")
    }

    func testArrowKeysKeepWorkingInTheProjectListAfterTheDashboard() throws {
        try writeNote("Kickoff notes for the project", in: "Projects/Work")
        launch()
        openNote(titled: "Kickoff notes for the project")
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(text("Work Dashboard").waitForExistence(timeout: 5))

        // Work, Inbox, All Notes, Dashboard
        for _ in 0..<3 {
            app.typeKey(.upArrow, modifierFlags: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTAssertFalse(app.textFields["Search notes or #tags..."].exists, "the Dashboard has no note list")

        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.textFields["Search notes or #tags..."].waitForExistence(timeout: 5), "down from the Dashboard reaches All Notes")
    }

    func testTickingTodaysLastTaskShowsTheSunAndCompletedCanBeHidden() throws {
        try writeNote("- [ ] water the plants today\n- [ ] call mum")
        launch()
        sidebarItem("Dashboard").click()
        let tick = app.buttons["Mark water the plants today as done"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        tick.click()

        XCTAssertTrue(waitUntil { self.noteFiles().first?.text.contains("- [x] water the plants today") == true })
        XCTAssertTrue(text("All done for today: 1 completed").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["All done, today"].exists, "the today count turns into a sun")
        XCTAssertTrue(app.buttons["Mark water the plants today as not done"].exists, "a ticked task stays, struck through")

        app.buttons["Hide Completed"].click()
        XCTAssertTrue(waitUntil { !self.app.buttons["Mark water the plants today as not done"].exists })
        XCTAssertTrue(text("All done for today.").exists)
        app.buttons["Show Completed"].click()
        XCTAssertTrue(app.buttons["Mark water the plants today as not done"].waitForExistence(timeout: 5))
    }
}
