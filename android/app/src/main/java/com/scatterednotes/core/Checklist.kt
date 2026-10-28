package com.scatterednotes.core

object Checklist {
    private val open = listOf("- [ ]", "* [ ]")
    private val done = listOf("- [x]", "- [X]", "* [x]", "* [X]")

    /** null when the (trimmed) line is not a checklist item, otherwise whether it is checked. */
    fun state(trimmedLine: String): Boolean? = when {
        open.any { trimmedLine.startsWith(it) } -> false
        done.any { trimmedLine.startsWith(it) } -> true
        else -> null
    }

    private val toggles = listOf(
        "- [ ]" to "- [x]", "- [x]" to "- [ ]", "- [X]" to "- [ ]",
        "* [ ]" to "* [x]", "* [x]" to "* [ ]", "* [X]" to "* [ ]",
    )

    /** Flips the checkbox on line [lineIndex]. A plain line becomes a checked item. Other lines are left untouched. */
    fun toggleLine(lineIndex: Int, content: String): String {
        val lines = LineText.split(content)
        if (lineIndex !in lines.indices) return content
        val line = lines[lineIndex].text
        val toggled = toggles.firstOrNull { line.contains(it.first) }?.let { line.replace(it.first, it.second) }
            ?: completingPlainLine(line)
            ?: return content
        lines[lineIndex] = lines[lineIndex].copy(text = toggled)
        return LineText.join(lines)
    }

    /** "call the bank tomorrow" becomes "- [x] call the bank tomorrow", keeping indentation and replacing a bullet. */
    private fun completingPlainLine(line: String): String? {
        val indent = line.takeWhile { it == ' ' || it == '\t' }
        var body = line.substring(indent.length)
        if (LineText.trimWhitespace(body).isEmpty() || body.startsWith("#")) return null
        listOf("- ", "* ", "+ ").firstOrNull { body.startsWith(it) }?.let { body = body.substring(it.length) }
        return "$indent- [x] $body"
    }
}
