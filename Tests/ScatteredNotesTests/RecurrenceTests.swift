import XCTest
@testable import ScatteredNotes

/// To-dos that repeat: "log daily food" is one item for each day since it started, ticked one day at a time.
final class RecurrenceTests: XCTestCase {
    private let cal = Calendar.current

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func items(_ content: String, now: Date) -> [AgendaItem] {
        var note = Note(title: "T", content: content)
        note.updatedAt = now
        return AgendaExtractor.items(from: note, calendar: cal, now: now)
    }

    // MARK: Words

    func testWordsAreRead() {
        XCTAssertEqual(Recurrence.find(in: "log daily food")?.text, "every day")
        XCTAssertEqual(Recurrence.find(in: "take vitamins every morning")?.text, "every day")
        XCTAssertEqual(Recurrence.find(in: "water plants every 3 days")?.text, "every 3 days")
        XCTAssertEqual(Recurrence.find(in: "stand-up every weekday")?.text, "every weekday")
        XCTAssertEqual(Recurrence.find(in: "gym every Mon and thu")?.text, "every monday and thursday")
        XCTAssertEqual(Recurrence.find(in: "pay rent every month")?.text, "every month")
        XCTAssertEqual(Recurrence.find(in: "review every other week")?.text, "every 2 weeks")
        XCTAssertEqual(Recurrence.find(in: "weekly report")?.text, "every week")
        XCTAssertNil(Recurrence.find(in: "call the bank tomorrow"))
        XCTAssertNil(Recurrence.find(in: "every thing is fine"))
    }

    func testWrittenRuleReadsBackAsTheSameRule() {
        for words in ["every day", "every 3 days", "every weekday", "every weekend", "every monday",
                      "every monday, wednesday and friday", "every week", "every 2 weeks", "every month", "every year"] {
            XCTAssertEqual(Recurrence.find(in: words)?.text, words)
        }
    }

    // MARK: Days

    func testDaysCountFromTheStart() {
        let rule = Recurrence(unit: .day, interval: 3)
        XCTAssertEqual(rule.days(from: day(2026, 11, 1), through: day(2026, 11, 10), calendar: cal),
                       [day(2026, 11, 1), day(2026, 11, 4), day(2026, 11, 7), day(2026, 11, 10)])
        XCTAssertEqual(rule.next(after: day(2026, 11, 10), from: day(2026, 11, 1), calendar: cal), day(2026, 11, 13))
    }

