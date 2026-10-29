package com.scatterednotes.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** A line pulled out of a note for the dashboard: a to-do, a dated plan, or both. */
data class AgendaItem(
    val noteId: UUID,
    val lineIndex: Int,
    val text: String,
    val isTodo: Boolean,
    val isDone: Boolean,
    /** The day the line refers to, if it mentions one */
    val date: LocalDate?,
    /** The day relative words in the line are measured from: when the line was written */
    val writtenOn: LocalDate,
    /** The day a checked line was ticked, from its ✅ marker */
    val doneOn: LocalDate?,
) {
    val id: String get() = "${Note.formatId(noteId)}-$lineIndex"
}

/**
 * Scans note content for checklist lines, plain lines that read as plans (see [isPlannedAction]), and
 * lines that mention a day. Same rules as the Mac and Windows apps. Recognised days (case-insensitive):
 * `2026-10-28` (optionally with `@`), today, tonight, tomorrow, weekday names and "next friday",
 * "next week", "day after tomorrow", "in 3 days", "in 2 weeks", "the day after" (one day after the closest
 * dated line above), and month plus day such as "oct 28", "28 october", "Oct 28th".
 *
 * Relative words resolve against the day the line was written. The app writes that day into the line when
 * the note is saved (see [resolvingDates]), as `📅 2026-10-28` for the day a line refers to and
 * `✅ 2026-10-28` for the day it was ticked, the markers the Obsidian Tasks plugin uses. A line without a
 * `📅` marker, e.g. one written in another editor, resolves against the note's last update.
 */
object AgendaExtractor {
    fun items(note: Note, zone: ZoneId = ZoneId.systemDefault()): List<AgendaItem> {
        val reference = dayOf(note.updatedAt, zone)
        val result = mutableListOf<AgendaItem>()
        var previous: LocalDate? = null

        LineText.split(note.content).forEachIndexed { index, line ->
            val trimmed = LineText.trimWhitespace(line.text)
            if (trimmed.isEmpty() || trimmed.startsWith("#")) return@forEachIndexed

            val checklist = Checklist.state(trimmed)
            val marks = markers(trimmed)
            val date = marks.first ?: parseDate(withoutMarkers(trimmed), reference, previous)
            if (date != null) previous = date

            val text = displayText(trimmed)
            if (text.isEmpty()) return@forEachIndexed
            val isTodo = checklist != null || isPlannedAction(text)
            if (!isTodo && date == null) return@forEachIndexed

            result.add(AgendaItem(note.id, index, text, isTodo, checklist ?: false, date, reference, if (checklist == true) marks.second else null))
        }
        return result
    }

    fun dayOf(instant: Instant, zone: ZoneId): LocalDate = instant.atZone(zone).toLocalDate()

    private val dueMarker = Regex("""\s*📅\s*(\d{4})-(\d{2})-(\d{2})""")
    private val doneMarker = Regex("""\s*✅\s*(\d{4})-(\d{2})-(\d{2})""")

    private fun markedDay(regex: Regex, line: String): LocalDate? {
        val (year, month, day) = regex.find(line)?.destructured ?: return null
        val y = year.toInt()
        val m = month.toInt()
        val d = day.toInt()
        return if (y >= 1 && m in 1..12 && d >= 1 && d <= java.time.YearMonth.of(y, m).lengthOfMonth()) LocalDate.of(y, m, d) else null
    }

    /** The days written into a line by `📅` and `✅`, as (due, done). */
    fun markers(line: String): Pair<LocalDate?, LocalDate?> = markedDay(dueMarker, line) to markedDay(doneMarker, line)

    /** The line without its `📅` and `✅` markers. */
    fun withoutMarkers(line: String): String = line.replace(dueMarker, "").replace(doneMarker, "")

    private fun marker(symbol: String, day: LocalDate): String = " $symbol $day"

