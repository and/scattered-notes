package com.scatterednotes.storage

import com.scatterednotes.core.CategoryType
import com.scatterednotes.core.Note
import com.scatterednotes.core.NoteFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class NoteStoreTests {
    @Test
    fun notesLeftInAreasMoveToTheInboxAsTags() {
        val root = Files.createTempDirectory("sn-store").toFile()
        try {
            val area = File(root, "Areas/Home Office").apply { mkdirs() }
            val desk = Note(title = "Desk", content = "Buy a lamp\n", categoryType = CategoryType.AREA, targetName = "Home Office")
            File(area, "desk.md").writeText(NoteFormat.serialize(desk))

            val store = NoteStore(LocalFolder(root))
            store.loadAll()

            val moved = store.notes.single()
            assertEquals(desk.id, moved.id)
            assertEquals(CategoryType.INBOX, moved.categoryType)
            assertEquals("Buy a lamp\n\n#home-office", moved.content)
            assertEquals(listOf("home-office"), moved.tags)
            assertTrue(File(root, "Inbox").listFiles()!!.any { it.name.endsWith(".md") })
            assertTrue(area.listFiles()!!.none { it.name.endsWith(".md") })
            assertTrue("no new Areas folder is made", !File(root, "Areas/General").exists())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun savingWritesDaysIntoTheNotesOwnFileAndOpeningNeverRewritesIt() {
        val root = Files.createTempDirectory("sn-store").toFile()
        try {
            val store = NoteStore(LocalFolder(root))
            store.loadAll()
            val note = store.createNote("Errands", "Buy tomatoes today")
            store.save(note.copy(content = note.content + "\nCall bank tomorrow"))
            val file = File(root, store.notes.single().filePath!!)
            val saved = file.readText()
            assertTrue(saved, saved.contains("Call bank tomorrow 📅 "))
            assertTrue(saved, !saved.contains("seen:"))
            assertTrue(!File(root, ".agenda-log.json").exists())
            val items = store.agendaItems(store.notes.single())
            assertEquals(items[0].date!!.plusDays(1), items[1].date)

            // A note written elsewhere has no markers; loading leaves it alone
            val outside = "---\nid: ${note.idString}\ntitle: Errands\n---\n\nbuy tomatoes today\n- [x] call bank tomorrow\n"
            file.writeText(outside)
            val reloaded = NoteStore(LocalFolder(root)).also { it.loadAll() }
            assertEquals(2, reloaded.agendaItems(reloaded.notes.single()).size)
            assertEquals(outside, file.readText())
        } finally {
            root.deleteRecursively()
        }
    }
}
