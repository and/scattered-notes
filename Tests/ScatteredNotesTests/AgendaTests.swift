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
            createdAt: monday, updatedAt: monday
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

        let note = Note(title: "Mixed", content: "Sunny today\nfix the screen bug\nWill was here", createdAt: monday, updatedAt: monday)
        let items = AgendaExtractor.items(from: note, calendar: calendar)
        XCTAssertEqual(items.map(\.text), ["Sunny today", "fix the screen bug"])
        XCTAssertEqual(items.map(\.isTodo), [false, true])
    }

    func testTickingAPlannedLineMakesItAChecklistItem() {
        let content = Note.togglingChecklistLine(0, in: "fix the screen bug")
        XCTAssertEqual(content, "- [x] fix the screen bug")
        let note = Note(title: "Done", content: content, createdAt: monday, updatedAt: monday)
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
        XCTAssertTrue(saved.contains("Intro\n- [ ] Buy stamps\n- [x] Post letter ✅ "), saved)
        XCTAssertEqual(manager.agendaItems.filter(\.isDone).map(\.text), ["Post letter"])
    }

    func testParsesDaysOfTheMonth() {
        XCTAssertEqual(parse("there is a driving class on 22nd of the next month"), day(11, 22))
        XCTAssertEqual(parse("Rent due 1 of next month"), day(11, 1))
        XCTAssertEqual(parse("Report on the 28th of this month"), day(10, 28))
        XCTAssertEqual(parse("Pay it by the end of the month"), day(10, 31))
        XCTAssertEqual(parse("Plan ready end of next month"), day(11, 30))
        XCTAssertEqual(parse("Class on the 28th"), day(10, 28))
        XCTAssertEqual(parse("Class on the 22nd"), day(11, 22), "already past this month")
        XCTAssertEqual(parse("Class on the 26th"), day(10, 26), "today counts")
        XCTAssertNil(parse("Class on 31st of next month"), "November has no 31st")
        XCTAssertNil(parse("Buy the 3 apples"))
    }

    func testParsesDayAfterAndIntervals() {
        XCTAssertEqual(parse("Party the day after tomorrow"), day(10, 28))
        XCTAssertEqual(parse("Laundry the day after"), day(10, 27))
        XCTAssertEqual(parse("Renew in 3 days"), day(10, 29))
        XCTAssertEqual(parse("Review in 2 weeks"), day(11, 9))

        let note = Note(content: "buy tomatoes today\n\nalso do laundry the day after.", createdAt: monday, updatedAt: monday)
        let items = AgendaExtractor.items(from: note, calendar: calendar)
        XCTAssertEqual(items.map(\.date), [day(10, 26), day(10, 27)])
    }

    func testDashboardHidesOrShowsWhatWasTickedToday() {
        let note = Note(title: "Errands")
        let today = day(10, 26)
        func item(_ line: Int, done: Bool, date: Date?) -> AgendaItem {
            AgendaItem(noteID: note.id, lineIndex: line, text: "item \(line)", isTodo: true, isDone: done,
                       date: date, writtenOn: today, doneOn: nil)
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

    func testMarkersFixAWordsDayAndShowTheTickDay() {
        let note = Note(
            content: "Call bank tomorrow 📅 2026-10-30\n- [x] Pay rent ✅ 2026-10-25\n- [x] Send form friday 📅 2026-11-06 ✅ 2026-10-28",
            createdAt: monday, updatedAt: monday)
        let items = AgendaExtractor.items(from: note, calendar: calendar)

        XCTAssertEqual(items.map(\.text), ["Call bank tomorrow", "Pay rent", "Send form friday"])
        XCTAssertEqual(items.map(\.date), [day(10, 30), nil, day(11, 6)])
        XCTAssertEqual(items.map(\.doneOn), [nil, day(10, 25), day(10, 28)])
    }

    private func resolve(_ content: String, previous: String? = nil, previousUpdatedAt: Date? = nil, now: Date? = nil) -> String {
        AgendaExtractor.resolvingDates(in: content, previous: previous, previousUpdatedAt: previousUpdatedAt,
                                       now: now ?? monday, calendar: calendar)
    }

    func testResolvingWritesTheDayOfRelativeWordsOnly() {
        let content = "Call bank tomorrow\nlunch on 2026-11-02\nbuy milk oct 28\n# Heading today\nplain line"
        let once = resolve(content)
        XCTAssertEqual(once, "Call bank tomorrow 📅 2026-10-27\nlunch on 2026-11-02\nbuy milk oct 28\n# Heading today\nplain line")
        XCTAssertEqual(resolve(once, previous: once, previousUpdatedAt: monday, now: monday.addingTimeInterval(5 * 86_400)), once,
                       "a marked line never moves")
    }

    func testResolvingKeepsTheMarkerWhenTheEditorsCopyLacksIt() {
        let saved = "Call bank tomorrow 📅 2026-10-27"
        let later = monday.addingTimeInterval(4 * 86_400)
        XCTAssertEqual(resolve("Call bank tomorrow", previous: saved, previousUpdatedAt: monday, now: later), saved)
        XCTAssertEqual(resolve("intro\nCall bank tomorrow", previous: saved, previousUpdatedAt: monday, now: later),
                       "intro\n" + saved, "moving a line keeps its day")
        XCTAssertEqual(resolve("Call bank tomorrow 📅 2026-11-02", previous: saved, previousUpdatedAt: monday, now: later),
                       "Call bank tomorrow 📅 2026-11-02", "a marker the user edited wins over the word")
    }

    func testDuplicateLinesKeepTheirOwnDays() {
        let saved = "call bank tomorrow 📅 2026-10-27\ncall bank tomorrow 📅 2026-10-31"
        let later = monday.addingTimeInterval(9 * 86_400)
        XCTAssertEqual(resolve("call bank tomorrow\ncall bank tomorrow", previous: saved, previousUpdatedAt: monday, now: later), saved)
    }

    func testResolvingDatesNewLinesFromNowAndOldUnmarkedLinesFromTheirNote() {
        let edited = monday.addingTimeInterval(3 * 86_400)
        let result = resolve("old plan tomorrow\nnew plan tomorrow", previous: "old plan tomorrow", previousUpdatedAt: monday, now: edited)
        XCTAssertEqual(result, "old plan tomorrow 📅 2026-10-27\nnew plan tomorrow 📅 2026-10-30")
    }

    func testResolvingChainsTheDayAfterFromTheLineAbove() {
        XCTAssertEqual(resolve("buy tomatoes today\nbake the day after"),
                       "buy tomatoes today 📅 2026-10-26\nbake the day after 📅 2026-10-27")
    }

    func testResolvingWritesAndRemovesTheTickDay() {
        let ticked = resolve("- [x] call bank")
        XCTAssertEqual(ticked, "- [x] call bank ✅ 2026-10-26")
        let later = monday.addingTimeInterval(86_400)
        XCTAssertEqual(resolve(ticked, previous: ticked, previousUpdatedAt: monday, now: later), ticked, "tick day is kept")
        XCTAssertEqual(resolve("- [x] call bank", previous: ticked, previousUpdatedAt: monday, now: later), ticked,
                       "the editor's copy without the marker keeps the tick day")
        XCTAssertEqual(resolve("- [ ] call bank ✅ 2026-10-26", previous: ticked, previousUpdatedAt: monday, now: later), "- [ ] call bank")
        XCTAssertEqual(resolve("- [x] send form friday"), "- [x] send form friday 📅 2026-10-30 ✅ 2026-10-26")
    }

    func testMarkersAreInvisibleToTheLineText() {
        XCTAssertEqual(AgendaExtractor.displayText(for: "- [x] call bank tomorrow 📅 2026-10-27 ✅ 2026-10-28"), "call bank tomorrow")
        XCTAssertTrue(AgendaExtractor.isPlannedAction(AgendaExtractor.displayText(for: "call bank 📅 2026-10-27")))
    }

    func testWordCountMatchesSplittingOnWhitespace() {
        for text in ["", "   ", "one", " two  words\n", "tab\tand\nnewline  mix", "naïve café — dash", "a\u{00A0}b"] {
            let expected = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            XCTAssertEqual(NoteDetailEditorView.wordCount(in: text), expected, text)
        }
    }

    @MainActor
    func testSavingWritesDaysIntoTheNotesOwnFile() throws {
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

        let stored = try XCTUnwrap(manager.notes.first)
        let items = manager.agendaItems(for: stored)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].date, firstDay)
        XCTAssertEqual(items[1].date, Calendar.current.date(byAdding: .day, value: 1, to: firstDay))
        let file = try String(contentsOf: XCTUnwrap(stored.filePath), encoding: .utf8)
        XCTAssertTrue(file.contains("Call bank tomorrow 📅 "), "the day belongs in the line")
        XCTAssertFalse(file.contains("seen:"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".agenda-log.json").path))
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
        XCTAssertTrue(saved.contains("- [x] buy tomatoes today 📅 "), saved)
        XCTAssertTrue(saved.contains(" ✅ "), saved)
        let after = manager.agendaItems(for: try XCTUnwrap(manager.notes.first))
        XCTAssertEqual(after.map(\.isDone), [true, false])
        XCTAssertEqual(after.map(\.date), before.map(\.date), "completing must not move the date")
    }

    func testFrontmatterFromOtherAppsSurvivesASave() throws {
        let raw = "---\nid: 7C1F3A52-1111-4B5B-9C8E-1234567890AB\ntitle: \"Trip\"\naliases:\n  - Holiday\n  - \"Trip 2026\"\ncssclasses: wide\ntags:\n  - travel\n  - \"#plans\"\nrating: 4\n---\n\nbody"
        let note = Note.parse(from: raw)
        XCTAssertEqual(note.tags, ["travel", "plans"])
        XCTAssertEqual(note.extraFrontmatter, "aliases:\n  - Holiday\n  - \"Trip 2026\"\ncssclasses: wide\nrating: 4")

        let saved = note.serializeToMarkdown()
        XCTAssertTrue(saved.contains("\naliases:\n  - Holiday\n  - \"Trip 2026\"\ncssclasses: wide\nrating: 4\n---\n\nbody"), saved)
        XCTAssertEqual(saved.components(separatedBy: "\ntags:").count, 2, "tags written twice")
        let again = Note.parse(from: saved)
        XCTAssertEqual(again.extraFrontmatter, note.extraFrontmatter)
        XCTAssertEqual(again.tags, note.tags)
        XCTAssertEqual(again.serializeToMarkdown(), saved)
    }

    @MainActor
    func testCursorStaysInTheSameWordsWhenMarkersAreWritten() {
        let old = "do this tomorrow\nand the day after tomorrow do"
        let new = "do this tomorrow 📅 2026-10-30\nand the day after tomorrow do 📅 2026-10-31"
        let end = (old as NSString).length
        XCTAssertEqual(EditorFocus.mappedOffset(end, from: old, to: new), (new as NSString).length - (" 📅 2026-10-31" as NSString).length,
                       "typing at the end of a line stays before its marker")
        XCTAssertEqual(EditorFocus.mappedOffset(3, from: old, to: new), 3)
        let firstEnd = ("do this tomorrow" as NSString).length
        XCTAssertEqual(EditorFocus.mappedOffset(firstEnd + 1, from: old, to: new), firstEnd + (" 📅 2026-10-30" as NSString).length + 1)
        let marked = "a tomorrow 📅 2026-10-30 b"
        XCTAssertEqual(EditorFocus.mappedOffset(("a tomorrow 📅 2026-10-30" as NSString).length, from: marked, to: marked + "!"),
                       ("a tomorrow 📅 2026-10-30" as NSString).length, "right after a marker stays after it")
        XCTAssertTrue(AgendaExtractor.sameIgnoringMarkers(old, new))
        XCTAssertFalse(AgendaExtractor.sameIgnoringMarkers(old, new + "x"))
    }

    func testMarkersStayOutOfTitlesAndPreviews() {
        let note = Note(content: "do this tomorrow 📅 2026-10-30\n- [x] check linkedin today 📅 2026-10-29 ✅ 2026-10-29")
        XCTAssertEqual(note.displayTitle, "do this tomorrow")
        XCTAssertEqual(note.previewExcerpt, "do this tomorrow - [x] check linkedin today")
    }
}
