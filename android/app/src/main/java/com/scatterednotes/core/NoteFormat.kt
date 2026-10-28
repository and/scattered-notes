package com.scatterednotes.core

import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.UUID

/** Reads and writes the note file format shared with the Mac and Windows apps. The body is kept exactly as it is. */
object NoteFormat {
    private val writeFormat = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)
    private val uuidPattern = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

    fun formatDate(date: Instant): String = writeFormat.format(date)

    /** ISO 8601 with or without fractional seconds, any offset. */
    fun parseDate(value: String): Instant? = try {
        OffsetDateTime.parse(value, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant()
    } catch (_: DateTimeParseException) {
        null
    }

    fun serialize(note: Note): String {
        val fm = StringBuilder("---\n")
        fm.append("id: ").append(note.idString).append('\n')
        fm.append("title: \"").append(escapeYaml(note.title)).append("\"\n")
        fm.append("type: ").append(note.categoryType.rawValue).append('\n')
        if (!note.targetName.isNullOrEmpty()) fm.append("target: \"").append(escapeYaml(note.targetName)).append("\"\n")
        fm.append("created_at: ").append(formatDate(note.createdAt)).append('\n')
        fm.append("updated_at: ").append(formatDate(note.updatedAt)).append('\n')
        if (note.isPinned) fm.append("pinned: true\n")
        if (note.tags.isNotEmpty()) fm.append("tags: [").append(note.tags.joinToString(", ") { "\"$it\"" }).append("]\n")
        fm.append("---\n\n")
        return fm.toString() + note.content
    }

    /**
     * Splits `---` delimited frontmatter from the body without altering the body. Delimiters must be lines
     * of their own, so "---" in a title or the body is never mistaken for one. null without a complete block.
     */
    fun splitFrontmatter(raw: String): Pair<String, String>? {
        if (!raw.startsWith("---")) return null
        fun isDelimiter(line: String) = line.trimEnd('\r').trim(' ', '\t') == "---"

        var cursor = 0
        fun nextLine(): Pair<String, Int>? {
            if (cursor >= raw.length) return null
            val newline = raw.indexOf('\n', cursor)
            return if (newline < 0) raw.substring(cursor) to raw.length else raw.substring(cursor, newline) to newline + 1
        }

        val opening = nextLine() ?: return null
        if (!isDelimiter(opening.first)) return null
        cursor = opening.second
        val yamlStart = cursor
        while (true) {
            val line = nextLine() ?: return null
            if (isDelimiter(line.first)) {
                val yaml = raw.substring(yamlStart, cursor)
                var bodyStart = line.second
                // Serialize writes one blank line between the frontmatter and the body
                if (raw.startsWith("\r\n", bodyStart)) bodyStart += 2
                else if (bodyStart < raw.length && raw[bodyStart] == '\n') bodyStart += 1
                return yaml to raw.substring(bodyStart)
            }
            cursor = line.second
        }
    }

    fun escapeYaml(value: String): String = value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")

    fun unescapeYaml(value: String): String {
        val result = StringBuilder(value.length)
        var i = 0
        while (i < value.length) {
            val ch = value[i]
            if (ch != '\\' || i + 1 >= value.length) {
                result.append(ch)
                i++
                continue
            }
            when (val escaped = value[i + 1]) {
                'n' -> result.append('\n')
                'r' -> result.append('\r')
                '"', '\\' -> result.append(escaped)
                // Not an escape the apps write: keep it, e.g. files edited by hand
                else -> result.append(ch).append(escaped)
            }
            i += 2
        }
        return result.toString()
    }

    /** Parses a note file. Dates missing from the frontmatter fall back to [fileModified], then to now. */
    fun parse(raw: String, filePath: String? = null, fileModified: Instant? = null): Note {
        var id = UUID.randomUUID()
        var title = ""
        var category = CategoryType.INBOX
        var target: String? = null
        var created: Instant? = null
        var updated: Instant? = null
        var tags = emptyList<String>()
        var pinned = false
        var body = raw

        splitFrontmatter(raw)?.let { (yaml, rest) ->
            body = rest
            // Split on "\n" only: titles may hold other Unicode line separators
            for (line in yaml.split('\n')) {
                val colon = line.indexOf(':')
                if (colon < 0) continue
                val key = line.substring(0, colon).trim()
                var value = line.substring(colon + 1).trim()
                if (key.isEmpty()) continue
                if (value.length >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
                    value = unescapeYaml(value.substring(1, value.length - 1))
                }
                when (key) {
                    "id" -> if (uuidPattern.matches(value)) id = UUID.fromString(value)
                    "title" -> title = value
                    "type" -> CategoryType.fromRawValue(value)?.let { category = it }
                    "target" -> target = value
                    "pinned" -> pinned = value.equals("true", ignoreCase = true)
                    "created_at" -> created = parseDate(value) ?: created
                    "updated_at" -> updated = parseDate(value) ?: updated
                    "tags" -> tags = value.trim('[', ']').split(',')
                        .map { it.trim(' ', '\t').trim('"') }
                        .filter { it.isNotEmpty() }
                }
            }
        }

        val now = Instant.now()
        val note = Note(
            id = id,
            title = title,
            content = body,
            categoryType = category,
            targetName = target,
            createdAt = created ?: fileModified ?: now,
            updatedAt = updated ?: fileModified ?: now,
            tags = tags,
            filePath = filePath,
            isPinned = pinned,
        )
        return if (note.title.isEmpty()) note.copy(title = note.displayTitle) else note
    }
}
