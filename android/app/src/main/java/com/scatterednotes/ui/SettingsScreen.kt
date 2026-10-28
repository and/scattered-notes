package com.scatterednotes.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.scatterednotes.update.Updater

/** Where the notes live. Picking a folder a sync app keeps in step with the Mac or Windows PC shares the notes. */
@Composable
fun SettingsScreen(model: AppViewModel, folderName: String?, modifier: Modifier = Modifier) {
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) model.useFolder(uri)
    }
    val context = LocalContext.current
    val version = context.packageManager.getPackageInfo(context.packageName, 0).versionName

    Column(modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Settings", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
        Text("Notes folder", style = MaterialTheme.typography.titleMedium)
        Text(folderName ?: "On this phone", style = MaterialTheme.typography.bodyLarge)
        Text(
            "To see the same notes as on your computer, choose the folder a sync app (for example Syncthing, " +
                "Dropbox or OneDrive) keeps in step with the notes folder set in the Mac or Windows app.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(onClick = { pick.launch(null) }) { Text("Choose Folder…") }
        if (folderName != null) {
            OutlinedButton(onClick = model::useAppFolder) { Text("Use Folder on This Phone") }
        }
        Text("Version $version", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (Updater.isAvailable) {
            val update by model.updater.state.collectAsState()
            OutlinedButton(
                onClick = { model.updater.check(userInitiated = true) },
                enabled = update != Updater.State.Checking && update != Updater.State.Downloading,
            ) { Text("Check for Updates") }
            val status = when (val current = update) {
                Updater.State.Checking -> "Checking…"
                Updater.State.UpToDate -> "Scattered Notes is up to date."
                Updater.State.Downloading -> "Downloading the update…"
                is Updater.State.Failed -> current.message
                else -> "Scattered Notes checks GitHub for a new version once a day and asks before installing it."
            }
            Text(status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
