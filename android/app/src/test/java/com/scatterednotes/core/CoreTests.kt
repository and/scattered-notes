package com.scatterednotes.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** Ported from the Mac and Windows tests; the reference day is Monday 26 Oct 2026 in Kolkata. */
class AgendaTests {
    private val zone = ZoneId.of("Asia/Kolkata")
    private val monday = Instant.parse("2026-10-26T03:30:00Z")

    private fun day(month: Int, day: Int, year: Int = 2026) = LocalDate.of(year, month, day)
    private fun parse(line: String) = AgendaExtractor.parseDate(line, day(10, 26))

    @Test
    fun parsesSupportedDateFormats() {
        assertEquals(day(11, 2), parse("Send invoice @2026-11-02"))
        assertEquals(day(10, 27), parse("Call the bank tomorrow"))
        assertEquals(day(10, 26), parse("Finish draft today"))
        assertEquals(day(10, 30), parse("Team dinner on Friday"))
        assertEquals(day(11, 6), parse("Review next friday"))
        assertEquals(day(10, 26), parse("Gym on monday"))
        assertEquals(day(11, 2), parse("Next week, plan to buy spare parts"))
        assertEquals(day(10, 30), parse("Dentist Oct 30th at 4pm"))
        assertEquals(day(11, 3), parse("Flight on 3 November"))
        assertEquals(day(1, 15, 2027), parse("Taxes due jan 15"))
        assertEquals(day(10, 28), parse("day after tomorrow"))
        assertEquals(day(10, 29), parse("in 3 days"))
        assertEquals(day(11, 9), parse("in 2 weeks"))
    }

    @Test
    fun ignoresLinesWithoutDates() {
        assertNull(parse("Buy milk"))
        assertNull(parse("Read chapter 30"))
        assertNull(parse("Sunny weather"))
        assertNull(parse("Feb 30 is not a day"))
        assertNull(parse("Build 0000-00-00 and 2026-13-45"))
    }

    @Test
    fun extractsTodosAndDatedLines() {
        val note = Note(
            title = "Week",
            content = "# Plans for tomorrow\n- [ ] Renew passport\n- [x] Pay rent\nLunch with Sam tomorrow\nJust a thought\n- [ ] Send invoice @2026-11-02",
            createdAt = monday,
            updatedAt = monday,
        )
        val items = AgendaExtractor.items(note, zone = zone)
        assertEquals(listOf("Renew passport", "Pay rent", "Lunch with Sam tomorrow", "Send invoice"), items.map { it.text })
        assertEquals(listOf(1, 2, 3, 5), items.map { it.lineIndex })
        assertEquals(listOf(true, true, false, true), items.map { it.isTodo })
        assertEquals(listOf(false, true, false, false), items.map { it.isDone })
        assertEquals(listOf(null, null, day(10, 27), day(11, 2)), items.map { it.date })
    }

    @Test
    fun plainLinesThatReadAsPlansAreTodos() {
        listOf(
            "fix the right side of the mac screen getting unresponsive.",
            "- Call the bank",
            "Need to renew passport",
            "I have to pay rent",
            "I’ll email Sam the slides",
            "we're going to repaint the hall",
            "Don't forget the charger",
            "TODO: back up photos",
        ).forEach { assertTrue(it, AgendaExtractor.isPlannedAction(AgendaExtractor.displayText(it))) }
        listOf("Just a thought", "Lunch with Sam", "Fixed the login bug", "Should we move?", "Read later:", "Fixes")
            .forEach { assertFalse(it, AgendaExtractor.isPlannedAction(it)) }
    }

    @Test
    fun tickingAPlainLineMakesItAChecklistItem() {
        assertEquals("a\n- [x] fix the screen bug\r\nb", Checklist.toggleLine(1, "a\nfix the screen bug\r\nb"))
        assertEquals("  - [ ] Pay rent", Checklist.toggleLine(0, "  - [x] Pay rent"))
        assertEquals("# Heading", Checklist.toggleLine(0, "# Heading"))
    }

