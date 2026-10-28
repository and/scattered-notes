package com.scatterednotes.update

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import com.scatterednotes.BuildConfig
import com.scatterednotes.core.Release
import com.scatterednotes.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Checks GitHub for a newer release and installs its APK, like the Mac and Windows apps do. Only the
 * build published on GitHub has it ([isAvailable]): Google Play updates the Play build itself and
 * doesn't allow apps to update themselves. Android only installs an update signed with the same key
 * as the installed app, so a tampered download is refused.
 */
class Updater(private val context: Context, private val scope: CoroutineScope) {
    sealed interface State {
        data object Idle : State
        data object Checking : State
        data object UpToDate : State
        data class Available(val release: Release) : State
        data object Downloading : State
        data class Failed(val message: String) : State
    }

    private val prefs = context.getSharedPreferences("updates", Context.MODE_PRIVATE)
    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state.asStateFlow()

    private val installedVersion: String =
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0"

    /** Checks at most every 20 hours, like the desktop apps. */
    fun checkIfDue() {
        if (!isAvailable) return
        val last = prefs.getLong(KEY_LAST_CHECK, 0)
        if (System.currentTimeMillis() - last < 20 * 60 * 60 * 1000L) return
        check(userInitiated = false)
    }

    /** A check the user asked for also offers a release they skipped, and reports when there is none. */
    fun check(userInitiated: Boolean) {
        if (!isAvailable || _state.value == State.Checking || _state.value == State.Downloading) return
        _state.value = State.Checking
        scope.launch {
            _state.value = try {
                val release = withContext(Dispatchers.IO) { fetchLatest() }
                prefs.edit().putLong(KEY_LAST_CHECK, System.currentTimeMillis()).apply()
                val skipped = if (userInitiated) null else prefs.getString(KEY_SKIPPED, null)
                when {
                    release != null && release.isUpdate(installedVersion, skipped) -> State.Available(release)
                    userInitiated -> State.UpToDate
                    else -> State.Idle
                }
            } catch (e: Exception) {
                if (userInitiated) State.Failed("Couldn't reach GitHub. Check your connection and try again.") else State.Idle
            }
        }
    }

    fun skip(release: Release) {
        prefs.edit().putString(KEY_SKIPPED, release.tag).apply()
        _state.value = State.Idle
    }

    fun remindLater() {
        _state.value = State.Idle
    }

    /** Downloads the APK and hands it to Android's installer, which asks the user to confirm. */
    fun install(release: Release) {
        _state.value = State.Downloading
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val apk = File(context.cacheDir, "update.apk")
                    download(release.apkUrl, apk)
                    commit(apk)
                    apk.delete()
                }
            } catch (e: Exception) {
                _state.value = State.Failed("The update couldn't be downloaded. Try again later.")
            }
        }
    }

    /** Called with the installer's result, delivered to [MainActivity]. */
    fun onInstallStatus(intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            // On success Android replaces and restarts the app, so this is only reached when it wasn't installed
            PackageInstaller.STATUS_SUCCESS -> _state.value = State.Idle
            PackageInstaller.STATUS_FAILURE_ABORTED -> _state.value = State.Idle
            else -> _state.value = State.Failed(
                intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "The update couldn't be installed.",
            )
        }
    }

    private fun fetchLatest(): Release? {
        val connection = URL(RELEASES_API).openConnection() as HttpURLConnection
        connection.setRequestProperty("Accept", "application/vnd.github+json")
        connection.connectTimeout = 15_000
        connection.readTimeout = 15_000
        return try {
            if (connection.responseCode != 200) throw java.io.IOException("HTTP ${connection.responseCode}")
            Release.parse(connection.inputStream.bufferedReader().use { it.readText() })
        } finally {
            connection.disconnect()
        }
    }

    private fun download(url: String, destination: File) {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 60_000
        try {
            if (connection.responseCode != 200) throw java.io.IOException("HTTP ${connection.responseCode}")
            connection.inputStream.use { input -> destination.outputStream().use { input.copyTo(it) } }
        } finally {
            connection.disconnect()
        }
    }

    private fun commit(apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(context.packageName)
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            session.openWrite("update.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val status = Intent(context, MainActivity::class.java)
                .setAction(ACTION_INSTALL_STATUS)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            // Mutable so the installer can add its result to the intent
            val pending = PendingIntent.getActivity(
                context, sessionId, status, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            session.commit(pending.intentSender)
        }
    }

    companion object {
        /** Whether this build updates itself from GitHub; false in the Google Play build. */
        val isAvailable: Boolean get() = BuildConfig.UPDATES_FROM_GITHUB
        const val ACTION_INSTALL_STATUS = "com.scatterednotes.action.INSTALL_STATUS"
        private const val RELEASES_API = "https://api.github.com/repos/and/scattered-notes/releases/latest"
        private const val KEY_LAST_CHECK = "lastCheck"
        private const val KEY_SKIPPED = "skippedVersion"
    }
}
