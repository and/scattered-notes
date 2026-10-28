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
    /** The day relative words in the line are measured from: when the line first appeared */
    val writtenOn: LocalDate,
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
 * Relative words resolve against the day the line was first written. `anchors` maps a line's log key (see
 * [logKey]) to that moment; lines without one fall back to the note's creation date.
 */
object AgendaExtractor {
    fun items(note: Note, anchors: Map<String, Instant> = emptyMap(), zone: ZoneId = ZoneId.systemDefault()): List<AgendaItem> {
        val created = dayOf(note.createdAt, zone)
        val result = mutableListOf<AgendaItem>()
        var previous: LocalDate? = null

        LineText.split(note.content).forEachIndexed { index, line ->
            val trimmed = LineText.trimWhitespace(line.text)
            if (trimmed.isEmpty() || trimmed.startsWith("#")) return@forEachIndexed

            val checklist = Checklist.state(trimmed)
            val reference = anchors[logKey(trimmed)]?.let { dayOf(it, zone) } ?: created
            val date = parseDate(trimmed, reference, previous)
            if (date != null) previous = date

            val text = displayText(trimmed)
            if (text.isEmpty()) return@forEachIndexed
            val isTodo = checklist != null || isPlannedAction(text)
            if (!isTodo && date == null) return@forEachIndexed

            result.add(AgendaItem(note.id, index, text, isTodo, checklist ?: false, date, reference))
        }
        return result
    }

    fun dayOf(instant: Instant, zone: ZoneId): LocalDate = instant.atZone(zone).toLocalDate()

    /** Identifies a line across edits that do not touch its words, e.g. ticking it or moving it. */
    fun logKey(line: String): String = displayText(LineText.trimWhitespace(line)).lowercase()

    private val displayPrefixes = listOf("- [ ]", "* [ ]", "- [x]", "- [X]", "* [x]", "* [X]", "- ", "* ", "+ ")
    private val isoDateToken = Regex("""\s*@?\b\d{4}-\d{2}-\d{2}\b""")

    fun displayText(line: String): String {
        var text = line
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
    private val dayAfterTomorrow = Regex("""\bday\s+after\s+tomorrow\b""", options)
    private val dayAfter = Regex("""\bday\s+after\b""", options)
    private val inInterval = Regex("""\bin\s+(\d{1,3})\s+(day|week)s?\b""", options)
    private val nextWeek = Regex("""\bnext\s+week\b""", options)

    fun parseDate(line: String, reference: LocalDate, previous: LocalDate? = null): LocalDate? {
        iso.find(line)?.let { match ->
            val (year, month, day) = match.destructured
            val y = year.toInt()
            val m = month.toInt()
            val d = day.toInt()
            if (y >= 1 && m in 1..12 && d >= 1 && d <= java.time.YearMonth.of(y, m).lengthOfMonth()) return LocalDate.of(y, m, d)
        }
        monthDay.find(line)?.let { match ->
            resolveMonthDay(match.groupValues[1], match.groupValues[2].toIntOrNull(), reference)?.let { return it }
        }
        dayMonth.find(line)?.let { match ->
            resolveMonthDay(match.groupValues[2], match.groupValues[1].toIntOrNull(), reference)?.let { return it }
        }
        if (dayAfterTomorrow.containsMatchIn(line)) return reference.plusDays(2)
        // "the day after" continues from the dated line above, e.g. "buy milk today" then "bake the day after"
        if (dayAfter.containsMatchIn(line)) return (previous ?: reference).plusDays(1)
        inInterval.find(line)?.let { match ->
            val count = match.groupValues[1].toLong()
            val isWeek = match.groupValues[2].equals("week", ignoreCase = true)
            return reference.plusDays(if (isWeek) count * 7 else count)
        }
        relative.find(line)?.let { match ->
            val isTomorrow = match.groupValues[1].equals("tomorrow", ignoreCase = true)
            return reference.plusDays(if (isTomorrow) 1 else 0)
        }
        weekday.find(line)?.let { match ->
            val target = weekdays.indexOf(match.groupValues[2].lowercase())
            // java.time counts Monday as 1 and Sunday as 7; the list starts on Sunday
            val current = reference.dayOfWeek.value % 7
            var offset = (target - current + 7) % 7
            if (match.groupValues[1].isNotEmpty()) offset += 7
            return reference.plusDays(offset.toLong())
        }
        if (nextWeek.containsMatchIn(line)) return reference.plusDays(7)
        return null
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
