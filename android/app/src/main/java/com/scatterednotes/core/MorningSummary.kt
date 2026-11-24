package com.scatterednotes.core

import java.time.LocalDate

/**
 * The text of the morning notification for one day: what is planned that day and how many to-dos are
 * overdue. Same wording as the iPhone app (`Sources/Models/MorningSummary.swift`).
 */
data class MorningSummary(
    val title: String,
    val body: String,
    /** Open items planned for the day */
    val todayCount: Int,
    /** Open to-dos dated before the day, each line once */
    val overdueCount: Int,
) {
    companion object {
        /** How many of the day's items are named in the body before "+N more" */
        const val NAMED_ITEMS = 3

        /** The summary for [day], or null when nothing is planned that day and nothing is overdue */
        fun make(items: List<AgendaItem>, day: LocalDate): MorningSummary? {
            val open = items.filter { !it.isDone && it.date != null }
            val today = open.filter { it.date == day }
            val overdue = open.filter { it.isTodo && it.date!! < day }.map { it.id }.toSet().size
            return make(today, overdue)
        }

        fun make(today: List<AgendaItem>, overdueCount: Int): MorningSummary? {
            if (today.isEmpty() && overdueCount == 0) return null
            // To-dos first, in the order they are written
            val ordered = today.filter { it.isTodo } + today.filter { !it.isTodo }
            var title = if (ordered.isEmpty()) {
                "Nothing planned today"
            } else {
                val noun = if (ordered.all { it.isTodo }) {
                    if (ordered.size == 1) "to-do" else "to-dos"
                } else {
                    if (ordered.size == 1) "thing" else "things"
                }
                "${ordered.size} $noun today"
            }
            if (overdueCount > 0) title += ", $overdueCount overdue"

            val body = if (ordered.isEmpty()) {
                if (overdueCount == 1) "1 to-do is waiting from an earlier day." else "$overdueCount to-dos are waiting from earlier days."
            } else {
                val named = ordered.take(NAMED_ITEMS).joinToString(" · ") { it.text }
                if (ordered.size > NAMED_ITEMS) "$named · +${ordered.size - NAMED_ITEMS} more" else named
            }
            return MorningSummary(title, body, ordered.size, overdueCount)
        }
    }
}
