package com.scatterednotes.core

/** One line of a text and the line break that ended it ("" for the last line). */
data class Line(val text: String, val lineBreak: String)

/**
 * Line handling shared by every feature that works line by line. "\r\n" counts as a single break, so
 * files written on Windows keep their line endings when a line is edited.
 */
object LineText {
    fun split(text: String): MutableList<Line> {
        val lines = mutableListOf<Line>()
        var start = 0
        var i = 0
        while (i < text.length) {
            val ch = text[i]
            if (ch == '\n' || ch == '\r') {
                val length = if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') 2 else 1
                lines.add(Line(text.substring(start, i), text.substring(i, i + length)))
                i += length
                start = i
            } else {
                i++
            }
        }
        lines.add(Line(text.substring(start), ""))
        return lines
    }

    fun join(lines: List<Line>): String = lines.joinToString("") { it.text + it.lineBreak }

    /** Trims spaces and tabs, like Swift's `.whitespaces` set, but never line breaks. */
    fun trimWhitespace(text: String): String = text.trim { isWhitespace(it) }

    fun isWhitespace(ch: Char): Boolean = ch == '\t' || Character.getType(ch) == Character.SPACE_SEPARATOR.toInt()
}
