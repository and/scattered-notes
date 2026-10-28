package com.scatterednotes.ui

import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.scatterednotes.core.AgendaItem
import com.scatterednotes.core.CategoryType
import com.scatterednotes.core.Note
import com.scatterednotes.core.ProjectArea
import com.scatterednotes.storage.LocalFolder
import com.scatterednotes.storage.NoteFolder
import com.scatterednotes.storage.NoteStore
import com.scatterednotes.storage.TreeFolder
import com.scatterednotes.update.Updater
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

/** Everything the screens show, read from the store after each change. */
data class NotesState(
    val notes: List<Note> = emptyList(),
    val projects: List<ProjectArea> = emptyList(),
    val agenda: List<AgendaItem> = emptyList(),
    val loaded: Boolean = false,
)

/**
 * Owns the note store and runs every file operation on one background thread, in order, so the UI never
 * waits on storage and two writes never overlap.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = application.getSharedPreferences("settings", Context.MODE_PRIVATE)
    private val io = Dispatchers.IO.limitedParallelism(1)
    private lateinit var store: NoteStore

    private val _state = MutableStateFlow(NotesState())
    val state: StateFlow<NotesState> = _state.asStateFlow()

    /** Updates from GitHub; does nothing in the Google Play build */
    val updater = Updater(application, viewModelScope)

    private val _folderName = MutableStateFlow<String?>(null)
    /** Name of the picked folder, or null when notes are kept in the app's own storage. */
    val folderName: StateFlow<String?> = _folderName.asStateFlow()

    init {
        openFolder()
    }

    private fun pickedTree(): Uri? = prefs.getString(KEY_TREE, null)?.let(Uri::parse)

    private fun openFolder() {
        val app = getApplication<Application>()
        val tree = pickedTree()?.takeIf { uri ->
            // The permission is gone if the user revoked it or the folder's app was removed
            app.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission }
        }
        val root: NoteFolder = if (tree != null) {
            _folderName.value = Uri.decode(tree.lastPathSegment ?: "").substringAfterLast(':').substringAfterLast('/')
            TreeFolder.root(app.contentResolver, tree)
        } else {
            _folderName.value = null
            LocalFolder(File(app.filesDir, "ScatteredNotes"))
        }
        store = NoteStore(root)
        reload()
    }

    private fun publish() {
        _state.value = NotesState(store.notes, store.projects, store.agendaItems(), loaded = true)
    }

    private fun onStore(action: NoteStore.() -> Unit) {
        viewModelScope.launch(io) {
            store.action()
            publish()
        }
    }

    /** Re-reads the folder, picking up notes changed on other devices. */
    fun reload() = onStore { loadAll() }

    fun save(note: Note) = onStore { save(note) }

    fun delete(note: Note) = onStore { delete(note) }

    fun togglePin(note: Note) = onStore { togglePin(note) }

    fun toggle(item: AgendaItem) = onStore { toggleChecklistItem(item.noteId, item.lineIndex) }

    fun capture(text: String, category: CategoryType, targetName: String?, tags: List<String>) =
        onStore { createNote(content = text, category = category, targetName = targetName, tags = tags) }

    /** Creates a note from what was typed in a new note and hands its ID back once it exists. */
    fun createNote(title: String, content: String, onCreated: (UUID) -> Unit) {
        viewModelScope.launch(io) {
            val note = store.createNote(title = title, content = content)
            publish()
            launch(Dispatchers.Main) { onCreated(note.id) }
        }
    }

    fun useFolder(tree: Uri) {
        val resolver = getApplication<Application>().contentResolver
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        resolver.takePersistableUriPermission(tree, flags)
        pickedTree()?.takeIf { it != tree }?.let { old ->
            runCatching { resolver.releasePersistableUriPermission(old, flags) }
        }
        prefs.edit().putString(KEY_TREE, tree.toString()).apply()
        viewModelScope.launch(io) { openFolder() }
    }

    fun useAppFolder() {
        prefs.edit().remove(KEY_TREE).apply()
        viewModelScope.launch(io) { openFolder() }
    }

    private companion object {
        const val KEY_TREE = "notesFolderTree"
    }
}
