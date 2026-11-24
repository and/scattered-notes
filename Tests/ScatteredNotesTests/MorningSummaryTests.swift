import XCTest
@testable import ScatteredNotes

final class MorningSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text)!
    }

    private func note(_ content: String, updated: String = "2026-11-20") -> Note {
        var n = Note(title: "Plans", content: content)
        n.updatedAt = day(updated)
        return n
    }

    func testNothingPlannedAndNothingOverdueSendsNothing() {
        let notes = [note("- [ ] someday maybe\njust a thought")]
        XCTAssertNil(MorningSummary.make(notes: notes, day: day("2026-11-24"), calendar: calendar))
    }

    func testNamesTodaysToDosAndCountsOverdue() throws {
        let notes = [note("""
        - [ ] call the bank 📅 2026-11-24
        - [ ] pay rent 📅 2026-11-24
        - [x] already done 📅 2026-11-24 ✅ 2026-11-24
        - [ ] send the form 📅 2026-11-22
        - [ ] next week 📅 2026-12-01
        """)]
        let summary = try XCTUnwrap(MorningSummary.make(notes: notes, day: day("2026-11-24"), calendar: calendar))
        XCTAssertEqual(summary.title, "2 to-dos today, 1 overdue")
        XCTAssertEqual(summary.body, "call the bank · pay rent")
        XCTAssertEqual(summary.todayCount, 2)
        XCTAssertEqual(summary.overdueCount, 1)
    }

    func testLongListEndsWithHowManyMore() throws {
        let lines = (1...5).map { "- [ ] task \($0) 📅 2026-11-24" }.joined(separator: "\n")
        let summary = try XCTUnwrap(MorningSummary.make(notes: [note(lines)], day: day("2026-11-24"), calendar: calendar))
        XCTAssertEqual(summary.title, "5 to-dos today")
        XCTAssertEqual(summary.body, "task 1 · task 2 · task 3 · +2 more")
    }

    func testOnlyOverdue() throws {
        let summary = try XCTUnwrap(MorningSummary.make(
            notes: [note("- [ ] send the form 📅 2026-11-22")], day: day("2026-11-24"), calendar: calendar))
        XCTAssertEqual(summary.title, "Nothing planned today, 1 overdue")
        XCTAssertEqual(summary.body, "1 to-do is waiting from an earlier day.")
    }

    func testRepeatingToDoHasAnItemOnAComingDayAndCountsOnceWhenMissed() throws {
        // Started on the 20th and never ticked: on the 30th it is due that day, and its missed days are one overdue line
        let notes = [note("- [ ] log daily food 🔁 every day 📅 2026-11-20")]
        let summary = try XCTUnwrap(MorningSummary.make(notes: notes, day: day("2026-11-30"), calendar: calendar))
        XCTAssertEqual(summary.title, "1 to-do today, 1 overdue")
        XCTAssertEqual(summary.body, "log daily food")
    }

    func testTickedRepeatDayIsNotListed() {
        let notes = [note("""
        - [ ] log daily food 🔁 every day 📅 2026-11-25
        - [x] log daily food 🔁 every day 📅 2026-11-24 ✅ 2026-11-24
        """)]
        XCTAssertNil(MorningSummary.make(notes: notes, day: day("2026-11-24"), calendar: calendar))
    }
}