    /**
     * The note text with the days written into it. A line whose date comes from a relative word, such as
     * "call the bank tomorrow", gets `📅` and the day it resolves to; a ticked checklist line gets `✅` and the
     * day it was ticked; an unticked one loses its `✅`. Lines are matched with [previous], the text as last
     * saved, by their words, so a line keeps its days when the editor's copy lacks the markers or the line is
     * moved. A line already in [previous] without markers counts as written at [previousUpdatedAt]; any other
     * line was written [now]. Only lines that need a marker change.
     */
    fun resolvingDates(
        content: String, previous: String?, previousUpdatedAt: Instant?, now: Instant, zone: ZoneId = ZoneId.systemDefault(),
    ): String {
        val today = dayOf(now, zone)
        val before = previousUpdatedAt?.let { dayOf(it, zone) } ?: today
        val known = mutableMapOf<String, ArrayDeque<Pair<LocalDate?, LocalDate?>>>()
        for (raw in LineText.split(previous.orEmpty())) {
            val line = LineText.trimWhitespace(raw.text)
            if (line.isEmpty() || line.startsWith("#")) continue
            known.getOrPut(displayText(line)) { ArrayDeque() }.addLast(markers(line))
        }

        val lines = LineText.split(content)
        var previousDate: LocalDate? = null
        for (index in lines.indices) {
            val line = LineText.trimWhitespace(lines[index].text)
            if (line.isEmpty() || line.startsWith("#")) continue
            val key = displayText(line)
            if (key.isEmpty()) continue
            val old = known[key]?.removeFirstOrNull()
            val marks = markers(line)

            var due = marks.first ?: old?.first
            var found: LocalDate? = null
            if (due == null) {
                val parsed = parseDay(withoutMarkers(line), if (old == null) today else before, previousDate)
                found = parsed?.first
                if (parsed != null && parsed.second) due = parsed.first
            }
            (due ?: found)?.let { previousDate = it }

            var done = marks.second
            when (Checklist.state(line)) {
                true -> done = marks.second ?: old?.second ?: (if (old == null) today else before)
                false -> done = null
                null -> {}
            }

            if (due == marks.first && done == marks.second) continue
            var text = withoutMarkers(lines[index].text).trimEnd { LineText.isWhitespace(it) }
            if (due != null) text += marker("📅", due)
            if (done != null) text += marker("✅", done)
            lines[index] = lines[index].copy(text = text)
        }
        return LineText.join(lines)
    }

    private val displayPrefixes = listOf("- [ ]", "* [ ]", "- [x]", "- [X]", "* [x]", "* [X]", "- ", "* ", "+ ")
    private val isoDateToken = Regex("""\s*@?\b\d{4}-\d{2}-\d{2}\b""")

    fun displayText(line: String): String {
        var text = withoutMarkers(line)
        displayPrefixes.firstOrNull { text.startsWith(it) }?.let { text = text.substring(it.length) }
        // An explicit @2026-10-28 marker is metadata; the dashboard shows the date separately
        isoDateToken.find(text)?.let { match ->
            if (match.value.contains('@')) text = text.removeRange(match.range)
        }
        return LineText.trimWhitespace(text)
    }

    /** Verbs that start a line written as an instruction to oneself, e.g. "fix the login bug" */
    private val actionVerbs = listOf(
        "add", "ask", "book", "build", "buy", "call", "cancel", "check", "clean", "confirm", "contact",
        "create", "debug", "delete", "deploy", "draft", "email", "figure", "finish", "fix", "follow",
        "get", "install", "investigate", "look", "make", "move", "pay", "pick", "ping", "prepare",
        "print", "publish", "read", "refactor", "remind", "renew", "reply", "research", "review",
        "schedule", "send", "share", "ship", "sign", "submit", "try", "update", "upload", "visit", "write",
    )

    private val options = setOf(RegexOption.IGNORE_CASE)

    private val plannedAction = Regex(
        """^(?:to-?\s?do\b""" +
            """|(?:(?:i|we)\s+(?:am\s+|are\s+)?|(?:i|we)['’](?:m|re)\s+)?""" +
            """(?:needs?\s+to|ha(?:ve|s)\s+to|must|should|remember\s+to|don['’]?t\s+forget""" +
            """|plan(?:ning)?\s+to|going\s+to|gonna|want\s+to)\s""" +
            """|(?:i|we)(?:\s+will|['’]ll)\s""" +
            "|(?:" + actionVerbs.joinToString("|") + """)\s)""",
        options,
    )

    /**
     * Whether a plain line reads like something the writer plans to do, so it counts as a to-do without
     * checklist syntax: it starts with an action verb ("fix the login bug"), an intent ("need to renew
     * passport", "I'll call Sam") or "todo". Questions and lines ending in ":" are left out.
     */
    fun isPlannedAction(text: String): Boolean =
        !text.endsWith("?") && !text.endsWith(":") && plannedAction.containsMatchIn(text)

    private val months = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
    private const val MONTH_PATTERN =
        "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
    private val weekdays = listOf("sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday")

    private val iso = Regex("""\b(\d{4})-(\d{2})-(\d{2})\b""")
    private val monthDay = Regex("""\b""" + MONTH_PATTERN + """\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b""", options)
    private val dayMonth = Regex("""\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?""" + MONTH_PATTERN + """\b""", options)
    private val relative = Regex("""\b(today|tonight|tomorrow)\b""", options)
    private val weekday = Regex("""\b(next\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b""", options)
    private val dayOfMonth = Regex("""\b(\d{1,2})(?:st|nd|rd|th)?\s+of\s+(?:the\s+)?(next|this)\s+month\b""", options)
    private val endOfMonth = Regex("""\bend\s+of\s+(?:the\s+)?(next\s+|this\s+)?month\b""", options)
    private val theOrdinal = Regex("""\bthe\s+(\d{1,2})(?:st|nd|rd|th)\b""", options)
    private val dayAfterTomorrow = Regex("""\bday\s+after\s+tomorrow\b""", options)
    private val dayAfter = Regex("""\bday\s+after\b""", options)
    private val inInterval = Regex("""\bin\s+(\d{1,3})\s+(day|week)s?\b""", options)
    private val nextWeek = Regex("""\bnext\s+week\b""", options)

