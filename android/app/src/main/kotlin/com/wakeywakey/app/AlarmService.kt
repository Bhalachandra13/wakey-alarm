package com.wakeywakey.app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground Service that drives the alarm ringing experience.
 *
 * Responsibilities:
 * - Show a high-priority notification with a fullScreenIntent to
 *   [RingingActivity] (required for lock-screen alarm display).
 * - Play the alarm ringtone.
 * - Vibrate if requested.
 * - Stop itself when it receives [ACTION_STOP_ALARM] via [startService].
 *
 * The service is started by [AlarmReceiver] and stopped by
 * [RingingActivity] on dismiss or snooze.
 */
class AlarmService : Service() {

    private var ringtone: Ringtone? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_ALARM) {
            Log.d(TAG, "Received STOP_ALARM – stopping service")
            stopRingtone()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val alarmId = intent?.getIntExtra(AlarmReceiver.EXTRA_ALARM_ID, -1) ?: -1
        val label = intent?.getStringExtra(AlarmReceiver.EXTRA_LABEL) ?: "Alarm"
        val soundUri = intent?.getStringExtra(AlarmReceiver.EXTRA_SOUND_URI) ?: ""
        val vibrate = intent?.getBooleanExtra(AlarmReceiver.EXTRA_VIBRATE, true) ?: true
        val snoozeDurationMin =
            intent?.getIntExtra(AlarmReceiver.EXTRA_SNOOZE_DURATION_MIN, 10) ?: 10
        val maxSnoozeCount = intent?.getIntExtra(AlarmReceiver.EXTRA_MAX_SNOOZE_COUNT, -1) ?: -1

        Log.d(TAG, "Starting alarm: id=$alarmId label=$label vibrate=$vibrate")

        val fullScreenIntent = buildFullScreenIntent(
            alarmId, label, soundUri, vibrate, snoozeDurationMin, maxSnoozeCount,
        )
        val notification = buildNotification(label, fullScreenIntent)

        startForeground(NOTIFICATION_ID, notification)
        playRingtone(soundUri)
        if (vibrate) startVibration()

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRingtone()
        cancelVibration()
    }

    // -------------------------------------------------------------------------
    // Notification
    // -------------------------------------------------------------------------

    private fun buildFullScreenIntent(
        alarmId: Int,
        label: String,
        soundUri: String,
        vibrate: Boolean,
        snoozeDurationMin: Int,
        maxSnoozeCount: Int,
    ): PendingIntent {
        val ringingIntent = Intent(this, RingingActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(AlarmReceiver.EXTRA_ALARM_ID, alarmId)
            putExtra(AlarmReceiver.EXTRA_LABEL, label)
            putExtra(AlarmReceiver.EXTRA_SOUND_URI, soundUri)
            putExtra(AlarmReceiver.EXTRA_VIBRATE, vibrate)
            putExtra(AlarmReceiver.EXTRA_SNOOZE_DURATION_MIN, snoozeDurationMin)
            putExtra(AlarmReceiver.EXTRA_MAX_SNOOZE_COUNT, maxSnoozeCount)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(this, alarmId, ringingIntent, flags)
    }

    private fun buildNotification(label: String, fullScreenIntent: PendingIntent): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText("Tap to open alarm")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // fullScreenIntent shows the RingingActivity on the lock screen.
            .setFullScreenIntent(fullScreenIntent, /* highPriority= */ true)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }

    // -------------------------------------------------------------------------
    // Ringtone
    // -------------------------------------------------------------------------

    private fun playRingtone(soundUriString: String) {
        val uri: Uri = try {
            if (soundUriString.isNotBlank()) Uri.parse(soundUriString)
            else RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        } catch (_: Exception) {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        }

        ringtone = RingtoneManager.getRingtone(applicationContext, uri)?.also { r ->
            // API 28+: AudioAttributes let us declare this as an alarm stream
            // so it respects the alarm volume, not the media/notification volume.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                r.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            }
            r.isLooping = true
            r.play()
        }
    }

    private fun stopRingtone() {
        ringtone?.stop()
        ringtone = null
    }

    // -------------------------------------------------------------------------
    // Vibration
    // -------------------------------------------------------------------------

    @SuppressLint("MissingPermission") // VIBRATE permission declared in manifest
    private fun startVibration() {
        // Long-short-long pattern typical for alarms.
        val pattern = longArrayOf(0, 500, 300, 700)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // API 31+: VibratorManager is preferred over the deprecated Vibrator.
            val vibratorManager =
                getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vibratorManager?.defaultVibrator?.vibrate(
                VibrationEffect.createWaveform(pattern, /* repeat= */ 0),
            )
        } else {
            @Suppress("DEPRECATION")
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            @Suppress("DEPRECATION")
            vibrator?.vibrate(
                VibrationEffect.createWaveform(pattern, /* repeat= */ 0),
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun cancelVibration() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager =
                getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vibratorManager?.defaultVibrator?.cancel()
        } else {
            @Suppress("DEPRECATION")
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            vibrator?.cancel()
        }
    }

    companion object {
        private const val TAG = "AlarmService"
        private const val NOTIFICATION_ID = 9001
        private const val CHANNEL_ID = "alarm_alerts"
        const val ACTION_STOP_ALARM = "com.wakeywakey.app.STOP_ALARM"
    }
}
