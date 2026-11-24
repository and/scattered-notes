package com.scatterednotes.notify

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.scatterednotes.R
import com.scatterednotes.core.MorningSummary
import com.scatterednotes.storage.AppFolder
import com.scatterednotes.storage.NoteStore
import com.scatterednotes.ui.MainActivity
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId

/**
 * The morning notification: at the time set in Settings, what is planned that day (see [MorningSummary]).
 * An alarm wakes [MorningReceiver] at that time, which reads the notes as they are then, so ticks made on
 * another device are counted. The alarm is exact when Android allows it (granted on Android 12 and 13; on 14
 * and later the person allows it once, see [canBeExact]); otherwise Android may deliver it up to an hour late
 * to save battery.
 */
object MorningReminder {
    const val KEY_ENABLED = "morningSummary.enabled"
    /** Minutes after midnight */
    const val KEY_MINUTES = "morningSummary.minutes"
    const val DEFAULT_MINUTES = 8 * 60
    const val CHANNEL_ID = "morningSummary"
    const val EXTRA_OPEN_DASHBOARD = "openDashboard"
    private const val NOTIFICATION_ID = 1001
    private const val ACTION_FIRE = "com.scatterednotes.MORNING_SUMMARY"

    private fun prefs(context: Context) = context.getSharedPreferences(AppFolder.PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context) = prefs(context).getBoolean(KEY_ENABLED, false)
    fun minutes(context: Context) = prefs(context).getInt(KEY_MINUTES, DEFAULT_MINUTES)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        schedule(context)
    }

    fun setMinutes(context: Context, minutes: Int) {
        prefs(context).edit().putInt(KEY_MINUTES, minutes).apply()
        schedule(context)
    }

    /** Whether Android lets the app post notifications (asked for from Android 13 on) */
    fun canNotify(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** The next time the summary is due, after [now] */
    fun nextTime(minutes: Int, now: LocalDateTime): LocalDateTime {
        val today = now.toLocalDate().atTime(LocalTime.MIN.plusMinutes(minutes.toLong()))
        return if (today.isAfter(now)) today else today.plusDays(1)
    }

    /** Sets the alarm for the next summary, or cancels it when the summary is off */
    fun schedule(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = firePendingIntent(context)
        alarms.cancel(pending)
        if (!isEnabled(context)) return
        val zone = ZoneId.systemDefault()
        val at = nextTime(minutes(context), LocalDateTime.now(zone)).atZone(zone).toInstant().toEpochMilli()
        // Both are delivered while the phone is idle; only the exact one keeps to the minute
        if (canBeExact(context)) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
    }

    /** Whether Android lets the app set an alarm for an exact time (asked for from Android 14 on) */
    fun canBeExact(context: Context): Boolean =
        Build.VERSION.SDK_INT < 31 || context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true

    private fun firePendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context, 0,
            Intent(context, MorningReceiver::class.java).setAction(ACTION_FIRE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /** Reads the notes and posts today's summary; runs off the main thread */
    fun post(context: Context, today: LocalDate = LocalDate.now()) {
        if (!canNotify(context)) return
        val store = NoteStore(AppFolder.open(context).first)
        store.loadAll()
        val summary = MorningSummary.make(store.agendaItems(), today) ?: return

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Morning summary", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "What is planned for the day, each morning"
            },
        )
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_OPEN_DASHBOARD, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(summary.title)
            .setContentText(summary.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(summary.body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    internal fun isFire(intent: Intent) = intent.action == ACTION_FIRE
}

/** Posts the summary when the alarm goes off, and sets the alarm again after a restart or a clock change */
class MorningReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        // The alarm is one-off: set the next one first, so a failed read never stops the summaries
        MorningReminder.schedule(app)
        if (!MorningReminder.isFire(intent) || !MorningReminder.isEnabled(app)) return
        val done = goAsync()
        Thread {
            try {
                MorningReminder.post(app)
            } catch (_: Exception) {
                // An unreadable folder means no summary today, not a crash
            } finally {
                done.finish()
            }
        }.start()
    }
}
