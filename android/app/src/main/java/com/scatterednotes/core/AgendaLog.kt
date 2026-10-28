package com.scatterednotes.core

import org.json.JSONException
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.UUID

/**
 * Remembers when each to-do or dated line of a note first appeared, so relative words such as "tomorrow"
 * keep the day they were written for, however much the note is edited later.
 *
 * Stored as `.agenda-log.json` in the notes folder, in the same format as the Mac and Windows apps:
 * `{ "notes": { "<note id>": { "<line key>": { "line": "...", "firstSeen": "2026-10-27T06:55:00Z" } } } }`.
 * It is derived data: if it is missing or corrupt it is rebuilt, and notes are never affected.
 */
class AgendaLog(val notes: MutableMap<String, MutableMap<String, Entry>> = mutableMapOf()) {
    data class Entry(val line: String, val firstSeen: Instant)

    fun anchors(noteId: UUID): Map<String, Instant> =
        notes[Note.formatId(noteId)]?.mapValues { it.value.firstSeen } ?: emptyMap()

    /**
     * Syncs a note's entries with its current lines. New lines are stamped [seenAt], existing ones keep
     * their date, and lines no longer present are dropped. Returns whether the log changed.
     */
    fun update(noteId: UUID, lines: List<Pair<String, String>>, seenAt: Instant): Boolean {
        val id = Note.formatId(noteId)
        val entries = notes[id]?.toMutableMap() ?: mutableMapOf()
        val keys = lines.map { it.first }.toSet()
        var changed = entries.keys.retainAll(keys)
        // The Mac app decodes dates with Swift's .iso8601 strategy, which rejects fractional seconds
        val stamp = seenAt.truncatedTo(ChronoUnit.SECONDS)
        for ((key, line) in lines) {
            if (key in entries) continue
            entries[key] = Entry(line, stamp)
            changed = true
        }
        if (entries.isEmpty()) return notes.remove(id) != null
        notes[id] = entries
        return changed
    }

    fun remove(noteId: UUID): Boolean = notes.remove(Note.formatId(noteId)) != null

    /** Folds in a copy of the log made by a sync conflict, keeping the earliest first-seen date of each line. */
    fun merge(other: AgendaLog) {
        for ((id, entries) in other.notes) {
            val mine = notes.getOrPut(id) { mutableMapOf() }
            for ((key, entry) in entries) {
                val existing = mine[key]
                if (existing == null || entry.firstSeen < existing.firstSeen) mine[key] = entry
            }
        }
    }

    /** Sorted keys, so the file only changes when its content does. */
    fun encode(): String {
        val root = StringBuilder("{\n  \"notes\" : {")
        notes.keys.sorted().forEachIndexed { i, id ->
            root.append(if (i == 0) "\n" else ",\n").append("    ").append(JSONObject.quote(id)).append(" : {")
            val entries = notes.getValue(id)
            entries.keys.sorted().forEachIndexed { j, key ->
                val entry = entries.getValue(key)
                root.append(if (j == 0) "\n" else ",\n")
                    .append("      ").append(JSONObject.quote(key)).append(" : {\n")
                    .append("        \"firstSeen\" : ").append(JSONObject.quote(dateFormat.format(entry.firstSeen))).append(",\n")
                    .append("        \"line\" : ").append(JSONObject.quote(entry.line)).append("\n")
                    .append("      }")
            }
            root.append(if (entries.isEmpty()) "}" else "\n    }")
        }
        root.append(if (notes.isEmpty()) "}\n}" else "\n  }\n}")
        return root.toString()
    }

    companion object {
        const val FILE_NAME = ".agenda-log.json"
        private val dateFormat = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)

        /** null for any unreadable log, which is then rebuilt from the notes. */
        fun decode(text: String): AgendaLog? = try {
            val root = JSONObject(text).getJSONObject("notes")
            val log = AgendaLog()
            for (id in root.keys()) {
                val entries = root.getJSONObject(id)
                val map = mutableMapOf<String, Entry>()
                for (key in entries.keys()) {
                    val entry = entries.getJSONObject(key)
                    val firstSeen = NoteFormat.parseDate(entry.getString("firstSeen")) ?: return null
                    map[key] = Entry(entry.getString("line"), firstSeen)
                }
                // Keys are compared as the Mac app writes them
                log.notes[id.uppercase()] = map
            }
            log
        } catch (_: JSONException) {
            null
        }
    }
}
