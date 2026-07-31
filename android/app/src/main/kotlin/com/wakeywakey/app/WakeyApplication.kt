package com.wakeywakey.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.app.FlutterApplication

/**
 * Application entry point.
 *
 * The [NotificationChannel] for alarm alerts is created here, in
 * [onCreate], rather than in [MainActivity.configureFlutterEngine].
 * This is important because the alarm pipeline (see [AlarmService])
 * is designed to fire even when the app has been cold-started by
 * the AlarmManager broadcast and the user has never opened the app.
 * In that cold-start path only the [Application] is initialised —
 * [MainActivity] may never run — so any channel creation that lives
 * in the activity is too late. The channel must exist by the time
 * [AlarmService.startForeground] posts its notification, or the
 * system will substitute a default-importance channel and the
 * high-priority full-screen-intent behaviour will be silently
 * dropped (the alarm will ring, but it won't be the loud,
 * lock-screen-displaying, do-not-disturb-bypassing alarm the user
 * expects).
 *
 * Channels are immutable once created: if the channel already
 * exists with a different configuration, this call is a no-op.
 * That is acceptable here — the configuration is final — but it
 * does mean that any future change to the channel settings will
 * only take effect for fresh installs.
 */
class WakeyApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        createAlarmChannel()
    }

    private fun createAlarmChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Channels were introduced in API 26.
            return
        }
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            ALARM_NOTIFICATION_CHANNEL_ID,
            "Alarm alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Ringing alarms and timers"
            setBypassDnd(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            enableVibration(true)
        }
        notificationManager.createNotificationChannel(channel)
    }

    companion object {
        const val ALARM_NOTIFICATION_CHANNEL_ID = "alarm_alerts"
    }
}
