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
}
