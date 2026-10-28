import XCTest
@testable import ScatteredNotes

final class AgendaTests: XCTestCase {
    var calendar: Calendar!
    /// Monday 26 Oct 2026
    var monday: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
    }

    private func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func parse(_ line: String) -> Date? {
        AgendaExtractor.parseDate(in: line, reference: calendar.startOfDay(for: monday), calendar: calendar)
    }

    func testParsesSupportedDateFormats() {
        XCTAssertEqual(parse("Send invoice @2026-11-02"), day(11, 2))
        XCTAssertEqual(parse("Call the bank tomorrow"), day(10, 27))
        XCTAssertEqual(parse("Finish draft today"), day(10, 26))
        XCTAssertEqual(parse("Team dinner on Friday"), day(10, 30))
        XCTAssertEqual(parse("Review next friday"), day(11, 6))
        XCTAssertEqual(parse("Gym on monday"), day(10, 26))
        XCTAssertEqual(parse("Next week, plan to buy spare parts"), day(11, 2))
        XCTAssertEqual(parse("Dentist Oct 30th at 4pm"), day(10, 30))
        XCTAssertEqual(parse("Flight on 3 November"), day(11, 3))
        XCTAssertEqual(parse("Taxes due jan 15"), day(1, 15, year: 2027))
    }

    func testIgnoresLinesWithoutDates() {
        XCTAssertNil(parse("Buy milk"))
        XCTAssertNil(parse("Read chapter 30"))
        XCTAssertNil(parse("Sunny weather"))
        XCTAssertNil(parse("Feb 30 is not a day"))
    }

    func testExtractsTodosAndDatedLines() {
        let note = Note(
            title: "Week",
            content: """
            # Plans for tomorrow
            - [ ] Renew passport
            - [x] Pay rent
            Lunch with Sam tomorrow
            Just a thought
            - [ ] Send invoice @2026-11-02
            """,
            createdAt: monday
        )
        let items = AgendaExtractor.items(from: note, calendar: calendar)

        XCTAssertEqual(items.map(\.text), ["Renew passport", "Pay rent", "Lunch with Sam tomorrow", "Send invoice"])
        XCTAssertEqual(items.map(\.lineIndex), [1, 2, 3, 5])
        XCTAssertEqual(items.map(\.isTodo), [true, true, false, true])
        XCTAssertEqual(items.map(\.isDone), [false, true, false, false])
        XCTAssertEqual(items.map(\.date), [nil, nil, day(10, 27), day(11, 2)])
    }

    func testPlainLinesThatReadAsPlansAreTodos() {
        let plans = [
            "fix the right side of the mac screen getting unresponsive.",
            "- Call the bank",
            "Need to renew passport",
            "I have to pay rent",
            "I’ll email Sam the slides",
            "we're going to repaint the hall",
            "Don't forget the charger",
            "TODO: back up photos",
        ]
        for line in plans {
            XCTAssertTrue(AgendaExtractor.isPlannedAction(AgendaExtractor.displayText(for: line)), line)
        }

        let notPlans = ["Just a thought", "Lunch with Sam", "Fixed the login bug", "Should we move?", "Read later:", "Fixes"]
        for line in notPlans {
            XCTAssertFalse(AgendaExtractor.isPlannedAction(line), line)
        }

        let note = Note(title: "Mixed", content: "Sunny today\nfix the screen bug\nWill was here", createdAt: monday)
        let items = AgendaExtractor.items(from: note, calendar: calendar)
        XCTAssertEqual(items.map(\.text), ["Sunny today", "fix the screen bug"])
        XCTAssertEqual(items.map(\.isTodo), [false, true])
    }

    func testTickingAPlannedLineMakesItAChecklistItem() {
        let content = Note.togglingChecklistLine(0, in: "fix the screen bug")
        XCTAssertEqual(content, "- [x] fix the screen bug")
        let note = Note(title: "Done", content: content, createdAt: monday)
        XCTAssertEqual(AgendaExtractor.items(from: note, calendar: calendar).map(\.isDone), [true])
    }

    @MainActor
    func testToggleChecklistItemUpdatesNoteOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let suite = "com.scatterednotes.app.tests.agenda"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let manager = NoteStorageManager(settings: AppSettings(notesDirectoryURL: root, defaults: defaults), enableFileWatcher: false)
        let note = manager.createNote(title: "Errands", content: "Intro\n- [ ] Buy stamps\n- [ ] Post letter")

        manager.toggleChecklistItem(noteID: note.id, lineIndex: 2)

        let saved = try String(contentsOf: XCTUnwrap(manager.notes.first?.filePath), encoding: .utf8)
        XCTAssertTrue(saved.hasSuffix("Intro\n- [ ] Buy stamps\n- [x] Post letter"))
        XCTAssertEqual(manager.agendaItems.filter(\.isDone).map(\.text), ["Post letter"])
    }

    func testParsesDayAfterAndIntervals() {
        XCTAssertEqual(parse("Party the day after tomorrow"), day(10, 28))
        XCTAssertEqual(parse("Laundry the day after"), day(10, 27))
        XCTAssertEqual(parse("Renew in 3 days"), day(10, 29))
        XCTAssertEqual(parse("Review in 2 weeks"), day(11, 9))

        let note = Note(content: "buy tomatoes today\n\nalso do laundry the day after.", createdAt: monday)
        let items = AgendaExtractor.items(from: note, calendar: calendar)
        XCTAssertEqual(items.map(\.date), [day(10, 26), day(10, 27)])
    }

    func testRelativeWordsResolveFromLineAnchorNotCreationDate() {
        let note = Note(content: "Old plan tomorrow\nCall bank tomorrow", createdAt: monday)
        let friday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9))!
        let anchors = [AgendaExtractor.logKey(for: "Call bank tomorrow"): friday]

        let items = AgendaExtractor.items(from: note, anchors: anchors, calendar: calendar)

        XCTAssertEqual(items.map(\.date), [day(10, 27), day(10, 31)])
        XCTAssertEqual(items.map(\.writtenOn), [day(10, 26), day(10, 30)])
    }

    func testAgendaLogKeepsFirstSeenAndDropsRemovedLines() {
        var log = AgendaLog()
        let id = UUID()
        let later = monday.addingTimeInterval(4 * 86_400)

        XCTAssertTrue(log.update(noteID: id, lines: [("a tomorrow", "A tomorrow", false)], seenAt: monday))
        XCTAssertFalse(log.update(noteID: id, lines: [("a tomorrow", "A tomorrow", false)], seenAt: later))
        XCTAssertTrue(log.update(noteID: id, lines: [("a tomorrow", "A tomorrow", false), ("b today", "B today", false)], seenAt: later))
        XCTAssertEqual(log.anchors(for: id), ["a tomorrow": monday, "b today": later])
        XCTAssertTrue(log.update(noteID: id, lines: [("b today", "B today", false)], seenAt: later))
        XCTAssertEqual(Set(log.anchors(for: id).keys), ["b today"])
    }

    func testDashboardHidesOrShowsWhatWasTickedToday() {
        let note = Note(title: "Errands")
        let today = day(10, 26)
        func item(_ line: Int, done: Bool, date: Date?) -> AgendaItem {
            AgendaItem(noteID: note.id, lineIndex: line, text: "item \(line)", isTodo: true, isDone: done,
                       date: date, writtenOn: today)
        }
        let items = [
            item(0, done: true, date: today),        // planned for today, ticked
            item(1, done: true, date: nil),          // to-do ticked today
            item(2, done: true, date: nil),          // to-do ticked on an earlier day
            item(3, done: false, date: nil),
        ]
        let doneToday: Set<String> = [items[0].id, items[1].id]
        func snapshot(showCompleted: Bool) -> DashboardSnapshot {
            DashboardSnapshot(notes: [note], items: items, today: today, upcomingDays: 14, calendar: calendar,
                              doneToday: doneToday, showCompleted: showCompleted)
        }

        let shown = snapshot(showCompleted: true)
        XCTAssertEqual(shown.dueToday.map(\.lineIndex), [0])
        XCTAssertEqual(shown.undatedTodosByNote.first?.items.map(\.lineIndex), [1, 3])
        XCTAssertEqual(shown.completedTodayCount, 2)
        XCTAssertTrue(shown.isTodayDone)

        let hidden = snapshot(showCompleted: false)
        XCTAssertTrue(hidden.dueToday.isEmpty)
        XCTAssertEqual(hidden.undatedTodosByNote.first?.items.map(\.lineIndex), [3])
        XCTAssertEqual(hidden.completedTodayCount, 2)
        XCTAssertTrue(hidden.isTodayDone)
    }

    func testAgendaLogRemembersWhenALineWasTicked() {
        var log = AgendaLog()
        let id = UUID()
        let later = monday.addingTimeInterval(3_600)

        _ = log.update(noteID: id, lines: [("call bank", "- [ ] call bank", false)], seenAt: monday)
        XCTAssertEqual(log.doneDates(for: id), [:])
        XCTAssertTrue(log.update(noteID: id, lines: [("call bank", "- [x] call bank", true)], seenAt: later))
        XCTAssertFalse(log.update(noteID: id, lines: [("call bank", "- [x] call bank", true)], seenAt: later.addingTimeInterval(60)))
        XCTAssertEqual(log.doneDates(for: id), ["call bank": later])
        XCTAssertEqual(log.anchors(for: id), ["call bank": monday])
        XCTAssertTrue(log.update(noteID: id, lines: [("call bank", "- [ ] call bank", false)], seenAt: later))
        XCTAssertEqual(log.doneDates(for: id), [:])
    }

    @MainActor
    func testEditingNoteLaterDoesNotMoveEarlierRelativeLines() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let suite = "com.scatterednotes.app.tests.agendalog"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let manager = NoteStorageManager(settings: AppSettings(notesDirectoryURL: root, defaults: defaults), enableFileWatcher: false)
        var note = manager.createNote(title: "Errands", content: "Buy tomatoes today")
        let firstDay = try XCTUnwrap(manager.agendaItems(for: note).first?.date)

        note.content += "\nCall bank tomorrow"
        manager.save(note: note)

        let items = manager.agendaItems(for: note)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].date, firstDay)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.agendaLogURL.path))
    }

    func testTogglingPlainLineMakesItACheckedItemAndBack() {
        let content = "Intro\n  call bank tomorrow\n* buy milk\n# Heading\n\nlast"
        let first = Note.togglingChecklistLine(1, in: content)
        XCTAssertEqual(first, "Intro\n  - [x] call bank tomorrow\n* buy milk\n# Heading\n\nlast")
        XCTAssertEqual(Note.togglingChecklistLine(1, in: first), "Intro\n  - [ ] call bank tomorrow\n* buy milk\n# Heading\n\nlast")
        XCTAssertEqual(Note.togglingChecklistLine(2, in: content), "Intro\n  call bank tomorrow\n- [x] buy milk\n# Heading\n\nlast")
        XCTAssertEqual(Note.togglingChecklistLine(3, in: content), content, "headings are not completable")
        XCTAssertEqual(Note.togglingChecklistLine(4, in: content), content, "blank lines are not completable")
    }

    @MainActor
    func testCompletingPlainDatedLineFromDashboardKeepsItsDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let suite = "com.scatterednotes.app.tests.complete"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let manager = NoteStorageManager(settings: AppSettings(notesDirectoryURL: root, defaults: defaults), enableFileWatcher: false)
        let note = manager.createNote(title: "Plans", content: "buy tomatoes today\nhiking next week")
        let before = manager.agendaItems(for: note)
        XCTAssertEqual(before.map(\.isDone), [false, false])

        manager.toggleChecklistItem(noteID: note.id, lineIndex: 0)

        let saved = try String(contentsOf: XCTUnwrap(manager.notes.first?.filePath), encoding: .utf8)
        XCTAssertTrue(saved.hasSuffix("- [x] buy tomatoes today\nhiking next week"))
        let after = manager.agendaItems(for: try XCTUnwrap(manager.notes.first))
        XCTAssertEqual(after.map(\.isDone), [true, false])
        XCTAssertEqual(after.map(\.date), before.map(\.date), "completing must not move the date")
    }
}
