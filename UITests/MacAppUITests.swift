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

    /// A real mouse drag: button down, many small moves so the drag begins and the target is entered, button up
    private func mouseDrag(from start: CGPoint, to end: CGPoint, steps: Int = 40) {
        func post(_ type: CGEventType, _ point: CGPoint) {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.02)
        }
        post(.mouseMoved, start)
        post(.leftMouseDown, start)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        Thread.sleep(forTimeInterval: 0.4)
        post(.leftMouseUp, end)
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

    // MARK: - Links

    func testTheLinksColumnShowsWhatANoteMentionsAndWhatMentionsIt() throws {
        try writeNote("Budget\nmoney for the trip")
        try writeNote("Trip plan\ncheck the budget first, then book")
        launch()
        openNote(titled: "Trip plan")

        let toggle = app.buttons["linksToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        let panel = app.descendants(matching: .any)["linksPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the Links column opens")
        let budgetRow = panel.buttons.matching(NSPredicate(format: "label CONTAINS 'Budget'")).firstMatch
        XCTAssertTrue(budgetRow.waitForExistence(timeout: 5), "the plan mentions Budget")

        // Clicking the row opens that note, whose column says the plan mentions it
        budgetRow.click()
        let planRow = panel.buttons.matching(NSPredicate(format: "label CONTAINS 'Trip plan'")).firstMatch
        XCTAssertTrue(planRow.waitForExistence(timeout: 5), "Budget lists Trip plan under Linked from")
    }

    // MARK: - Log notes

    func testALogNoteShowsATimeAtTheRightOfEachLineAndKeepsItInTheFile() throws {
        try writeNote("Log - gym\nran 5k ⏱ 2026-11-05 18:02")
        launch()
        openNote(titled: "Log - gym")
        let text = app.textViews["noteText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual((text.value as? String) ?? "", "Log - gym\nran 5k", "the time marker is not shown in the text")

        // A new line typed now gets the time it was written
        text.click()
        text.typeKey(.downArrow, modifierFlags: .command)
        text.typeText("\nbench press")
        XCTAssertTrue(waitUntil {
            self.noteFiles().contains {
                $0.text.range(of: #"(?m)^20\d\d-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d bench press$"#, options: .regularExpression) != nil
                    && $0.text.range(of: #"(?m)^2026-11-05T18:02:00[+-]\d\d:\d\d ran 5k$"#, options: .regularExpression) != nil
            }
        }, "the new line has its time at the start of the line in the file and the old line keeps its own")
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

    /// ⌘N starts the note in the project that is open now, also after moving between projects
    func testCommandNCreatesTheNoteInTheOpenProject() throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Projects/Garden"), withIntermediateDirectories: true)
        try writeNote("Kickoff notes", in: "Projects/Work")
        try writeNote("Seeds to order", in: "Projects/Garden")
        launch()

        func notes(in project: String) -> Int { noteFiles().filter { $0.folder == "Projects/\(project)" }.count }

        sidebarItem("Work").click()
        XCTAssertTrue(text("Work Dashboard").waitForExistence(timeout: 5))
        sidebarItem("Garden").click()
        XCTAssertTrue(text("Garden Dashboard").waitForExistence(timeout: 5))

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(waitUntil { notes(in: "Garden") == 2 }, "⌘N in Garden files the note in Garden")
        XCTAssertEqual(notes(in: "Work"), 1, "and not in the project that was open before")

        sidebarItem("Work").click()
        XCTAssertTrue(text("Work Dashboard").waitForExistence(timeout: 5))
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(waitUntil { notes(in: "Work") == 2 }, "⌘N in Work files the note in Work")
        XCTAssertEqual(notes(in: "Garden"), 2)
    }

    func testTypingStartsAtOnceInANewNote() throws {
        launch()
        sidebarItem("Inbox").click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textViews["noteText"].waitForExistence(timeout: 5))
        app.typeText("Order seeds")
        XCTAssertTrue(waitUntil { self.noteFiles().contains { $0.text.contains("Order seeds") } }, "what is typed goes into the new note without a click")
        XCTAssertTrue(waitUntil { self.noteFiles().contains { $0.text.contains("title: \"Order seeds\"") } }, "the title follows the first line")
    }

    func testPointingAtANoteInTheListDoesNotOpenIt() throws {
        try writeNote("Seeds to order for the garden")
        launch()
        sidebarItem("Inbox").click()
        let row = text("Seeds to order for the garden")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(app.textViews["noteText"].exists, "hovering only marks the row; it does not select it")
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
        XCTAssertEqual(app.windows.firstMatch.title, "Dashboard", "three ups from the project reach the Dashboard")
        XCTAssertFalse(text("Work Dashboard").exists)

        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.app.windows.firstMatch.title == "All Notes" }, "down from the Dashboard reaches All Notes")
    }

    func testTheDashboardHidesTheNoteListAndOpeningANoteBringsItBack() throws {
        try writeNote("- [ ] water the plants\nGarden notes")
        launch()
        let field = app.textFields["Search notes or #tags..."]
        XCTAssertTrue(text("water the plants").waitForExistence(timeout: 5), "the Dashboard is showing")
        XCTAssertFalse(field.exists && field.isHittable, "the note list is hidden on the Dashboard")

        sidebarItem("All Notes").click()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "other places show the note list")
        sidebarItem("Dashboard").click()
        XCTAssertTrue(waitUntil { !(field.exists && field.isHittable) }, "back on the Dashboard the list is hidden again")
    }

    func testRightArrowFromTheInboxSelectsItsFirstNote() throws {
        try writeNote("Seeds to order for the garden")
        launch()
        sidebarItem("Inbox").click()
        XCTAssertTrue(text("Seeds to order for the garden").waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["noteText"].exists, "no note is open yet")

        // The sidebar has the keyboard after a click; wait for the list to settle
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.textViews["noteText"].waitForExistence(timeout: 5), "right selects the first note, as it selects the dashboard row in a project")
    }

    func testArrowKeysWalkTheDashboardItemsAndTheSearchBox() throws {
        try writeNote("- [ ] water the plants\nGarden notes")
        launch()
        sidebarItem("Dashboard").click()
        XCTAssertTrue(text("water the plants").waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        // Right goes to the first item; Return opens its note
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.textViews["noteText"].waitForExistence(timeout: 5), "right then Return opens the first item's note")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(text("water the plants").waitForExistence(timeout: 5), "Escape is back on the Dashboard")
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        // Up from the first item goes to the search box, and down from there to the first item again
        sidebarItem("Dashboard").click()
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeText("plants")
        let search = app.textFields["dashboardSearch"]
        XCTAssertEqual(search.value as? String, "plants", "up from the first item reaches the search box")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.textViews["noteText"].waitForExistence(timeout: 5), "down from the search box reaches the first item")
    }

    func testCompletedItemsAreFoldedAwayUntilAsked() throws {
        try writeNote("- [x] send the form ✅ 2026-10-20\nKickoff notes", in: "Projects/Work")
        launch()
        sidebarItem("Work").click()
        let completed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Completed'")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 5), "an older ticked item has a Completed section")
        XCTAssertFalse(app.buttons["Mark send the form as not done"].exists, "folded away to begin with")

        completed.click()
        XCTAssertTrue(app.buttons["Mark send the form as not done"].waitForExistence(timeout: 5))
    }

    func testCommandOJumpsToAProjectByName() throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Projects/Garden"), withIntermediateDirectories: true)
        try writeNote("Kickoff notes for the project", in: "Projects/Work")
        try writeNote("Seeds to order", in: "Projects/Garden")
        launch()

        // A key pressed the moment the window appears can be lost, so press again like a person would
        let field = app.textFields["goToField"]
        for _ in 0..<3 where !field.exists {
            app.typeKey("o", modifierFlags: .command)
            _ = field.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(field.exists, "⌘O opens the switcher")
        field.typeText("gar")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(text("Garden Dashboard").waitForExistence(timeout: 5), "Return goes to the project")
        XCTAssertFalse(field.exists, "the switcher closes")

        // The keyboard is in that project's notes, so down opens the first one
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.textViews["noteText"].waitForExistence(timeout: 5))
    }

    func testDraggingANoteOntoAProjectMovesItAndUndoBringsItBack() throws {
        // Mouse events do nothing while the screen is locked, so there is nothing to check
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any], session["CGSSessionScreenIsLocked"] as? Bool == true {
            throw XCTSkip("the screen is locked")
        }
        try writeNote("Seeds to order for the garden")
        launch()
        let row = text("Seeds to order for the garden")
        sidebarItem("All Notes").click()
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let start = CGPoint(x: row.frame.minX + 20, y: row.frame.midY)
        let end = CGPoint(x: sidebarItem("Work").frame.minX + 40, y: sidebarItem("Work").frame.midY)
        mouseDrag(from: start, to: end)

        XCTAssertTrue(waitUntil(8) { self.noteFiles().contains { $0.folder == "Projects/Work" && $0.text.contains("Seeds to order") } },
                      "the note is filed in the project it was dropped on; files are in \(noteFiles().map { $0.folder })")
        XCTAssertFalse(noteFiles().contains { $0.folder == "Inbox" })

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitUntil(8) { self.noteFiles().contains { $0.folder == "Inbox" && $0.text.contains("Seeds to order") } },
                      "⌘Z moves it back")
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
