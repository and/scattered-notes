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
        let content = "Log - gym ⏱ 2026-11-05 11:34\n\nran 5k ⏱ 2026-11-05 18:02\nplain"
        let log = LogLines.parse(content, calendar: calendar)
        XCTAssertEqual(LogLines.serialize(text: log.text, stamps: log.stamps, calendar: calendar), content)
    }

    func testBlankLinesGetNoMarkerAndTrailingSpacesAreTrimmedBeforeOne() {
        let out = LogLines.serialize(text: "a  \n\n   \nb", stamps: [morning, morning, morning, nil], calendar: calendar)
        XCTAssertEqual(out, "a ⏱ 2026-11-05 11:34\n\n   \nb")
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

    // MARK: Keeping the times in step with typing

    private func edit(_ stamps: inout [Date?], _ text: String, _ location: Int, _ length: Int = 0, _ replacement: String, now: Date? = nil) {
        LogLines.edit(stamps: &stamps, in: text, replacing: NSRange(location: location, length: length), with: replacement, now: now ?? morning)
    }

    func testTypingInALineNeverChangesItsTime() {
        var stamps: [Date?] = [at(9, 0), at(10, 0)]
        edit(&stamps, "first\nsecond", 3, 0, "XYZ")
        XCTAssertEqual(stamps, [at(9, 0), at(10, 0)])
    }

    func testTheFirstTextInALineGivesItTheTime() {
        var stamps: [Date?] = [at(9, 0), nil]
        edit(&stamps, "first\n", 6, 0, "n", now: at(12, 30))
        XCTAssertEqual(stamps, [at(9, 0), at(12, 30)])
    }

    func testPressingReturnAtTheEndOfALineMakesANewLineWithoutATimeUntilItHasText() {
        var stamps: [Date?] = [at(9, 0)]
        edit(&stamps, "first", 5, 0, "\n")
        XCTAssertEqual(stamps, [at(9, 0), nil])
        edit(&stamps, "first\n", 6, 0, "x", now: at(9, 5))
        XCTAssertEqual(stamps, [at(9, 0), at(9, 5)])
    }

    func testPressingReturnAtTheStartOfALinePushesItDownWithItsTime() {
        var stamps: [Date?] = [at(9, 0), at(10, 0)]
        edit(&stamps, "first\nsecond", 6, 0, "\n")
        XCTAssertEqual(stamps, [at(9, 0), nil, at(10, 0)])
    }

    func testSplittingALineKeepsTheTimeOnTheFirstPart() {
        var stamps: [Date?] = [at(9, 0)]
        edit(&stamps, "abcdef", 3, 0, "\n", now: at(9, 30))
        XCTAssertEqual(stamps, [at(9, 0), at(9, 30)])
    }

    func testJoiningTwoLinesKeepsTheFirstTime() {
        var stamps: [Date?] = [at(9, 0), at(10, 0), at(11, 0)]
        edit(&stamps, "one\ntwo\nthree", 3, 1, "")
        XCTAssertEqual(stamps, [at(9, 0), at(11, 0)])
    }

    func testPastingSeveralLinesGivesEachTheTime() {
        var stamps: [Date?] = [at(9, 0)]
        edit(&stamps, "one", 3, 0, "\ntwo\nthree", now: at(14, 0))
        XCTAssertEqual(stamps, [at(9, 0), at(14, 0), at(14, 0)])
    }

    func testDeletingAWholeLineRemovesItsTimeAndAnEmptiedLineLosesItsTime() {
        var stamps: [Date?] = [at(9, 0), at(10, 0), at(11, 0)]
        edit(&stamps, "one\ntwo\nthree", 4, 4, "")
        XCTAssertEqual(stamps, [at(9, 0), at(11, 0)])

        var emptied: [Date?] = [at(9, 0)]
        edit(&emptied, "one", 0, 3, "")
        XCTAssertEqual(emptied, [nil], "a line with no text has no time; typing again starts a new one")
    }

    func testOldLinesWithoutATimeStayWithoutOneUntilTheyAreEdited() {
        var stamps: [Date?] = [nil, nil, nil]
        edit(&stamps, "a\nb\nc", 3, 0, "x", now: at(15, 0))
        XCTAssertEqual(stamps, [nil, at(15, 0), nil])
    }

    func testTheTimesAreFittedWhenTheirCountIsWrong() {
        var stamps: [Date?] = [at(9, 0)]
        edit(&stamps, "a\nb\nc", 0, 0, "x", now: at(15, 0))
        XCTAssertEqual(stamps.count, 3)
        var tooMany: [Date?] = [nil, nil, nil, nil, nil]
        edit(&tooMany, "a", 1, 0, "b", now: at(15, 0))
        XCTAssertEqual(tooMany.count, 1)
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
        let content = "Log - gym ⏱ 2026-11-05 11:34\nbuy shoes ⏱ 2026-11-05 18:05"
        let changed = AgendaExtractor.settingDate(at(0, 0), onLine: 1, in: content, calendar: calendar)
        XCTAssertEqual(changed, "Log - gym ⏱ 2026-11-05 11:34\nbuy shoes 📅 2026-11-05 ⏱ 2026-11-05 18:05")
    }

    func testResolvingDatesOnALogNoteKeepsTheTimes() {
        let content = "Log - plans ⏱ 2026-11-05 11:34\ncall the bank tomorrow ⏱ 2026-11-05 11:40"
        let resolved = AgendaExtractor.resolvingDates(in: content, previous: nil, previousUpdatedAt: nil, now: morning, calendar: calendar)
        XCTAssertEqual(resolved, "Log - plans ⏱ 2026-11-05 11:34\ncall the bank tomorrow 📅 2026-11-06 ⏱ 2026-11-05 11:40")
    }
}
