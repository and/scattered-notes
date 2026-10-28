package com.scatterednotes.core

import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Names for note files and project and area folders that are valid on Android, Windows and macOS. */
object FileNames {
    private val reserved = setOf(
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    )

    private fun isInvalid(ch: Char) = ch.code < 32 || ch in "\\/:*?\"<>|"

    /** The title part of a note file name, as the Mac app makes it: runs of invalid characters and whitespace become "-", cut to 40 characters. */
    fun sanitizeTitle(title: String): String {
        val joined = title.split { isInvalid(it) || it == ' ' || it == '\n' || it == '\t' || it == '\r' }
            .filter { it.isNotEmpty() }
            .joinToString("-")
        if (joined.length <= 40) return joined
        val end = if (joined[39].isHighSurrogate()) 39 else 40
        return joined.substring(0, end)
    }

    private fun String.split(isSeparator: (Char) -> Boolean): List<String> {
        val parts = mutableListOf<String>()
        var start = 0
        for (i in indices) {
            if (!isSeparator(this[i])) continue
            parts.add(substring(start, i))
            start = i + 1
        }
        parts.add(substring(start))
        return parts
    }

    /** `yyyy-MM-dd_<title>.md`, the date being when the note was created. [idSuffixLength] 0 for none. */
    fun noteFileName(note: Note, idSuffixLength: Int = 0, zone: ZoneId = ZoneId.systemDefault()): String {
        val base = sanitizeTitle(note.displayTitle).ifEmpty { "note" }
        val date = DateTimeFormatter.ofPattern("yyyy-MM-dd").format(note.createdAt.atZone(zone))
        return if (idSuffixLength > 0) "${date}_${base}_${note.idString.take(idSuffixLength)}.md" else "${date}_$base.md"
    }

    /** A project or area folder name every platform accepts. "" when nothing usable is left. */
    fun sanitizeFolderName(name: String): String {
        val cleaned = name.trim().map { if (isInvalid(it)) '-' else it }.joinToString("").trimEnd('.', ' ')
        if (cleaned.isEmpty()) return ""
        val stem = cleaned.substringBefore('.')
        return if (stem.uppercase() in reserved) cleaned + "_" else cleaned
    }
}