    @Test
    fun dashboardSortsItemsIntoSections() {
        val note = Note(content = "overdue thing 2026-10-20\n- [ ] pay rent today\nlunch friday\nfix the bike", createdAt = monday, updatedAt = monday)
        val dashboard = Dashboard.build(listOf(note), AgendaExtractor.items(note, zone = zone), day(10, 26))
        assertEquals(emptyList<String>(), dashboard.overdue.map { it.text })
        assertEquals(listOf("pay rent today"), dashboard.dueToday.map { it.text })
        assertEquals(listOf(day(10, 30)), dashboard.upcoming.map { it.first })
        assertEquals(listOf("fix the bike"), dashboard.undatedTodos.single().second.map { it.text })
        assertEquals(2, dashboard.openTodoCount)
        assertEquals("Tomorrow", Dashboard.dayLabel(day(10, 27), day(10, 26)))
    }
}

class NoteFormatTests {
    @Test
    fun roundTripsTheSharedFormat() {
        val note = Note(
            id = UUID.fromString("7C1F3A52-1111-4B5B-9C8E-1234567890AB"),
            title = "Say \"hi\"\nthere",
            content = "Body\n---\nmore",
            categoryType = CategoryType.PROJECT,
            targetName = "Garden",
            createdAt = Instant.parse("2026-10-27T09:00:00.123Z"),
            updatedAt = Instant.parse("2026-10-28T05:00:00Z"),
            tags = listOf("home", "weekend"),
            isPinned = true,
        )
        val text = NoteFormat.serialize(note)
        assertTrue(text.startsWith("---\nid: 7C1F3A52-1111-4B5B-9C8E-1234567890AB\ntitle: \"Say \\\"hi\\\"\\nthere\"\ntype: project\n"))
        assertTrue(text.contains("created_at: 2026-10-27T09:00:00.123Z\n"))
        assertEquals(note.copy(filePath = "x.md"), NoteFormat.parse(text, "x.md"))
    }

    @Test
    fun readsFilesWrittenByOtherApps() {
        val raw = "---\r\nid: 7c1f3a52-1111-4b5b-9c8e-1234567890ab\r\ntitle: \"\"\r\ncreated_at: 2026-10-27T09:00:00+05:30\r\n---\r\n\r\n# Groceries\r\nmilk"
        val note = NoteFormat.parse(raw)
        assertEquals("7C1F3A52-1111-4B5B-9C8E-1234567890AB", note.idString)
        assertEquals("Groceries", note.title)
        assertEquals(Instant.parse("2026-10-27T03:30:00Z"), note.createdAt)
        assertEquals("# Groceries\r\nmilk", note.content)
    }

    @Test
    fun withoutFrontmatterTheWholeFileIsTheBody() {
        val note = NoteFormat.parse("just text\n---\n")
        assertEquals("just text\n---\n", note.content)
        assertEquals(CategoryType.INBOX, note.categoryType)
    }
}

class AgendaMarkerTests {
    private val zone = ZoneId.of("Asia/Kolkata")
    private val monday = Instant.parse("2026-10-26T03:30:00Z")

    private fun day(month: Int, day: Int) = LocalDate.of(2026, month, day)

    private fun resolve(content: String, previous: String? = null, previousUpdatedAt: Instant? = null, now: Instant = monday) =
        AgendaExtractor.resolvingDates(content, previous, previousUpdatedAt, now, zone)

    @Test
    fun markersFixAWordsDayAndShowTheTickDay() {
        val note = Note(
            content = "Call bank tomorrow 📅 2026-10-30\n- [x] Pay rent ✅ 2026-10-25\n- [x] Send form friday 📅 2026-11-06 ✅ 2026-10-28",
            createdAt = monday, updatedAt = monday,
        )
        val items = AgendaExtractor.items(note, zone)

        assertEquals(listOf("Call bank tomorrow", "Pay rent", "Send form friday"), items.map { it.text })
        assertEquals(listOf(day(10, 30), null, day(11, 6)), items.map { it.date })
        assertEquals(listOf(null, day(10, 25), day(10, 28)), items.map { it.doneOn })
    }

    @Test
    fun writesTheDayOfRelativeWordsOnly() {
        val content = "Call bank tomorrow\nlunch on 2026-11-02\nbuy milk oct 28\n# Heading today\nplain line"
        val once = resolve(content)
        assertEquals("Call bank tomorrow 📅 2026-10-27\nlunch on 2026-11-02\nbuy milk oct 28\n# Heading today\nplain line", once)
        assertEquals("a marked line never moves", once, resolve(once, once, monday, monday.plusSeconds(5 * 86_400)))
    }

