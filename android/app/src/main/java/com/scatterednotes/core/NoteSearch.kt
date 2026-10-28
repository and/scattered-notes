package com.scatterednotes.core

import java.text.Normalizer

/** [snippet] is a short stretch of the body around the first match; null when only the title or tags matched. */
data class SearchResult(val note: Note, val score: Int, val snippet: String?)

/**
 * Global note search. Every whitespace separated term must match somewhere in the note (title, body, tags
 * or destination), ignoring case and accents. A term starting with `#` matches tags only.
 */
object NoteSearch {
    fun terms(query: String): List<String> = query.split(Regex("\\s+")).filter { it.isNotEmpty() && it != "#" }

    fun search(query: String, notes: List<Note>, limit: Int = 50): List<SearchResult> {
        val terms = terms(query)
        if (terms.isEmpty()) return emptyList()
        return notes.mapNotNull { match(it, terms) }
            .sortedWith(compareByDescending<SearchResult> { it.score }.thenByDescending { it.note.updatedAt })
            .take(limit)
    }

    /** Text folded for matching, and for each folded character the index it came from in the original. */
    private class Folded(text: String) {
        val chars: String
        val origin: IntArray

        init {
            val builder = StringBuilder()
            val map = ArrayList<Int>()
            for ((index, ch) in text.withIndex()) {
                val decomposed = Normalizer.normalize(ch.toString(), Normalizer.Form.NFD)
                for (part in decomposed) {
                    if (Character.getType(part) == Character.NON_SPACING_MARK.toInt()) continue
                    builder.append(part.lowercaseChar())
                    map.add(index)
                }
            }
            chars = builder.toString()
            origin = map.toIntArray()
        }
    }

    private fun fold(term: String) = Folded(term).chars

    /** Index and length in [text] of the first match of [term], ignoring case and accents. */
    fun find(text: String, term: String, startIndex: Int = 0): Pair<Int, Int>? {
        if (startIndex >= text.length) return null
        val folded = Folded(text)
        val needle = fold(term)
        if (needle.isEmpty()) return null
        val from = folded.origin.indexOfFirst { it >= startIndex }.takeIf { it >= 0 } ?: return null
        val at = folded.chars.indexOf(needle, from)
        if (at < 0) return null
        val start = folded.origin[at]
        val end = folded.origin[at + needle.length - 1] + 1
        return start to end - start
    }

    private fun match(note: Note, terms: List<String>): SearchResult? {
        var score = 0
        var snippet: String? = null
        val title = note.displayTitle
        val destination = note.destinationDisplay

        for (term in terms) {
            if (term.startsWith("#")) {
                val tag = term.substring(1)
                val hit = note.tags.firstOrNull { find(it, tag) != null } ?: return null
                score += if (fold(hit) == fold(tag)) 12 else 8
                continue
            }
            var matched = false
            find(title, term)?.let { (index, _) ->
                matched = true
                score += if (index == 0) 14 else 10
            }
            if (note.tags.any { find(it, term) != null }) {
                matched = true
                score += 6
            }
            if (find(destination, term) != null) {
                matched = true
                score += 3
            }
            find(note.content, term)?.let { (index, length) ->
                matched = true
                score += 1 + minOf(occurrences(note.content, term), 5)
                if (snippet == null) snippet = makeSnippet(note.content, index, length)
            }
            if (!matched) return null
        }
        if (note.isPinned) score += 1
        return SearchResult(note, score, snippet)
    }

    private fun occurrences(text: String, term: String): Int {
        var count = 0
        var from = 0
        while (count < 6) {
            val (index, length) = find(text, term, from) ?: break
            count++
            from = index + maxOf(length, 1)
        }
        return count
    }

    /** About 90 characters of one line around the match, with ellipses where it was cut. */
    fun makeSnippet(text: String, index: Int, length: Int): String {
        val lineStart = if (index == 0) 0 else text.lastIndexOfAny(charArrayOf('\n', '\r'), index - 1) + 1
        val lineEndIndex = text.indexOfAny(charArrayOf('\n', '\r'), index + length)
        val lineEnd = if (lineEndIndex < 0) text.length else lineEndIndex
        val start = safeBoundary(text, maxOf(index - 30, lineStart))
        val end = safeBoundary(text, minOf(index + length + 60, lineEnd))
        var snippet = text.substring(start, end).trim(' ', '\t')
        if (start > lineStart) snippet = "…$snippet"
        if (end < lineEnd) snippet += "…"
        return snippet
    }

    /** Moves a cut point off the middle of a surrogate pair. */
    private fun safeBoundary(text: String, position: Int): Int =
        if (position > 0 && position < text.length && text[position].isLowSurrogate()) position - 1 else position
}
