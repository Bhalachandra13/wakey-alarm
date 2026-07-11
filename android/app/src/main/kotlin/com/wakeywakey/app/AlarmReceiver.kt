package com.wakeywakey.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BroadcastReceiver that is invoked by [AlarmManager.setAlarmClock()].
 *
 * Its only responsibility is to extract the alarm data from the Intent
 * extras and hand off to [AlarmService] as a foreground service. All
 * sound/vibration/notification logic lives in the Service so that it
 * survives even if the Activity is killed.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "AlarmReceiver.onReceive – alarmId=${intent.getIntExtra(EXTRA_ALARM_ID, -1)}")

        val serviceIntent = Intent(context, AlarmService::class.java).apply {
            // Forward all alarm data extras to the service.
            putExtra(EXTRA_ALARM_ID, intent.getIntExtra(EXTRA_ALARM_ID, -1))
            putExtra(EXTRA_LABEL, intent.getStringExtra(EXTRA_LABEL) ?: "")
            putExtra(EXTRA_SOUND_URI, intent.getStringExtra(EXTRA_SOUND_URI) ?: "")
            putExtra(EXTRA_VIBRATE, intent.getBooleanExtra(EXTRA_VIBRATE, true))
            putExtra(EXTRA_SNOOZE_DURATION_MIN, intent.getIntExtra(EXTRA_SNOOZE_DURATION_MIN, 10))
            putExtra(EXTRA_MAX_SNOOZE_COUNT, intent.getIntExtra(EXTRA_MAX_SNOOZE_COUNT, -1))
        }

        // Must start as foreground – on API 26+ background services are
        // heavily restricted and will be killed almost immediately.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }

    companion object {
        private const val TAG = "AlarmReceiver"
        const val EXTRA_ALARM_ID = "alarmId"
        const val EXTRA_LABEL = "label"
        const val EXTRA_SOUND_URI = "soundUri"
        const val EXTRA_VIBRATE = "vibrate"
        const val EXTRA_SNOOZE_DURATION_MIN = "snoozeDurationMin"
        const val EXTRA_MAX_SNOOZE_COUNT = "maxSnoozeCount"
    }
}
