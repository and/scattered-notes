package com.scatterednotes.storage

import com.scatterednotes.core.AgendaExtractor
import com.scatterednotes.core.AgendaItem
import com.scatterednotes.core.CategoryType
import com.scatterednotes.core.Checklist
import com.scatterednotes.core.FileNames
import com.scatterednotes.core.Mentions
import com.scatterednotes.core.Note
import com.scatterednotes.core.NoteFormat
import com.scatterednotes.core.ProjectArea
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * Reads and writes the notes folder, in the layout the Mac and Windows apps use: Inbox and Projects/<name>,
 * plus the agenda log. Call it from one thread at a time.
 *
 * Areas (Areas/<name>) were replaced by tags: a note still in an area, written by an older version, moves to
 * the Inbox tagged with the area's name. The Mac app removes the emptied area folders.
 *
 * Data safety rules: a moved note's new file is written before the old one is removed; loading never writes a
 * note file; files that cannot be read are left alone.
 */
class NoteStore(private val root: NoteFolder, private val zone: ZoneId = ZoneId.systemDefault()) {
    var notes: List<Note> = emptyList()
        private set
    var projects: List<ProjectArea> = emptyList()
        private set

    /** Parsed notes by path, reused while a file's modification time and size are unchanged. */
    private data class CachedFile(val modified: Instant?, val size: Long, val note: Note)
    private val fileCache = mutableMapOf<String, CachedFile>()

    /** Agenda items per note, valid while the note's text, creation time and stamps are unchanged. */
    private data class CachedAgenda(val content: String, val updatedAt: Instant, val items: List<AgendaItem>)
    private val agendaCache = mutableMapOf<UUID, CachedAgenda>()

    private fun folder(path: List<String>, create: Boolean): NoteFolder? =
        path.fold(root as NoteFolder?) { parent, name -> parent?.folder(name, create) }

    private fun directory(category: CategoryType, targetName: String?): List<String> {
        val name = targetName?.trim()?.takeIf { it.isNotEmpty() } ?: "General"
        return when (category) {
            CategoryType.PROJECT -> listOf("Projects", name)
            CategoryType.AREA -> listOf("Areas", name)
            CategoryType.INBOX -> listOf("Inbox")
        }
    }

    fun loadAll() {
        val inbox = folder(listOf("Inbox"), create = true)
        val projectsDir = folder(listOf("Projects"), create = true)
        val areasDir = folder(listOf("Areas"), create = false)
        projects = projectsDir?.folders()?.map { ProjectArea(it.name, CategoryType.PROJECT) }?.sortedBy { it.name.lowercase() } ?: emptyList()

        val loaded = mutableListOf<Note>()
        inbox?.let { loaded += loadNotes(it, listOf("Inbox"), CategoryType.INBOX, null) }
        projectsDir?.folders()?.forEach { loaded += loadNotes(it, listOf("Projects", it.name), CategoryType.PROJECT, it.name) }
        areasDir?.folders()?.forEach { loaded += loadNotes(it, listOf("Areas", it.name), CategoryType.AREA, it.name) }

        val loadedPaths = loaded.mapNotNull { it.filePath }.toSet()
        fileCache.keys.retainAll(loadedPaths)

        // A crash while moving a note can leave its file in two folders. Show the newest copy and leave the
        // other file on disk untouched
        val newest = mutableMapOf<UUID, Note>()
        for (note in loaded) {
            val seen = newest[note.id]
            if (seen == null || seen.updatedAt <= note.updatedAt) newest[note.id] = note
        }
        val unique = loaded.filter { newest[it.id]?.filePath == it.filePath }

        agendaCache.keys.retainAll(unique.map { it.id }.toSet())

        notes = sorted(unique)
        moveAreaNotesToInbox()
    }

    /** Moves each note still in an area to the Inbox, tagged with the area's name; see the class comment. */
    private fun moveAreaNotesToInbox() {
        for (note in notes.filter { it.categoryType == CategoryType.AREA }) {
            val tag = Mentions.tagNameForArea(note.targetName ?: "")
            val hasTag = Mentions.names(Mentions.Kind.TAG, note.content).any { it.equals(tag, ignoreCase = true) }
            val body = note.content.trim('\n', '\r')
            val content = when {
                hasTag -> note.content
                body.isEmpty() -> "#$tag"
                else -> "$body\n\n#$tag"
            }
            save(note.copy(content = content, categoryType = CategoryType.INBOX, targetName = null,
                tags = Mentions.names(Mentions.Kind.TAG, content)))
        }
    }

