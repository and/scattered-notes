package com.scatterednotes.core

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID

/** What the dashboard shows, worked out from every note's agenda items. Same rules as the Mac and Windows apps. */
data class Dashboard(
    val today: LocalDate,
    /** Open to-dos dated before today, oldest first. */
    val overdue: List<AgendaItem>,
    /** Everything dated today, open items first. */
    val dueToday: List<AgendaItem>,
    /** Open items in the next [UPCOMING_DAYS] days, grouped by day. */
    val upcoming: List<Pair<LocalDate, List<AgendaItem>>>,
    /** Open to-dos without a date, grouped by note, most recently updated note first. */
    val undatedTodos: List<Pair<Note, List<AgendaItem>>>,
    val openTodoCount: Int,
    val notesById: Map<UUID, Note>,
) {
    val upcomingCount: Int get() = upcoming.sumOf { it.second.size }
    val isEmpty: Boolean get() = overdue.isEmpty() && dueToday.isEmpty() && upcoming.isEmpty() && undatedTodos.isEmpty()

    companion object {
        const val UPCOMING_DAYS = 14L

        fun build(notes: List<Note>, items: List<AgendaItem>, today: LocalDate): Dashboard {
            val notesById = notes.associateBy { it.id }
            val end = today.plusDays(UPCOMING_DAYS + 1)
            return Dashboard(
                today = today,
                overdue = items.filter { it.isTodo && !it.isDone && it.date != null && it.date < today }.sortedBy { it.date },
                dueToday = items.filter { it.date == today }.sortedBy { it.isDone },
                upcoming = items
                    .filter { it.date != null && it.date > today && it.date < end && !it.isDone }
                    .groupBy { it.date!! }
                    .toSortedMap()
                    .map { it.key to it.value },
                undatedTodos = items
                    .filter { it.isTodo && !it.isDone && it.date == null }
                    .groupBy { it.noteId }
                    .mapNotNull { (id, group) -> notesById[id]?.let { it to group.sortedBy { item -> item.lineIndex } } }
                    .sortedByDescending { it.first.updatedAt },
                openTodoCount = items.count { it.isTodo && !it.isDone },
                notesById = notesById,
            )
        }

        /** "Today", "Tomorrow", "Yesterday", a weekday within the week, otherwise e.g. "Mon, 2 Nov". */
        fun dayLabel(day: LocalDate, today: LocalDate, locale: Locale = Locale.getDefault()): String =
            when (val days = ChronoUnit.DAYS.between(today, day)) {
                0L -> "Today"
                1L -> "Tomorrow"
                -1L -> "Yesterday"
                in 2L..6L -> day.format(DateTimeFormatter.ofPattern("EEEE", locale))
                else -> day.format(DateTimeFormatter.ofPattern("EEE, d MMM", locale))
            }
    }
}
