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
}