    func testMonthEndIsClampedWithoutShiftingLaterMonths() {
        let rule = Recurrence(unit: .month)
        let days = rule.days(from: day(2026, 1, 31), through: day(2026, 4, 30), calendar: cal)
        XCTAssertEqual(days, [day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30)])
    }

    func testNamedWeekdays() {
        let rule = Recurrence(unit: .week, weekdays: [2, 5]) // Monday, Thursday
        // 2026-11-16 is a Monday
        XCTAssertEqual(rule.days(from: day(2026, 11, 16), through: day(2026, 11, 23), calendar: cal),
                       [day(2026, 11, 16), day(2026, 11, 19), day(2026, 11, 23)])
        XCTAssertEqual(rule.firstDay(onOrAfter: day(2026, 11, 17), calendar: cal), day(2026, 11, 19))
    }

    // MARK: Items

    func testMissedDaysEachShowAndTodayToo() {
        let content = "- [ ] log daily food 🔁 every day 📅 2026-11-18"
        let list = items(content, now: day(2026, 11, 20))
        // Nov 18, 19 overdue, Nov 20 today, Nov 21 next
        XCTAssertEqual(list.compactMap(\.date), [day(2026, 11, 18), day(2026, 11, 19), day(2026, 11, 20), day(2026, 11, 21)])
        XCTAssertEqual(Set(list.map(\.id)).count, 4)
        XCTAssertTrue(list.allSatisfy { $0.recurrence == "every day" && !$0.isDone })
    }

    func testTickedDayDoesNotShowAgain() {
        let content = """
        - [ ] log daily food 🔁 every day 📅 2026-11-18
        - [x] log daily food 🔁 every day 📅 2026-11-19 ✅ 2026-11-19
        """
        let open = items(content, now: day(2026, 11, 20)).filter { !$0.isDone }.compactMap(\.date)
        XCTAssertEqual(open, [day(2026, 11, 18), day(2026, 11, 20), day(2026, 11, 21)])
    }

    // MARK: Ticking

    func testTickingTheOldestDayMovesTheStartOn() {
        let content = "- [ ] log daily food 🔁 every day 📅 2026-11-18"
        let result = Note.togglingChecklistLine(0, in: content, occurrence: day(2026, 11, 18), now: day(2026, 11, 20), calendar: cal)
        XCTAssertEqual(result, """
        - [ ] log daily food 🔁 every day 📅 2026-11-19
        - [x] log daily food 🔁 every day 📅 2026-11-18 ✅ 2026-11-20
        """)
        let open = items(result, now: day(2026, 11, 20)).filter { !$0.isDone }.compactMap(\.date)
        XCTAssertEqual(open, [day(2026, 11, 19), day(2026, 11, 20), day(2026, 11, 21)])
    }

    func testTickingAMiddleDayKeepsTheStart() {
        let content = "- [ ] log daily food 🔁 every day 📅 2026-11-18"
        let result = Note.togglingChecklistLine(0, in: content, occurrence: day(2026, 11, 19), now: day(2026, 11, 20), calendar: cal)
        XCTAssertTrue(result.hasPrefix("- [ ] log daily food 🔁 every day 📅 2026-11-18\n- [x] log daily food 🔁 every day 📅 2026-11-19 ✅ 2026-11-20"))
        let open = items(result, now: day(2026, 11, 20)).filter { !$0.isDone }.compactMap(\.date)
        XCTAssertEqual(open, [day(2026, 11, 18), day(2026, 11, 20), day(2026, 11, 21)])
    }

    func testTickInTheEditorTicksToday() {
        let content = "- [ ] log daily food 🔁 every day 📅 2026-11-18"
        let result = Note.togglingChecklistLine(0, in: content, now: day(2026, 11, 20), calendar: cal)
        XCTAssertTrue(result.contains("📅 2026-11-20 ✅ 2026-11-20"))
    }

    func testUntickingATickedDayOpensItAgain() {
        let content = """
        - [ ] log daily food 🔁 every day 📅 2026-11-19
        - [x] log daily food 🔁 every day 📅 2026-11-18 ✅ 2026-11-20
        """
        let result = Note.togglingChecklistLine(1, in: content, now: day(2026, 11, 20), calendar: cal)
        XCTAssertEqual(result, "- [ ] log daily food 🔁 every day 📅 2026-11-19")
        let open = items(result, now: day(2026, 11, 20)).filter { !$0.isDone }.compactMap(\.date)
        XCTAssertEqual(open.first, day(2026, 11, 19))
    }

    func testOrdinaryChecklistLineStillFlips() {
        XCTAssertEqual(Note.togglingChecklistLine(0, in: "- [ ] call mom", now: day(2026, 11, 20), calendar: cal), "- [x] call mom")
    }

    // MARK: Saving

    func testSavingAddsTheMarkerAndFirstDay() {
        let saved = AgendaExtractor.resolvingDates(
            in: "- [ ] log daily food", previous: nil, previousUpdatedAt: nil, now: day(2026, 11, 20), calendar: cal)
        XCTAssertEqual(saved, "- [ ] log daily food 🔁 every day 📅 2026-11-20")
        // Saving again changes nothing, and the records of ticked days survive it
        let again = AgendaExtractor.resolvingDates(
            in: saved, previous: saved, previousUpdatedAt: day(2026, 11, 20), now: day(2026, 11, 21), calendar: cal)
        XCTAssertEqual(again, saved)
        let ticked = "- [ ] log daily food 🔁 every day 📅 2026-11-21\n- [x] log daily food 🔁 every day 📅 2026-11-20 ✅ 2026-11-20"
        XCTAssertEqual(AgendaExtractor.resolvingDates(
            in: ticked, previous: ticked, previousUpdatedAt: day(2026, 11, 20), now: day(2026, 11, 21), calendar: cal), ticked)
    }

    func testWeekdayWordsAreNotReadAsADate() {
        // 2026-11-18 is a Wednesday; "every monday" starts on the next Monday, not "monday" as a one-off date
        let saved = AgendaExtractor.resolvingDates(
            in: "- [ ] gym every monday", previous: nil, previousUpdatedAt: nil, now: day(2026, 11, 18), calendar: cal)
        XCTAssertEqual(saved, "- [ ] gym every monday 🔁 every monday 📅 2026-11-23")
    }

    func testChangingTheDateMovesTheStartAndKeepsTheRule() {
        let result = AgendaExtractor.settingDate(day(2026, 11, 25), onLine: 0, in: "- [ ] log daily food 🔁 every day 📅 2026-11-18", calendar: cal)
        XCTAssertEqual(result, "- [ ] log daily food 🔁 every day 📅 2026-11-25")
    }

    // MARK: Dashboard

    func testOldMissedDaysFoldIntoOneCount() {
        let now = day(2026, 11, 30)
        var note = Note(title: "Food", content: "- [ ] log daily food 🔁 every day 📅 2026-11-01")
        note.updatedAt = now
        let list = AgendaExtractor.items(from: note, calendar: cal, now: now)
        let snapshot = DashboardSnapshot(notes: [note], items: list, today: now, upcomingDays: 14, calendar: cal)
        // 29 days overdue (Nov 1 to 29): the last 7 stay, 22 fold
        XCTAssertEqual(snapshot.overdue.count, DashboardSnapshot.recentRepeatDays)
        XCTAssertEqual(snapshot.earlierRepeats.first?.count, 22)
        XCTAssertEqual(snapshot.overdue.first?.date, day(2026, 11, 23))
    }
}
