package com.scatterednotes.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.scatterednotes.core.Note
import com.scatterednotes.core.NoteSearch
import java.time.Duration
import java.time.Instant
import java.util.UUID

/** Every note, pinned first then newest, with search over titles, text and tags. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotesScreen(model: AppViewModel, state: NotesState, onOpenNote: (UUID) -> Unit, modifier: Modifier = Modifier) {
    var query by rememberSaveable { mutableStateOf("") }
    val results = if (query.isBlank()) state.notes.map { it to null } else NoteSearch.search(query, state.notes).map { it.note to it.snippet }

    Box(modifier.fillMaxSize()) {
        PullToRefreshBox(isRefreshing = false, onRefresh = model::reload) {
            LazyColumn(contentPadding = PaddingValues(16.dp, 16.dp, 16.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                item {
                    Text("Notes", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                }
                item {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        placeholder = { Text("Search all notes") },
                        leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (state.loaded && results.isEmpty()) {
                    item {
                        Text(
                            if (query.isBlank()) "No notes yet. Tap + to write one." else "No notes match.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 24.dp),
                        )
                    }
                }
                items(results, key = { it.first.id }) { (note, snippet) ->
                    NoteRow(note, snippet, onClick = { onOpenNote(note.id) })
                }
            }
        }
        FloatingActionButton(
            onClick = { model.newNote(onOpenNote) },
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
        ) {
            Icon(Icons.Outlined.Add, contentDescription = "New Note")
        }
    }
}

@Composable
private fun NoteRow(note: Note, snippet: String?, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (note.isPinned) {
                    Icon(Icons.Outlined.PushPin, contentDescription = "Pinned", modifier = Modifier.size(16.dp).padding(end = 4.dp))
                }
                Text(note.displayTitle, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            val preview = snippet ?: note.previewExcerpt
            if (preview.isNotEmpty()) {
                Text(
                    preview,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                "${note.destinationDisplay} · ${relative(note.updatedAt)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

private fun relative(instant: Instant): String {
    val minutes = Duration.between(instant, Instant.now()).toMinutes()
    return when {
        minutes < 1 -> "just now"
        minutes < 60 -> "$minutes min ago"
        minutes < 60 * 24 -> "${minutes / 60} h ago"
        minutes < 60 * 24 * 7 -> "${minutes / (60 * 24)} d ago"
        else -> java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy").format(instant.atZone(java.time.ZoneId.systemDefault()))
    }
}
