import XCTest
@testable import ScatteredNotes

final class LogNotesTests: XCTestCase {
    private var calendar: Calendar!
    private var morning: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 11, minute: 34))!
    }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: hour, minute: minute))!
    }

    // MARK: What is a log note

    func testANoteIsALogWhenItsFirstLineStartsWithLogAndADash() {
        XCTAssertTrue(LogLines.isLog("Log - Productivity tracker"))
        XCTAssertTrue(LogLines.isLog("log - gym"))
        XCTAssertTrue(LogLines.isLog("LOG – sleep"))
        XCTAssertTrue(LogLines.isLog("Log—moods\nmore"))
        XCTAssertTrue(LogLines.isLog("\n\n  Log - after blank lines"))
    }

    func testOtherNotesAreNotLogs() {
        XCTAssertFalse(LogLines.isLog(""))
        XCTAssertFalse(LogLines.isLog("Logbook"))
        XCTAssertFalse(LogLines.isLog("Log of the day"))
        XCTAssertFalse(LogLines.isLog("Today\nLog - not first"))
        XCTAssertFalse(LogLines.isLog("Catalog - x"))
    }

    func testALogCanBeNamedInTheTitleOrBeStartedInTheText() {
        XCTAssertTrue(LogLines.isLog(title: "Log - Productivity tracker", content: "5th nov 2026 - first entry"))
        XCTAssertTrue(LogLines.isLog(title: "", content: "Log - gym"))
        XCTAssertFalse(LogLines.isLog(title: "Shopping", content: "milk"))
    }

    // MARK: Taking the markers off and putting them back

    func testParseSeparatesTheTimesFromTheText() {
        let content = "Log - gym ⏱ 2026-11-05 11:34\nran 5k ⏱ 2026-11-05 18:02\nno time here"
        let log = LogLines.parse(content, calendar: calendar)
        XCTAssertEqual(log.text, "Log - gym\nran 5k\nno time here")
        XCTAssertEqual(log.stamps, [at(11, 34), at(18, 2), nil])
    }

    func testSerializeIsTheReverseOfParse() {
        let content = "Log - gym\n\n2026-11-05T11:34:00+05:30 ran 5k\nplain"
        let log = LogLines.parse(content, calendar: calendar)
        XCTAssertEqual(LogLines.serialize(text: log.text, stamps: log.stamps, calendar: calendar), content)
    }

    func testOnlyLinesWithATimeGetOneAndALineWithOnlyATimeKeepsIt() {
        let out = LogLines.serialize(text: "a\n\nb", stamps: [morning, nil, morning], calendar: calendar)
        XCTAssertEqual(out, "2026-11-05T11:34:00+05:30 a\n\n2026-11-05T11:34:00+05:30 b")
        let waiting = "2026-11-05T11:34:00+05:30 "
        let log = LogLines.parse(waiting, calendar: calendar)
        XCTAssertEqual(log.text, "")
        XCTAssertEqual(LogLines.serialize(text: log.text, stamps: log.stamps, calendar: calendar), waiting)
    }

    func testTheMarkerIsWrittenAsIsoWithSecondsAndOffset() {
        let out = LogLines.serialize(text: "a", stamps: [at(18, 2).addingTimeInterval(9)], calendar: calendar)
        XCTAssertEqual(out, "2026-11-05T18:02:09+05:30 a")
    }

    func testAnOffsetFixesTheMomentWhateverTheReadersTimeZone() {
        let log = LogLines.parse("2026-11-05T11:34:07Z a\n2026-11-05T11:34:07-08:00 b", calendar: calendar)
        XCTAssertEqual(log.stamps, [Date(timeIntervalSince1970: 1_793_878_447), Date(timeIntervalSince1970: 1_793_907_247)])
    }

    func testOlderMarkersWithoutSecondsOrOffsetAreStillRead() {
        let log = LogLines.parse("a ⏱ 2026-11-05 11:34", calendar: calendar)
        XCTAssertEqual(log.text, "a")
        XCTAssertEqual(log.stamps, [at(11, 34)])
    }

    func testTheLogHeadingGetsNoTimeButLaterLinesThatLookLikeItDo() {
        let out = LogLines.serialize(text: "Log - gym\nLog - restarted", stamps: [morning, morning], calendar: calendar)
        XCTAssertEqual(out, "Log - gym\n2026-11-05T11:34:00+05:30 Log - restarted")
    }

    func testAStampedFirstLineIsStillALogHeading() {
        XCTAssertTrue(LogLines.isLog("2026-11-05T11:34:07+05:30 Log - gym"))
    }

    func testTheSymbolWithAVariationSelectorIsRead() {
        let log = LogLines.parse("a \u{23F1}\u{FE0F} 2026-11-05 11:34", calendar: calendar)
        XCTAssertEqual(log.text, "a")
        XCTAssertEqual(log.stamps, [at(11, 34)])
    }

    func testAMarkerInTheMiddleOfALineIsLeftAlone() {
        let log = LogLines.parse("note about ⏱ 2026-11-05 11:34 and more", calendar: calendar)
        XCTAssertEqual(log.text, "note about ⏱ 2026-11-05 11:34 and more")
        XCTAssertEqual(log.stamps, [nil])
    }

    func testTheTimeAtTheStartOfALineIsQuietAndItsTAndOffsetAreFaint() {
        let text = "Log - gym\n2026-11-05T14:22:19+05:30 one sun\nplain 2026-11-05T14:22:19+05:30"
        let styling = LogLines.stampStyling(in: text)
        let ns = text as NSString
        XCTAssertEqual(styling.quiet.map { ns.substring(with: $0) }, ["2026-11-05T14:22:19+05:30"])
        XCTAssertEqual(styling.faint.map { ns.substring(with: $0) }, ["T", "+05:30"])
    }

    // MARK: The rest of the app ignores the markers

    func testAgendaItemsOfALogNoteAreNotMistakenForDatedLines() {
        let note = Note(content: "Log - gym ⏱ 2026-11-05 11:34\nran 5k ⏱ 2026-11-05 18:02\nbuy shoes ⏱ 2026-11-05 18:05")
        let items = AgendaExtractor.items(from: note, calendar: calendar)
        XCTAssertEqual(items.map(\.text), ["buy shoes"], "only the plan counts, and the time marker is not a date in it")
        XCTAssertNil(items.first?.date)
    }

    func testTheTitleAndPreviewOfALogNoteLeaveOutTheTimes() {
        let note = Note(content: "Log - gym ⏱ 2026-11-05 11:34\nran 5k ⏱ 2026-11-05 18:02")
        XCTAssertEqual(note.displayTitle, "Log - gym")
        XCTAssertFalse(note.previewExcerpt.contains("⏱"))
    }

    func testSettingADateOnALogLineKeepsItsTime() {
        let content = "Log - gym\n2026-11-05T18:05:00+05:30 buy shoes"
        let changed = AgendaExtractor.settingDate(at(0, 0), onLine: 1, in: content, calendar: calendar)
        XCTAssertEqual(changed, "Log - gym\n2026-11-05T18:05:00+05:30 buy shoes 📅 2026-11-05")
    }

    func testResolvingDatesOnALogNoteKeepsTheTimes() {
        let content = "Log - plans\n2026-11-05T11:40:00+05:30 call the bank tomorrow"
        let resolved = AgendaExtractor.resolvingDates(in: content, previous: nil, previousUpdatedAt: nil, now: morning, calendar: calendar)
        XCTAssertEqual(resolved, "Log - plans\n2026-11-05T11:40:00+05:30 call the bank tomorrow 📅 2026-11-06")
    }
}