    fun parseDate(line: String, reference: LocalDate, previous: LocalDate? = null): LocalDate? =
        parseDay(line, reference, previous)?.first

    /**
     * The day a line refers to and whether it depends on when the line was written ("tomorrow", "friday")
     * rather than being fixed ("2026-10-28", "oct 28").
     */
    fun parseDay(line: String, reference: LocalDate, previous: LocalDate? = null): Pair<LocalDate, Boolean>? {
        iso.find(line)?.let { match ->
            val (year, month, day) = match.destructured
            val y = year.toInt()
            val m = month.toInt()
            val d = day.toInt()
            if (y >= 1 && m in 1..12 && d >= 1 && d <= java.time.YearMonth.of(y, m).lengthOfMonth()) return LocalDate.of(y, m, d) to false
        }
        monthDay.find(line)?.let { match ->
            resolveMonthDay(match.groupValues[1], match.groupValues[2].toIntOrNull(), reference)?.let { return it to false }
        }
        dayMonth.find(line)?.let { match ->
            resolveMonthDay(match.groupValues[2], match.groupValues[1].toIntOrNull(), reference)?.let { return it to false }
        }
        // "22nd of the next month", "22 of this month"
        dayOfMonth.find(line)?.let { match ->
            val ahead = if (match.groupValues[2].equals("next", ignoreCase = true)) 1L else 0L
            inMonth(match.groupValues[1].toInt(), ahead, reference)?.let { return it to true }
        }
        // "end of the month", "end of next month"
        endOfMonth.find(line)?.let { match ->
            val month = reference.withDayOfMonth(1).plusMonths(if (match.groupValues[1].startsWith("next", ignoreCase = true)) 1 else 0)
            return month.withDayOfMonth(month.lengthOfMonth()) to true
        }
        // "on the 22nd": the next such day of a month, today included
        theOrdinal.find(line)?.let { match ->
            for (ahead in 0L..2L) {
                inMonth(match.groupValues[1].toInt(), ahead, reference)?.takeIf { it >= reference }?.let { return it to true }
            }
        }
        if (dayAfterTomorrow.containsMatchIn(line)) return reference.plusDays(2) to true
        // "the day after" continues from the dated line above, e.g. "buy milk today" then "bake the day after"
        if (dayAfter.containsMatchIn(line)) return (previous ?: reference).plusDays(1) to true
        inInterval.find(line)?.let { match ->
            val count = match.groupValues[1].toLong()
            val isWeek = match.groupValues[2].equals("week", ignoreCase = true)
            return reference.plusDays(if (isWeek) count * 7 else count) to true
        }
        relative.find(line)?.let { match ->
            val isTomorrow = match.groupValues[1].equals("tomorrow", ignoreCase = true)
            return reference.plusDays(if (isTomorrow) 1 else 0) to true
        }
        weekday.find(line)?.let { match ->
            val target = weekdays.indexOf(match.groupValues[2].lowercase())
            // java.time counts Monday as 1 and Sunday as 7; the list starts on Sunday
            val current = reference.dayOfWeek.value % 7
            var offset = (target - current + 7) % 7
            if (match.groupValues[1].isNotEmpty()) offset += 7
            return reference.plusDays(offset.toLong()) to true
        }
        if (nextWeek.containsMatchIn(line)) return reference.plusDays(7) to true
        return null
    }

    /** The [day] of the month [monthsAhead] months after the one [reference] is in; null when the month has no such day. */
    private fun inMonth(day: Int, monthsAhead: Long, reference: LocalDate): LocalDate? {
        val month = reference.withDayOfMonth(1).plusMonths(monthsAhead)
        return if (day in 1..month.lengthOfMonth()) month.withDayOfMonth(day) else null
    }

    private fun resolveMonthDay(month: String, day: Int?, reference: LocalDate): LocalDate? {
        val monthIndex = months.indexOf(month.lowercase().take(3))
        if (day == null || day < 1 || monthIndex < 0) return null
        if (day > java.time.YearMonth.of(reference.year, monthIndex + 1).lengthOfMonth()) return null
        val date = LocalDate.of(reference.year, monthIndex + 1, day)
        // A date more than six months before the line was written most likely means next year
        return if (date < reference.minusMonths(6)) date.plusYears(1) else date
    }
}
