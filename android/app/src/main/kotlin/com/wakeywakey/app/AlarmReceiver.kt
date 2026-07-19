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
 *  3. **Clean up one-shot alarms** — but only on a *natural* fire,
 *     not a snooze follow-up. The natural fire is the only point
 *     where we know the alarm has actually reached its scheduled
 *     time. Snooze fires are managed by [RingingActivity], which
 *     schedules them and increments [AlarmData.currentSnoozeCount]
 *     itself; the receiver stays out of the way.
 *
 * The data the receiver needs for (2) and (3) is carried in the
 * Intent extras of the firing PendingIntent, which were populated
 * by [AlarmScheduler.buildFireIntent] at schedule time. The
 * [EXTRA_IS_SNOOZE_FIRE] extra is the discriminator that tells the
 * receiver which kind of fire is happening.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, -1)
        val isSnoozeFire = intent.getBooleanExtra(EXTRA_IS_SNOOZE_FIRE, false)
        Log.d(TAG, "AlarmReceiver.onReceive – alarmId=$alarmId isSnoozeFire=$isSnoozeFire")

        // Emit a `fired` event to the Dart side so the in-app UI can
        // react (e.g. show an "alarm is ringing" indicator). No-op if
        // no Dart listener is attached — the event is silently dropped,
        // which is fine because nothing in the UI could render it
        // anyway when the app is cold-started by this broadcast.
        if (alarmId >= 0) {
            AlarmEventBus.emit(
                mapOf(
                    "alarmId" to alarmId,
                    "type" to "fired",
                    // Iteration 1 only schedules time-based alarms via
                    // AlarmManager; geofence-driven fires arrive through
                    // a separate path in Iteration 4.
                    "triggerType" to "time",
                ),
            )
        }

        // (1) Hand off to AlarmService. Must be foreground on API 26+
        // because background services are killed almost immediately.
        val serviceIntent = Intent(context, AlarmService::class.java).apply {
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_LABEL, intent.getStringExtra(EXTRA_LABEL) ?: "")
            putExtra(EXTRA_SOUND_URI, intent.getStringExtra(EXTRA_SOUND_URI) ?: "")
            putExtra(EXTRA_VIBRATE, intent.getBooleanExtra(EXTRA_VIBRATE, true))
            putExtra(EXTRA_SNOOZE_DURATION_MIN, intent.getIntExtra(EXTRA_SNOOZE_DURATION_MIN, 10))
            putExtra(EXTRA_MAX_SNOOZE_COUNT, intent.getIntExtra(EXTRA_MAX_SNOOZE_COUNT, -1))
            putExtra(EXTRA_IS_SNOOZE_FIRE, isSnoozeFire)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        // (2) and (3): re-schedule or clean up. SKIPPED for snooze
        // fires — the RingingActivity is in charge of those, and the
        // persisted currentSnoozeCount is already correct. The only
        // thing the receiver does for a snooze fire is start the
        // service and emit the fired event above.
        if (alarmId < 0) {
            Log.w(TAG, "Skipping self-reschedule: missing alarmId")
            return
        }
        if (isSnoozeFire) {
            Log.d(TAG, "Snooze fire; leaving schedule and persistence to RingingActivity")
            return
        }
        rescheduleOrCleanup(context, intent, alarmId)
    }

    private fun rescheduleOrCleanup(context: Context, intent: Intent, alarmId: Int) {
        val repeatDays = intent.getStringExtra(EXTRA_REPEAT_DAYS)
        if (repeatDays.isNullOrBlank()) {
            // One-shot natural fire: leave the data and PendingIntent
            // alone here. RingingActivity's dismiss handler will call
            // AlarmScheduler.cancel to clean up if the user dismisses;
            // and if the user snoozes, RingingActivity will re-persist
            // (with an incremented currentSnoozeCount) and re-schedule
            // the follow-up snooze fire. Cancelling here would erase
            // the data before RingingActivity could read it, which
            // broke one-shot snooze entirely in earlier iterations.
            Log.d(TAG, "One-shot alarm fired; awaiting RingingActivity dismiss/snooze")
            return
        }

        // Repeating natural fire: rebuild the AlarmData from the
        // intent extras and schedule the next occurrence.
        // NextAlarmTime.compute walks forward up to 7 days to find
        // the soonest matching day-of-week.
        //
        // Reset the snooze counter to 0 here so the user gets a
        // fresh `maxSnoozeCount` for the next fire cycle, regardless
        // of how many times they snoozed the current one.
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
            currentSnoozeCount = 0,
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
        // Discriminates between a natural fire (the alarm reached its
        // scheduled time) and a snooze follow-up fire (scheduled by
        // RingingActivity when the user tapped snooze). See the
        // class-level comment for the full state machine.
        const val EXTRA_IS_SNOOZE_FIRE = "isSnoozeFire"
    }
}
