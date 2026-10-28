package com.scatterednotes.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import java.util.UUID

/** Plain Markdown editing of one note. Changes are saved a moment after typing stops and when leaving. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(model: AppViewModel, state: NotesState, noteId: UUID, onClose: () -> Unit) {
    val note = state.notes.firstOrNull { it.id == noteId }
    var title by rememberSaveable(noteId) { mutableStateOf<String?>(null) }
    var content by rememberSaveable(noteId) { mutableStateOf<String?>(null) }
    var confirmingDelete by rememberSaveable { mutableStateOf(false) }
    val focus = androidx.compose.runtime.remember { FocusRequester() }

    // Fill the fields once, when the note is first available
    if (note != null && title == null) {
        title = note.title
        content = note.content
    }

    val save: () -> Unit = save@{
        val current = state.notes.firstOrNull { it.id == noteId } ?: return@save
        val newTitle = title ?: return@save
        val newContent = content ?: return@save
        // A note created here and left empty is dropped rather than kept as a blank file
        if (newTitle.isBlank() && newContent.isBlank()) model.delete(current)
        else model.save(current.copy(title = newTitle, content = newContent))
    }
    val latestSave by rememberUpdatedState(save)

    LaunchedEffect(title, content) {
        delay(800)
        latestSave()
    }
    DisposableEffect(noteId) { onDispose { latestSave() } }
    LaunchedEffect(noteId, note != null) {
        if (note != null && note.content.isEmpty()) focus.requestFocus()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(note?.destinationDisplay ?: "") },
                navigationIcon = {
                    IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back") }
                },
                actions = {
                    if (note != null) {
                        IconButton(onClick = { model.togglePin(note) }) {
                            Icon(
                                Icons.Outlined.PushPin,
                                contentDescription = if (note.isPinned) "Unpin" else "Pin",
                                tint = if (note.isPinned) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        IconButton(onClick = { confirmingDelete = true }) {
                            Icon(Icons.Outlined.Delete, contentDescription = "Delete Note")
                        }
                    }
                },
            )
        },
    ) { padding ->
        if (note == null) {
            Text(
                if (state.loaded) "This note was deleted, maybe on another device." else "",
                modifier = Modifier.padding(padding).padding(16.dp),
            )
            return@Scaffold
        }
        val colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent,
            unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        )
        Column(Modifier.padding(padding).imePadding().fillMaxSize()) {
            TextField(
                value = title ?: "",
                onValueChange = { title = it },
                placeholder = { Text("Title") },
                textStyle = MaterialTheme.typography.titleLarge,
                singleLine = true,
                colors = colors,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                modifier = Modifier.fillMaxWidth(),
            )
            TextField(
                value = content ?: "",
                onValueChange = { content = it },
                placeholder = { Text("Write anything. \"call the bank tomorrow\" shows up on the Dashboard.") },
                textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                colors = colors,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                modifier = Modifier.fillMaxSize().focusRequester(focus),
            )
        }
    }

    if (confirmingDelete && note != null) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text("Delete this note?") },
            confirmButton = {
                TextButton(onClick = {
                    confirmingDelete = false
                    // Stop the pending save from writing the note back
                    title = null
                    content = null
                    model.delete(note)
                    onClose()
                }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { confirmingDelete = false }) { Text("Cancel") } },
        )
    }
}
