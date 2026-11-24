package com.scatterednotes.core

import com.scatterednotes.notify.MorningReminder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.UUID

/** Same cases as Tests/ScatteredNotesTests/MorningSummaryTests.swift, except repeating to-dos (not on Android yet) */
class MorningSummaryTests {
    private val today = LocalDate.of(2026, 11, 24)
    private val note = UUID.randomUUID()
    private var line = 0

    private fun item(text: String, date: LocalDate?, isTodo: Boolean = true, isDone: Boolean = false) =
        AgendaItem(note, line++, text, isTodo, isDone, date, today, null)

    @Test
    fun nothingPlannedAndNothingOverdueSendsNothing() {
        assertNull(MorningSummary.make(listOf(item("someday maybe", null), item("next week", today.plusDays(7))), today))
    }

    @Test
    fun namesTodaysToDosAndCountsOverdue() {
        val summary = MorningSummary.make(
            listOf(
                item("call the bank", today),
                item("pay rent", today),
                item("already done", today, isDone = true),
                item("send the form", today.minusDays(2)),
                item("next week", today.plusDays(7)),
            ),
            today,
        )!!
        assertEquals("2 to-dos today, 1 overdue", summary.title)
        assertEquals("call the bank · pay rent", summary.body)
    }

    @Test
    fun longListEndsWithHowManyMore() {
        val summary = MorningSummary.make((1..5).map { item("task $it", today) }, today)!!
        assertEquals("5 to-dos today", summary.title)
        assertEquals("task 1 · task 2 · task 3 · +2 more", summary.body)
    }

    @Test
    fun onlyOverdue() {
        val summary = MorningSummary.make(listOf(item("send the form", today.minusDays(2))), today)!!
        assertEquals("Nothing planned today, 1 overdue", summary.title)
        assertEquals("1 to-do is waiting from an earlier day.", summary.body)
    }

    @Test
    fun datedPlanThatIsNotAToDoIsListedAfterToDos() {
        val summary = MorningSummary.make(listOf(item("dinner with Sam", today, isTodo = false), item("buy wine", today)), today)!!
        assertEquals("2 things today", summary.title)
        assertEquals("buy wine · dinner with Sam", summary.body)
    }

    @Test
    fun nextTimeIsTodayUntilItHasPassed() {
        val morning = LocalDateTime.of(2026, 11, 24, 7, 0)
        assertEquals(LocalDateTime.of(2026, 11, 24, 8, 0), MorningReminder.nextTime(8 * 60, morning))
        assertEquals(LocalDateTime.of(2026, 11, 25, 8, 0), MorningReminder.nextTime(8 * 60, morning.withHour(8)))
    }
}
