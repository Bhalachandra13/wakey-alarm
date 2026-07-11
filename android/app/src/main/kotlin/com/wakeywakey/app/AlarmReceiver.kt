package com.wakeywakey.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BroadcastReceiver that is invoked by [AlarmManager.setAlarmClock()].
 *
 * Three responsibilities, in order:
 *
 *  1. **Hand off to [AlarmService]** as a foreground service so the
 *     sound / vibration / notification pipeline runs in a process the
 *     OS will not kill.
 *  2. **Self-reschedule repeating alarms** by computing the next
 *     matching day-of-week and re-calling [AlarmScheduler.schedule].
 *     A "MON,WED,FRI" alarm keeps firing on every subsequent matching
 *     day without any user action.
 *  3. **Clean up one-shot alarms** by calling [AlarmScheduler.cancel]
 *     — without this, a one-shot alarm would remain in
 *     SharedPreferences and [BootReceiver] would resurrect it after
 *     a reboot.
 *
 * The data the receiver needs for (2) and (3) is carried in the
 * Intent extras of the firing PendingIntent, which were populated
 * by [AlarmScheduler.buildFireIntent] at schedule time.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, -1)
        Log.d(TAG, "AlarmReceiver.onReceive – alarmId=$alarmId")

        // (1) Hand off to AlarmService. Must be foreground on API 26+
        // because background services are killed almost immediately.
        val serviceIntent = Intent(context, AlarmService::class.java).apply {
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_LABEL, intent.getStringExtra(EXTRA_LABEL) ?: "")
            putExtra(EXTRA_SOUND_URI, intent.getStringExtra(EXTRA_SOUND_URI) ?: "")
            putExtra(EXTRA_VIBRATE, intent.getBooleanExtra(EXTRA_VIBRATE, true))
            putExtra(EXTRA_SNOOZE_DURATION_MIN, intent.getIntExtra(EXTRA_SNOOZE_DURATION_MIN, 10))
            putExtra(EXTRA_MAX_SNOOZE_COUNT, intent.getIntExtra(EXTRA_MAX_SNOOZE_COUNT, -1))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        // (2) and (3): re-schedule or clean up.
        if (alarmId < 0) {
            Log.w(TAG, "Skipping self-reschedule: missing alarmId")
            return
        }
        rescheduleOrCleanup(context, intent, alarmId)
    }

    private fun rescheduleOrCleanup(context: Context, intent: Intent, alarmId: Int) {
        val repeatDays = intent.getStringExtra(EXTRA_REPEAT_DAYS)
        if (repeatDays.isNullOrBlank()) {
            // One-shot: remove from persistence so BootReceiver does
            // not resurrect this alarm after a future reboot.
            Log.d(TAG, "One-shot alarm fired; removing from persistence")
            AlarmScheduler.cancel(context, alarmId)
            return
        }

        // Repeating: rebuild the AlarmData from the intent extras
        // and schedule the next occurrence. NextAlarmTime.compute
        // walks forward up to 7 days to find the soonest matching
        // day-of-week.
        val data = AlarmScheduler.AlarmData(
            alarmId = alarmId,
            timeHour = intent.getIntExtra(EXTRA_TIME_HOUR, 0),
            timeMinute = intent.getIntExtra(EXTRA_TIME_MINUTE, 0),
            repeatDays = repeatDays,
            label = intent.getStringExtra(EXTRA_LABEL) ?: "Alarm",
            soundUri = intent.getStringExtra(EXTRA_SOUND_URI) ?: "",
            vibrate = intent.getBooleanExtra(EXTRA_VIBRATE, true),
            snoozeDurationMin = intent.getIntExtra(EXTRA_SNOOZE_DURATION_MIN, 10),
            maxSnoozeCount = intent.getIntExtra(EXTRA_MAX_SNOOZE_COUNT, -1),
        )
        val nextTrigger = NextAlarmTime.compute(
            data.timeHour,
            data.timeMinute,
            data.repeatDays,
        )
        val ok = AlarmScheduler.schedule(context, data, nextTrigger)
        Log.d(TAG, "Repeating alarm self-rescheduled: ok=$ok next=$nextTrigger")
    }

    companion object {
        private const val TAG = "AlarmReceiver"
        const val EXTRA_ALARM_ID = "alarmId"
        const val EXTRA_LABEL = "label"
        const val EXTRA_SOUND_URI = "soundUri"
        const val EXTRA_VIBRATE = "vibrate"
        const val EXTRA_SNOOZE_DURATION_MIN = "snoozeDurationMin"
        const val EXTRA_MAX_SNOOZE_COUNT = "maxSnoozeCount"
        // Schedule metadata – needed by [AlarmScheduler] when the
        // receiver self-reschedules a repeating alarm, and by
        // [AlarmService] if it ever needs to recompute fire times.
        const val EXTRA_TIME_HOUR = "timeHour"
        const val EXTRA_TIME_MINUTE = "timeMinute"
        const val EXTRA_REPEAT_DAYS = "repeatDays"
    }
}
