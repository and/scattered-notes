package com.scatterednotes.storage

import android.content.Context
import android.net.Uri
import java.io.File

/**
 * The notes folder the app uses: the folder picked in Settings while the app may still read and write it,
 * otherwise the app's own folder. Used by the screens and by the morning notification, which reads the
 * notes without the app open.
 */
object AppFolder {
    const val PREFS = "settings"
    const val KEY_TREE = "notesFolderTree"

    /** The folder, and the name to show for it (null for the app's own folder) */
    fun open(context: Context): Pair<NoteFolder, String?> {
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val tree = prefs.getString(KEY_TREE, null)?.let(Uri::parse)?.takeIf { uri ->
            // The permission is gone if the user revoked it or the folder's app was removed
            app.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission }
        }
        return if (tree != null) {
            val name = Uri.decode(tree.lastPathSegment ?: "").substringAfterLast(':').substringAfterLast('/')
            TreeFolder.root(app.contentResolver, tree) to name
        } else {
            LocalFolder(File(app.filesDir, "ScatteredNotes")) to null
        }
    }
}
