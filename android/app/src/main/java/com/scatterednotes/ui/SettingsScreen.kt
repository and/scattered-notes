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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Switch
import androidx.compose.material3.TextButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import android.Manifest
import android.app.TimePickerDialog
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.text.format.DateFormat
import com.scatterednotes.notify.MorningReminder
import com.scatterednotes.update.Updater
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

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
        MorningSummarySettings()
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

/** Settings → Morning summary: one notification a day with what is planned (see [MorningReminder]) */
@Composable
private fun MorningSummarySettings() {
    val context = LocalContext.current
    var enabled by remember { mutableStateOf(MorningReminder.isEnabled(context) && MorningReminder.canNotify(context)) }
    var minutes by remember { mutableStateOf(MorningReminder.minutes(context)) }
    var denied by remember { mutableStateOf(false) }
    var exact by remember { mutableStateOf(MorningReminder.canBeExact(context)) }

    // Back from Android's "Alarms & reminders" page: use the exact alarm if it was allowed
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    androidx.compose.runtime.DisposableEffect(lifecycle) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                val now = MorningReminder.canBeExact(context)
                if (now != exact) {
                    exact = now
                    MorningReminder.schedule(context)
                }
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    val askPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        denied = !granted || !MorningReminder.canNotify(context)
        enabled = !denied
        MorningReminder.setEnabled(context, enabled)
    }

    fun turn(on: Boolean) {
        if (on && Build.VERSION.SDK_INT >= 33 && !MorningReminder.canNotify(context)) {
            askPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        denied = on && !MorningReminder.canNotify(context)
        enabled = on && !denied
        MorningReminder.setEnabled(context, enabled)
    }

    Text("Notifications", style = MaterialTheme.typography.titleMedium)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("Morning summary", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Switch(checked = enabled, onCheckedChange = ::turn)
    }
    if (enabled) {
        val time = LocalTime.MIN.plusMinutes(minutes.toLong())
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Time", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            TextButton(onClick = {
                TimePickerDialog(context, { _, hour, minute ->
                    minutes = hour * 60 + minute
                    MorningReminder.setMinutes(context, minutes)
                }, time.hour, time.minute, DateFormat.is24HourFormat(context)).show()
            }) { Text(time.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))) }
        }
        if (!exact && Build.VERSION.SDK_INT >= 31) {
            Text(
                "Without \"Alarms & reminders\" allowed, Android may send the summary up to an hour late.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedButton(onClick = {
                context.startActivity(
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, android.net.Uri.parse("package:${context.packageName}")),
                )
            }) { Text("Allow Exact Time") }
        }
    }
    Text(
        if (denied) "Notifications for Scattered Notes are turned off in Android settings."
        else "One notification each morning with what is planned that day and how many to-dos are overdue. Tap it to open the Dashboard.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    if (denied) {
        OutlinedButton(onClick = {
            context.startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
            )
        }) { Text("Open Notification Settings") }
    }
}