    private fun loadNotes(dir: NoteFolder, path: List<String>, category: CategoryType, targetName: String?): List<Note> =
        dir.files()
            .filter { it.name.endsWith(".md", ignoreCase = true) && !it.name.startsWith(".") }
            .mapNotNull { file ->
                val filePath = (path + file.name).joinToString("/")
                val cached = fileCache[filePath]
                val note = if (cached != null && cached.modified == file.modified && cached.size == file.size) {
                    cached.note
                } else {
                    val raw = dir.read(file.name) ?: return@mapNotNull null
                    NoteFormat.parse(raw, filePath, file.modified).also {
                        fileCache[filePath] = CachedFile(file.modified, file.size, it)
                    }
                }
                // Frontmatter without a destination takes it from the folder
                if (note.categoryType == CategoryType.INBOX && category != CategoryType.INBOX) {
                    note.copy(categoryType = category, targetName = targetName)
                } else {
                    note
                }
            }

    fun createNote(
        title: String = "",
        content: String = "",
        category: CategoryType = CategoryType.INBOX,
        targetName: String? = null,
        tags: List<String> = emptyList(),
    ): Note {
        val now = Instant.now()
        val note = Note(title = title, content = content, categoryType = category, targetName = targetName,
            createdAt = now, updatedAt = now, tags = tags)
        save(note)
        return notes.firstOrNull { it.id == note.id } ?: note
    }

    /** Writes the note and updates [notes]. Returns false when the file could not be written. */
    fun save(note: Note): Boolean {
        val existing = notes.firstOrNull { it.id == note.id }
        if (existing != null && existing.hasSameContent(note) && note.filePath != null) return true

        val target = if (note.categoryType == CategoryType.INBOX || note.targetName.isNullOrBlank()) note.targetName
        else FileNames.sanitizeFolderName(note.targetName).ifEmpty { null }
        var updated = note.copy(updatedAt = Instant.now(), targetName = target)
        updated = updated.copy(
            content = AgendaExtractor.resolvingDates(updated.content, existing?.content, existing?.updatedAt, updated.updatedAt, zone),
        )
        val destination = directory(updated.categoryType, updated.targetName)
        val dir = folder(destination, create = true) ?: return false

        var stale: String? = null
        val currentDir = updated.filePath?.substringBeforeLast('/', "")
        val fileName: String
        if (updated.filePath != null && currentDir == destination.joinToString("/")) {
            fileName = updated.filePath!!.substringAfterLast('/')
        } else {
            // Moved to another folder, or new. The old file goes only after the new one is safely written,
            // so a failure in between leaves a duplicate, never a lost note
            stale = updated.filePath
            fileName = uniqueFileName(updated, dir) ?: return false
            updated = updated.copy(filePath = (destination + fileName).joinToString("/"))
        }

        try {
            dir.write(fileName, NoteFormat.serialize(updated))
        } catch (_: IOException) {
            return false
        } catch (_: SecurityException) {
            // The picked folder's permission was revoked
            return false
        }
        if (stale != null && stale != updated.filePath) {
            folder(stale.split('/').dropLast(1), create = false)?.delete(stale.substringAfterLast('/'))
        }

        notes = sorted(notes.filter { it.id != updated.id } + updated)
        return true
    }

    fun delete(note: Note) {
        note.filePath?.let { path -> folder(path.split('/').dropLast(1), create = false)?.delete(path.substringAfterLast('/')) }
        notes = notes.filter { it.id != note.id }
        agendaCache.remove(note.id)
    }

    fun togglePin(note: Note): Boolean = save(note.copy(isPinned = !note.isPinned))

    fun toggleChecklistItem(noteId: UUID, lineIndex: Int) {
        val note = notes.firstOrNull { it.id == noteId } ?: return
        save(note.copy(content = Checklist.toggleLine(lineIndex, note.content)))
    }

    /** To-dos and dated lines from every note, dated from when each line was written. */
    fun agendaItems(): List<AgendaItem> = notes.flatMap { agendaItems(it) }

    /** To-dos and dated lines of one note, dated from when each line was written. */
    fun agendaItems(note: Note): List<AgendaItem> {
        agendaCache[note.id]?.let {
            if (it.content == note.content && it.updatedAt == note.updatedAt) return it.items
        }
        val items = AgendaExtractor.items(note, zone)
        agendaCache[note.id] = CachedAgenda(note.content, note.updatedAt, items)
        return items
    }

    /** A file name no other note uses: clashing titles get 6 characters of the ID, then the whole ID. */
    private fun uniqueFileName(note: Note, dir: NoteFolder): String? {
        val taken = dir.files().map { it.name }.toSet()
        return listOf(0, 6, 36).map { FileNames.noteFileName(note, it, zone) }.firstOrNull { it !in taken }
    }

    private fun sorted(list: List<Note>) =
        list.sortedWith(compareByDescending<Note> { it.isPinned }.thenByDescending { it.updatedAt })
}
