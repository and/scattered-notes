package com.scatterednotes.storage

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.time.Instant

/** A file in a [NoteFolder], with what the store needs to know about it without reading it. */
data class FileEntry(val name: String, val modified: Instant?, val size: Long)

/**
 * A folder of the notes tree. Notes live either in the app's own storage ([LocalFolder]) or in a folder the
 * user picked with the system picker ([TreeFolder]), such as one a sync app keeps in step with the Mac.
 */
interface NoteFolder {
    val name: String
    fun folders(): List<NoteFolder>
    fun files(): List<FileEntry>
    fun folder(name: String, create: Boolean): NoteFolder?
    fun read(name: String): String?
    /** Replaces or creates the file. Throws [IOException] when it cannot be written. */
    fun write(name: String, text: String)
    fun delete(name: String): Boolean
}

class LocalFolder(private val dir: File) : NoteFolder {
    override val name: String get() = dir.name

    override fun folders(): List<NoteFolder> =
        dir.listFiles()?.filter { it.isDirectory && !it.name.startsWith(".") }?.map { LocalFolder(it) } ?: emptyList()

    override fun files(): List<FileEntry> =
        dir.listFiles()?.filter { it.isFile }?.map { FileEntry(it.name, Instant.ofEpochMilli(it.lastModified()), it.length()) }
            ?: emptyList()

    override fun folder(name: String, create: Boolean): NoteFolder? {
        val child = File(dir, name)
        if (!child.isDirectory && !(create && child.mkdirs())) return null
        return LocalFolder(child)
    }

    override fun read(name: String): String? = try {
        File(dir, name).readText()
    } catch (_: IOException) {
        null
    }

    /** Writes to a temporary file first, so a crash leaves the old note or the new one, never half of one. */
    override fun write(name: String, text: String) {
        dir.mkdirs()
        val temp = File(dir, ".$name.${System.nanoTime()}.tmp")
        try {
            temp.outputStream().use { stream ->
                stream.write(text.toByteArray())
                stream.fd.sync()
            }
            if (!temp.renameTo(File(dir, name))) throw IOException("Could not replace $name")
        } finally {
            temp.delete()
        }
    }

    override fun delete(name: String): Boolean = File(dir, name).delete()
}

/** A folder reached through the Storage Access Framework, identified by its document ID within a granted tree. */
class TreeFolder(
    private val resolver: ContentResolver,
    private val treeUri: Uri,
    private val documentId: String,
    override val name: String,
) : NoteFolder {
    private data class Child(val id: String, val name: String, val isFolder: Boolean, val modified: Instant?, val size: Long)

    private fun children(): List<Child> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        val result = mutableListOf<Child>()
        resolver.query(uri, columns, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(1) ?: ""
                if (name.isEmpty()) continue
                result.add(
                    Child(
                        id = cursor.getString(0),
                        name = name,
                        isFolder = cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR,
                        modified = if (cursor.isNull(3)) null else Instant.ofEpochMilli(cursor.getLong(3)),
                        size = if (cursor.isNull(4)) -1 else cursor.getLong(4),
                    )
                )
            }
        }
        return result
    }

    private fun child(name: String) = children().firstOrNull { it.name == name }

    private fun uriOf(id: String) = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)

    override fun folders(): List<NoteFolder> =
        children().filter { it.isFolder && !it.name.startsWith(".") }.map { TreeFolder(resolver, treeUri, it.id, it.name) }

    override fun files(): List<FileEntry> =
        children().filter { !it.isFolder }.map { FileEntry(it.name, it.modified, it.size) }

    override fun folder(name: String, create: Boolean): NoteFolder? {
        child(name)?.let { return if (it.isFolder) TreeFolder(resolver, treeUri, it.id, it.name) else null }
        if (!create) return null
        val created = DocumentsContract.createDocument(resolver, uriOf(documentId), DocumentsContract.Document.MIME_TYPE_DIR, name)
            ?: return null
        return TreeFolder(resolver, treeUri, DocumentsContract.getDocumentId(created), name)
    }

    override fun read(name: String): String? {
        val file = child(name) ?: return null
        return try {
            resolver.openInputStream(uriOf(file.id))?.use { it.readBytes().decodeToString() }
        } catch (_: IOException) {
            null
        }
    }

    override fun write(name: String, text: String) {
        val uri = child(name)?.let { uriOf(it.id) }
            // octet-stream keeps the name exactly as given; a text type could make the provider add an extension
            ?: DocumentsContract.createDocument(resolver, uriOf(documentId), "application/octet-stream", name)
            ?: throw IOException("Could not create $name")
        try {
            // "wt" truncates, so a shorter note leaves no tail of the old one
            resolver.openOutputStream(uri, "wt")?.use { it.write(text.toByteArray()) } ?: throw IOException("Could not open $name")
        } catch (e: FileNotFoundException) {
            throw IOException(e)
        }
    }

    override fun delete(name: String): Boolean {
        val file = child(name) ?: return false
        return try {
            DocumentsContract.deleteDocument(resolver, uriOf(file.id))
        } catch (_: FileNotFoundException) {
            false
        }
    }

    companion object {
        fun root(resolver: ContentResolver, treeUri: Uri): TreeFolder =
            TreeFolder(resolver, treeUri, DocumentsContract.getTreeDocumentId(treeUri), "Notes")
    }
}
