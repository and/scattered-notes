package com.scatterednotes.core

/**
 * The inline marks a note can carry: `@person`, `#tag` and `+project`, with the same rules as the Mac app.
 *
 * A mark counts only at the start of a word (after the start of the text, whitespace or an opening bracket or
 * quote) and when a letter follows the symbol, so "user@mail.com", "C#", "+91 98…" and "#1" are left alone.
 * A mark runs on through letters, digits, `-`, `_` and `.`, and loses a trailing `.`.
 */
object Mentions {
    enum class Kind(val symbol: Char) { PERSON('@'), TAG('#'), PROJECT('+') }

    data class Mark(val kind: Kind, val name: String, val start: Int, val end: Int)

    fun marks(text: String): List<Mark> {
        val marks = mutableListOf<Mark>()
        var i = 0
        while (i < text.length) {
            val kind = Kind.entries.firstOrNull { it.symbol == text[i] }
            val startsWord = i == 0 || text[i - 1].isWhitespace() || text[i - 1] in "([{\"'"
            if (kind != null && startsWord && i + 1 < text.length && text[i + 1].isLetter()) {
                var end = i + 1
                while (end < text.length && (text[end].isLetterOrDigit() || text[end] in "-_.")) end++
                while (text[end - 1] == '.') end--
                marks += Mark(kind, text.substring(i + 1, end), i, end)
                i = end
                continue
            }
            i++
        }
        return marks
    }

    /** The distinct names of one kind, in the order they first appear; names differing only in case count once. */
    fun names(kind: Kind, text: String): List<String> {
        val seen = mutableSetOf<String>()
        return marks(text).filter { it.kind == kind }.map { it.name }.filter { seen.add(it.lowercase()) }
    }

    /** The tag an area becomes, as on the Mac: "Home Office" becomes "home-office". */
    fun tagNameForArea(area: String): String {
        val name = area.lowercase().split(Regex("[^\\p{L}\\p{N}_-]+")).filter { it.isNotEmpty() }.joinToString("-")
        return if (name.firstOrNull()?.isLetter() == true) name else "area-$name"
    }
}