    @Test
    fun keepsTheMarkerWhenTheEditorsCopyLacksIt() {
        val saved = "Call bank tomorrow 📅 2026-10-27"
        val later = monday.plusSeconds(4 * 86_400)
        assertEquals(saved, resolve("Call bank tomorrow", saved, monday, later))
        assertEquals("intro\n$saved", resolve("intro\nCall bank tomorrow", saved, monday, later))
        assertEquals("Call bank tomorrow 📅 2026-11-02", resolve("Call bank tomorrow 📅 2026-11-02", saved, monday, later))
    }

    @Test
    fun duplicateLinesKeepTheirOwnDays() {
        val saved = "call bank tomorrow 📅 2026-10-27\ncall bank tomorrow 📅 2026-10-31"
        assertEquals(saved, resolve("call bank tomorrow\ncall bank tomorrow", saved, monday, monday.plusSeconds(9 * 86_400)))
    }

    @Test
    fun datesNewLinesFromNowAndOldUnmarkedLinesFromTheirNote() {
        val result = resolve("old plan tomorrow\nnew plan tomorrow", "old plan tomorrow", monday, monday.plusSeconds(3 * 86_400))
        assertEquals("old plan tomorrow 📅 2026-10-27\nnew plan tomorrow 📅 2026-10-30", result)
    }

    @Test
    fun chainsTheDayAfterFromTheLineAbove() {
        assertEquals("buy tomatoes today 📅 2026-10-26\nbake the day after 📅 2026-10-27", resolve("buy tomatoes today\nbake the day after"))
    }

    @Test
    fun writesAndRemovesTheTickDay() {
        val ticked = resolve("- [x] call bank")
        assertEquals("- [x] call bank ✅ 2026-10-26", ticked)
        val later = monday.plusSeconds(86_400)
        assertEquals(ticked, resolve(ticked, ticked, monday, later))
        assertEquals(ticked, resolve("- [x] call bank", ticked, monday, later))
        assertEquals("- [ ] call bank", resolve("- [ ] call bank ✅ 2026-10-26", ticked, monday, later))
        assertEquals("- [x] send form friday 📅 2026-10-30 ✅ 2026-10-26", resolve("- [x] send form friday"))
    }

    @Test
    fun keepsWindowsLineEndings() {
        assertEquals("a\r\ncall bank tomorrow 📅 2026-10-27\r\nb", resolve("a\r\ncall bank tomorrow\r\nb"))
    }

    @Test
    fun markersAreInvisibleToTheLineText() {
        assertEquals("call bank tomorrow", AgendaExtractor.displayText("- [x] call bank tomorrow 📅 2026-10-27 ✅ 2026-10-28"))
        assertTrue(AgendaExtractor.isPlannedAction(AgendaExtractor.displayText("call bank 📅 2026-10-27")))
    }
}

class SearchAndFileNameTests {
    @Test
    fun searchIgnoresCaseAndAccents() {
        val cafe = Note(title = "Café plans", content = "Meet at the CAFÉ on friday", tags = listOf("food"))
        val other = Note(title = "Bank", content = "call")
        val results = NoteSearch.search("cafe", listOf(other, cafe))
        assertEquals(listOf(cafe.id), results.map { it.note.id })
        assertEquals("Meet at the CAFÉ on friday", results.single().snippet)
        assertEquals(listOf(cafe.id), NoteSearch.search("#foo", listOf(cafe, other)).map { it.note.id })
        assertTrue(NoteSearch.search("cafe bank", listOf(cafe, other)).isEmpty())
    }

    @Test
    fun fileNamesMatchTheMacApp() {
        val note = Note(
            id = UUID.fromString("7C1F3A52-1111-4B5B-9C8E-1234567890AB"),
            title = "Plan: the \"big\" trip / 2026",
            createdAt = Instant.parse("2026-10-27T20:00:00Z"),
        )
        val zone = ZoneId.of("Asia/Kolkata")
        assertEquals("2026-10-28_Plan-the-big-trip-2026.md", FileNames.noteFileName(note, 0, zone))
        assertEquals("2026-10-28_Plan-the-big-trip-2026_7C1F3A.md", FileNames.noteFileName(note, 6, zone))
        assertEquals("CON_", FileNames.sanitizeFolderName("CON"))
        assertEquals("a-b", FileNames.sanitizeFolderName(" a/b. "))
    }
}
