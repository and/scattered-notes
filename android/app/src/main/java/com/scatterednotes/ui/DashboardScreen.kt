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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.scatterednotes.core.AgendaItem
import com.scatterednotes.core.Dashboard
import java.time.LocalDate
import java.util.UUID

/** Overdue, today, the next 14 days and open to-dos from every note, as on the Mac and Windows Dashboard. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    model: AppViewModel,
    state: NotesState,
    onOpenNote: (UUID) -> Unit,
    onCapture: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val today = LocalDate.now()
    val dashboard = Dashboard.build(state.notes, state.agenda, today)
    // Everything ticked earlier starts folded away
    var completedExpanded by rememberSaveable { mutableStateOf(false) }

    Box(modifier.fillMaxSize()) {
        PullToRefreshBox(isRefreshing = false, onRefresh = model::reload) {
            LazyColumn(contentPadding = PaddingValues(16.dp, 16.dp, 16.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                item {
                    Text("Dashboard", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                }
                if (!dashboard.isEmpty) item { Counters(dashboard) }
                if (state.loaded && dashboard.isEmpty) {
                    item {
                        Text(
                            "Nothing planned. Write a to-do or a day in any note and it shows up here.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 24.dp),
                        )
                    }
                }
                section("Overdue", dashboard.overdue, dashboard, model, onOpenNote, showDate = true)
                section("Today", dashboard.dueToday, dashboard, model, onOpenNote)
                dashboard.upcoming.forEach { (day, items) ->
                    section(Dashboard.dayLabel(day, today), items, dashboard, model, onOpenNote)
                }
                dashboard.undatedTodos.forEach { (note, items) ->
                    section(note.displayTitle, items, dashboard, model, onOpenNote, showNote = false)
                }
                if (dashboard.completed.isNotEmpty()) {
                    item(key = "completed-header") {
                        Text(
                            (if (completedExpanded) "▾ " else "▸ ") + "Completed (${dashboard.completed.size})",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { completedExpanded = !completedExpanded }
                                .semantics { stateDescription = if (completedExpanded) "expanded" else "collapsed" }
                                .padding(top = 12.dp, start = 4.dp, bottom = 4.dp),
                        )
                    }
                    if (completedExpanded) {
                        items(dashboard.completed, key = { "completed-${it.id}" }) { item ->
                            val caption = listOfNotNull(
                                item.doneOn?.let { Dashboard.dayLabel(it, dashboard.today) } ?: "Earlier",
                                dashboard.notesById[item.noteId]?.displayTitle,
                            ).joinToString(" · ")
                            AgendaRow(item, caption, onToggle = { model.toggle(item) }, onOpen = { onOpenNote(item.noteId) })
                        }
                    }
                }
            }
        }
        FloatingActionButton(onClick = onCapture, modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp)) {
            Icon(Icons.Outlined.Edit, contentDescription = "Quick Capture")
        }
    }
}

private fun LazyListScope.section(
    title: String,
    items: List<AgendaItem>,
    dashboard: Dashboard,
    model: AppViewModel,
    onOpenNote: (UUID) -> Unit,
    showDate: Boolean = false,
    showNote: Boolean = true,
) {
    if (items.isEmpty()) return
    item(key = "header-$title-${items.first().id}") {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(top = 12.dp, start = 4.dp),
        )
    }
    items(items, key = { "$title-${it.id}" }) { item ->
        val note = dashboard.notesById[item.noteId]
        val caption = listOfNotNull(
            if (showDate) item.date?.let { Dashboard.dayLabel(it, dashboard.today) } else null,
            if (showNote) note?.displayTitle else null,
        ).joinToString(" · ")
        AgendaRow(item, caption, onToggle = { model.toggle(item) }, onOpen = { onOpenNote(item.noteId) })
    }
}

@Composable
private fun AgendaRow(item: AgendaItem, caption: String, onToggle: () -> Unit, onOpen: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(end = 16.dp, top = 4.dp, bottom = 4.dp)) {
            if (item.isTodo) {
                Checkbox(checked = item.isDone, onCheckedChange = { onToggle() })
            } else {
                Icon(
                    Icons.Outlined.Event,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(12.dp),
                )
            }
            Column(Modifier.padding(vertical = 8.dp)) {
                Text(
                    item.text,
                    textDecoration = if (item.isDone) TextDecoration.LineThrough else null,
                    color = if (item.isDone) MaterialTheme.colorScheme.onSurfaceVariant else Color.Unspecified,
                )
                if (caption.isNotEmpty()) {
                    Text(caption, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun Counters(dashboard: Dashboard) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        Counter("Overdue", dashboard.overdue.size, Color(0xFFE8710A), Modifier.weight(1f))
        Counter("Today", dashboard.dueToday.size, MaterialTheme.colorScheme.primary, Modifier.weight(1f))
        Counter("Upcoming", dashboard.upcomingCount, Color(0xFF8E44D9), Modifier.weight(1f))
        Counter("To-dos", dashboard.openTodoCount, Color(0xFF2E9E55), Modifier.weight(1f))
    }
}

@Composable
private fun Counter(title: String, value: Int, tint: Color, modifier: Modifier) {
    Card(modifier.clearAndSetSemantics { contentDescription = "$value $title" }) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
            Text(
                "$value",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = if (value > 0) tint else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
