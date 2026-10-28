package com.scatterednotes.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.scatterednotes.core.CategoryType
import com.scatterednotes.core.ProjectArea

/** Write a thought down fast and file it in the Inbox, a project or an area. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CaptureSheet(model: AppViewModel, state: NotesState, initialText: String, onDismiss: () -> Unit) {
    var text by rememberSaveable { mutableStateOf(initialText) }
    var destination by remember { mutableStateOf<ProjectArea?>(null) }
    var choosing by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Quick Capture", style = MaterialTheme.typography.titleLarge)
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                placeholder = { Text("Lines like \"call the bank tomorrow\" or \"- [ ] renew passport\" show up on the Dashboard.") },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                modifier = Modifier.fillMaxWidth().heightIn(min = 160.dp).focusRequester(focus),
            )
            ExposedDropdownMenuBox(expanded = choosing, onExpandedChange = { choosing = it }) {
                OutlinedTextField(
                    value = destination?.name ?: "Inbox",
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Save to") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = choosing) },
                    modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
                )
                ExposedDropdownMenu(expanded = choosing, onDismissRequest = { choosing = false }) {
                    DropdownMenuItem(text = { Text("Inbox") }, onClick = { destination = null; choosing = false })
                    (state.projects + state.areas).forEach { place ->
                        DropdownMenuItem(
                            text = { Text("${place.name} (${if (place.type == CategoryType.PROJECT) "project" else "area"})") },
                            onClick = { destination = place; choosing = false },
                        )
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Button(
                    enabled = text.isNotBlank(),
                    onClick = {
                        val trimmed = text.trim()
                        // Words starting with # become tags, as in the Mac Quick Capture
                        val tags = trimmed.split(Regex("\\s+"))
                            .filter { it.startsWith("#") && it.length > 1 }
                            .map { it.drop(1).trim { ch -> !ch.isLetterOrDigit() } }
                            .filter { it.isNotEmpty() }
                        model.capture(trimmed, destination?.type ?: CategoryType.INBOX, destination?.name, tags)
                        onDismiss()
                    },
                ) { Text("Save") }
            }
        }
    }
    LaunchedEffect(Unit) { focus.requestFocus() }
}
