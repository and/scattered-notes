package com.scatterednotes.ui

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import java.util.UUID

class MainActivity : ComponentActivity() {
    private val model: AppViewModel by viewModels()
    /** Text shared from another app, shown in Quick Capture */
    private val sharedText = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        sharedText.value = intent.sharedText()
        setContent {
            AppTheme {
                ScatteredNotesApp(model, sharedText.value, onSharedTextUsed = { sharedText.value = null })
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sharedText.value = intent.sharedText()
    }

    private fun Intent.sharedText(): String? =
        if (action == Intent.ACTION_SEND) getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() } else null
}

@Composable
private fun AppTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val colors = when {
        android.os.Build.VERSION.SDK_INT >= 31 -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> darkColorScheme(primary = Color(0xFFB4A8FF))
        else -> lightColorScheme(primary = Color(0xFF4B3DB8))
    }
    MaterialTheme(colorScheme = colors, content = content)
}

private enum class Tab(val title: String) { DASHBOARD("Dashboard"), NOTES("Notes"), SETTINGS("Settings") }

@Composable
fun ScatteredNotesApp(model: AppViewModel, sharedText: String?, onSharedTextUsed: () -> Unit) {
    val state by model.state.collectAsState()
    val folderName by model.folderName.collectAsState()
    var tab by rememberSaveable { mutableStateOf(Tab.DASHBOARD) }
    var openNote by rememberSaveable { mutableStateOf<String?>(null) }
    var capturing by rememberSaveable { mutableStateOf(false) }

    // No folder watcher on Android: pick up edits made on other devices whenever the app comes back
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        var first = true
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                if (!first) model.reload()
                first = false
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    val noteId = openNote?.let(UUID::fromString)
    if (noteId != null) {
        BackHandler { openNote = null }
        EditorScreen(model, state, noteId, onClose = { openNote = null })
        return
    }

    val open: (UUID) -> Unit = { openNote = it.toString() }
    Scaffold(
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = tab == item,
                        onClick = { tab = item },
                        icon = {
                            Icon(
                                when (item) {
                                    Tab.DASHBOARD -> Icons.Outlined.Dashboard
                                    Tab.NOTES -> Icons.AutoMirrored.Outlined.Notes
                                    Tab.SETTINGS -> Icons.Outlined.Settings
                                },
                                contentDescription = null,
                            )
                        },
                        label = { Text(item.title) },
                    )
                }
            }
        },
    ) { padding ->
        val modifier = Modifier.padding(padding)
        when (tab) {
            Tab.DASHBOARD -> DashboardScreen(model, state, onOpenNote = open, onCapture = { capturing = true }, modifier = modifier)
            Tab.NOTES -> NotesScreen(model, state, onOpenNote = open, modifier = modifier)
            Tab.SETTINGS -> SettingsScreen(model, folderName, modifier = modifier)
        }
    }

    if (capturing || sharedText != null) {
        CaptureSheet(
            model = model,
            state = state,
            initialText = sharedText ?: "",
            onDismiss = {
                capturing = false
                onSharedTextUsed()
            },
        )
    }
}
