import XCTest
@testable import ScatteredNotes

final class DateChangeTests: XCTestCase {
    var calendar: Calendar!
    /// Monday 26 Oct 2026
    var monday: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
    }

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func change(_ id: UUID = UUID(), at: Date, note: UUID, text: String = "Buy stamps", to: Date, device: String = "a") -> DateChange {
        DateChange(id: id, at: at, noteID: note, lineText: text, from: nil, to: to, device: device)
    }

    private let plainWrite: (URL, (URL) throws -> Void) throws -> Void = { url, body in try body(url) }

    // MARK: - settingDate

    func testSettingDateAddsAMarkerToAnUndatedLine() {
        let result = AgendaExtractor.settingDate(day(11, 2), onLine: 1, in: "Intro\n- [ ] Buy stamps\nother", calendar: calendar)
        XCTAssertEqual(result, "Intro\n- [ ] Buy stamps 📅 2026-11-02\nother")
    }

    func testSettingDateReplacesTheOldMarkerAndKeepsTheTick() {
        let content = "- [x] Post letter 📅 2026-10-28 ✅ 2026-10-27"
        XCTAssertEqual(
            AgendaExtractor.settingDate(day(11, 5), onLine: 0, in: content, calendar: calendar),
            "- [x] Post letter 📅 2026-11-05 ✅ 2026-10-27"
        )
    }

    func testTheMarkerBeatsDateWordsInTheLine() {
        let content = AgendaExtractor.settingDate(day(11, 6), onLine: 0, in: "call the bank tomorrow", calendar: calendar)
        let note = Note(title: "t", content: content, createdAt: monday, updatedAt: monday)
        XCTAssertEqual(AgendaExtractor.items(from: note, calendar: calendar).first?.date, day(11, 6))
    }

    func testSettingDateOutsideTheNoteChangesNothing() {
        XCTAssertEqual(AgendaExtractor.settingDate(day(11, 2), onLine: 5, in: "one line", calendar: calendar), "one line")
    }

    func testLineKeyIgnoresBulletsCheckboxesAndMarkers() {
        let key = AgendaExtractor.lineKey(onLine: 0, in: "- [ ] Buy stamps 📅 2026-11-02")
        XCTAssertEqual(key, AgendaExtractor.lineKey(onLine: 1, in: "x\nBuy stamps"))
    }

    // MARK: - QuickDates

    func testQuickDatesAreTodayTomorrowAndTheComingMonday() {
        let options = QuickDates.options(today: monday, calendar: calendar)
        XCTAssertEqual(options.map(\.title), ["Today", "Tomorrow", "Next Monday"])
        XCTAssertEqual(options.map(\.day), [day(10, 26), day(10, 27), day(11, 2)])
    }

    // MARK: - The log

    func testAnAppendedChangeIsReadBackFromDisk() throws {
        let directory = tempDirectory()
        let note = UUID()
        let log = DateChangeLog(directory: directory, device: "a")
        try log.append(change(at: monday, note: note, to: day(11, 2)), write: plainWrite)
        try log.append(change(at: monday.addingTimeInterval(60), note: note, to: day(11, 3)), write: plainWrite)

        let reread = DateChangeLog(directory: directory, device: "a")
        XCTAssertEqual(reread.history(noteID: note, lineText: "Buy stamps").map(\.to), [day(11, 2), day(11, 3)])
        XCTAssertTrue(reread.history(noteID: note, lineText: "other line").isEmpty)
    }

    func testALineCutShortByACrashIsSkipped() throws {
        let directory = tempDirectory()
        let note = UUID()
        let log = DateChangeLog(directory: directory, device: "a")
        try log.append(change(at: monday, note: note, to: day(11, 2)), write: plainWrite)
        let file = directory.appendingPathComponent(".date-log-a.jsonl")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"half".utf8))
        try handle.close()

        let reread = DateChangeLog(directory: directory, device: "a")
        XCTAssertEqual(reread.history(noteID: note, lineText: "Buy stamps").count, 1)
    }

    func testTwoDevicesMergeSortedByTimeWithoutRepeats() throws {
        let directory = tempDirectory()
        let note = UUID()
        let shared = UUID()
        let phone = DateChangeLog(directory: directory, device: "phone")
        let mac = DateChangeLog(directory: directory, device: "mac")
        try phone.append(change(at: monday.addingTimeInterval(120), note: note, to: day(11, 4), device: "phone"), write: plainWrite)
        try mac.append(change(at: monday, note: note, to: day(11, 2), device: "mac"), write: plainWrite)
        // The same change copied into both files, as a sync conflict could leave it
        try phone.append(change(shared, at: monday.addingTimeInterval(60), note: note, to: day(11, 3)), write: plainWrite)
        try mac.append(change(shared, at: monday.addingTimeInterval(60), note: note, to: day(11, 3)), write: plainWrite)

        let merged = DateChangeLog(directory: directory, device: "phone")
        XCTAssertEqual(merged.history(noteID: note, lineText: "Buy stamps").map(\.to), [day(11, 2), day(11, 3), day(11, 4)])
    }

    func testLogFilesAreNeverTakenForNotes() {
        XCTAssertTrue(DateChangeLog.isLogFile(".date-log-a1b2.jsonl"))
        XCTAssertFalse(DateChangeLog.isLogFile("2026-10-28_Errands.md"))
    }

    // MARK: - On disk

    @MainActor
    func testSetDateWritesTheNoteAndLogsTheChange() throws {
        let root = tempDirectory()
        let suite = "com.scatterednotes.app.tests.setdate"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let manager = NoteStorageManager(settings: AppSettings(notesDirectoryURL: root, defaults: defaults), enableFileWatcher: false)
        let note = manager.createNote(title: "Errands", content: "Intro\n- [ ] Buy stamps")
        let calendar = Calendar.current
        let first = calendar.date(from: DateComponents(year: 2030, month: 3, day: 4))!
        let second = calendar.date(from: DateComponents(year: 2030, month: 3, day: 9))!

        manager.setDate(noteID: note.id, lineIndex: 1, to: first, calendar: calendar)
        manager.setDate(noteID: note.id, lineIndex: 1, to: second, calendar: calendar)
        manager.setDate(noteID: note.id, lineIndex: 1, to: second, calendar: calendar)

        let saved = try String(contentsOf: XCTUnwrap(manager.notes.first?.filePath), encoding: .utf8)
        XCTAssertTrue(saved.contains("- [ ] Buy stamps 📅 2030-03-09"), saved)
        XCTAssertFalse(saved.contains("2030-03-04"), saved)
        let item = try XCTUnwrap(manager.agendaItems.first { $0.text == "Buy stamps" })
        XCTAssertEqual(item.date, second)

        let history = manager.dateHistory(for: item)
        XCTAssertEqual(history.map(\.from), [nil, first], "setting the same day again logs nothing")
        XCTAssertEqual(history.map(\.to), [first, second])

        // A fresh manager reads the same history from the log file
        let again = NoteStorageManager(settings: AppSettings(notesDirectoryURL: root, defaults: defaults), enableFileWatcher: false)
        let reloaded = try XCTUnwrap(again.agendaItems.first { $0.text == "Buy stamps" })
        XCTAssertEqual(again.dateHistory(for: reloaded).count, 2)
    }

    // MARK: - Dashboard search

    private func item(_ text: String, note: UUID) -> AgendaItem {
        AgendaItem(noteID: note, lineIndex: 0, text: text, isTodo: true, isDone: false, date: nil, writtenOn: monday, doneOn: nil)
    }

    func testSearchNeedsEveryWordAndIgnoresCaseAndAccents() {
        let note = Note(title: "Café plans", content: "", createdAt: monday, updatedAt: monday)
        let items = [item("Buy stamps", note: note.id), item("Call the bank", note: UUID())]
        let lookup = [note.id: note]

        func found(_ query: String) -> [String] {
            DashboardSearch.filter(items, terms: DashboardSearch.terms(query), notes: lookup).map(\.text)
        }
        XCTAssertEqual(found("STAMPS"), ["Buy stamps"])
        XCTAssertEqual(found("buy cafe"), ["Buy stamps"], "the note's title counts, accents folded")
        XCTAssertEqual(found("buy bank"), [])
        XCTAssertEqual(found("  "), ["Buy stamps", "Call the bank"], "an empty query shows everything")
    }
}
