package com.wakeywakey.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Single source of truth for scheduling, cancelling, and persisting
 * alarms on Android.
 *
 * Callers:
 * - [MainActivity] — when the Flutter app is alive (via the
 *   `scheduleAlarm` / `cancelAlarm` MethodChannel calls).
 * - [AlarmReceiver] — to self-reschedule a repeating alarm after
 *   it fires, so a "MON,WED,FRI" alarm keeps firing on the next
 *   matching day. One-shot alarms are cancelled here instead, so
 *   they don't linger in storage.
 * - [BootReceiver] — on `BOOT_COMPLETED`, to re-schedule every
 *   alarm that was registered when the device shut down. The OS
 *   clears `AlarmManager` state on reboot, so without this the
 *   user would have to open the app after every reboot.
 *
 * Persistence: alarm metadata is also written to a single
 * SharedPreferences entry as a JSON array. SharedPreferences is
 * available synchronously in a `BroadcastReceiver.onReceive`, which
 * is critical for `BootReceiver` (it runs before the Flutter engine
 * exists). The Dart-side sqflite database is *not* used here because
 * the native side has to be able to act without the Flutter engine.
 */
object AlarmScheduler {

    private const val TAG = "AlarmScheduler"

    private const val ACTION_FIRE_ALARM = "com.wakeywakey.action.FIRE_ALARM"
    private const val SCHEME_ALARM = "wakey"
    private const val URI_HOST_ALARM = "alarm"
    private const val URI_HOST_RING = "ring"

    private const val PREFS_NAME = "alarm_prefs"
    private const val KEY_SCHEDULED_ALARMS = "scheduled_alarms"

    /**
     * Canonical description of an alarm. Anything the alarm
     * pipeline needs to re-schedule it (without going through the
     * Dart side) lives here.
     */
    data class AlarmData(
        val alarmId: Int,
        val timeHour: Int,
        val timeMinute: Int,
        /**
         * Comma-separated day abbreviations (e.g. "MON,WED,FRI")
         * or null/blank for a one-shot alarm.
         */
        val repeatDays: String?,
        val label: String,
        val soundUri: String,
        val vibrate: Boolean,
        val snoozeDurationMin: Int,
        val maxSnoozeCount: Int,
    ) {
        val isRepeating: Boolean
            get() = !repeatDays.isNullOrBlank()
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Schedule an alarm to fire at [triggerAtMillis] and persist the
     * metadata to SharedPreferences.
     *
     * @return true if `setAlarmClock` returned successfully.
     */
    fun schedule(
        context: Context,
        data: AlarmData,
        triggerAtMillis: Long,
    ): Boolean {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: run {
                Log.w(TAG, "AlarmManager not available; cannot schedule id=${data.alarmId}")
                return false
            }

        val firePendingIntent = PendingIntent.getBroadcast(
            context,
            data.alarmId,
            buildFireIntent(context, data),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val showPendingIntent = PendingIntent.getActivity(
            context,
            data.alarmId,
            buildShowIntent(context, data),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return try {
            val info = AlarmManager.AlarmClockInfo(triggerAtMillis, showPendingIntent)
            alarmManager.setAlarmClock(info, firePendingIntent)
            persistAlarmData(context, data)
            Log.d(TAG, "Scheduled alarm id=${data.alarmId} at=$triggerAtMillis repeating=${data.isRepeating}")
            true
        } catch (se: SecurityException) {
            Log.e(TAG, "setAlarmClock rejected for id=${data.alarmId}", se)
            false
        }
    }

    /**
     * Cancel a previously-scheduled alarm and remove its metadata
     * from SharedPreferences. Idempotent: calling it for an
     * alarmId that is not scheduled is a no-op (and still
     * reports success to the caller).
     */
    fun cancel(context: Context, alarmId: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        if (alarmManager != null) {
            // Reconstruct an Intent with the same component used at
            // schedule time. Extras don't matter for equality
            // (PendingIntent.filterEquals ignores them).
            val existing = PendingIntent.getBroadcast(
                context,
                alarmId,
                Intent(context, AlarmReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            if (existing != null) {
                alarmManager.cancel(existing)
                Log.d(TAG, "Cancelled alarm id=$alarmId")
            } else {
                Log.d(TAG, "No PendingIntent to cancel for id=$alarmId (not scheduled?)")
            }
        }
        removePersistedAlarmData(context, alarmId)
    }

    /**
     * Read a single persisted [AlarmData] by id. Returns null if no
     * such record exists (e.g. it was a one-shot that already
     * fired and was cleaned up, or the alarm was never scheduled
     * on this device).
     */
    fun readPersisted(context: Context, alarmId: Int): AlarmData? {
        return readAllPersisted(context).firstOrNull { it.alarmId == alarmId }
    }

    /**
     * Re-schedule an alarm using its persisted metadata. Computes
     * the next fire time with [NextAlarmTime.compute], which
     * naturally handles both repeating (next matching day-of-week)
     * and one-shot (next occurrence of the time) cases.
     *
     * @return true if the alarm was successfully re-scheduled.
     */
    fun reschedulePersisted(context: Context, alarmId: Int): Boolean {
        val data = readPersisted(context, alarmId) ?: run {
            Log.w(TAG, "reschedulePersisted: no persisted data for id=$alarmId")
            return false
        }
        val triggerAtMillis = NextAlarmTime.compute(
            data.timeHour,
            data.timeMinute,
            data.repeatDays,
        )
        return schedule(context, data, triggerAtMillis)
    }

    /**
     * Re-schedule all persisted alarms. Used by [BootReceiver] on
     * `BOOT_COMPLETED`. One-shot alarms whose fire time is already
     * in the past will be rescheduled for "tomorrow at the same
     * time" by [NextAlarmTime.compute], which is a reasonable
     * fallback for a one-shot that the user expected to ring while
     * the device was off.
     */
    fun rescheduleAllPersisted(context: Context): Int {
        val all = readAllPersisted(context)
        Log.d(TAG, "Boot: re-scheduling ${all.size} persisted alarms")
        var ok = 0
        for (data in all) {
            val triggerAtMillis = NextAlarmTime.compute(
                data.timeHour,
                data.timeMinute,
                data.repeatDays,
            )
            if (schedule(context, data, triggerAtMillis)) ok++
        }
        return ok
    }

    // -------------------------------------------------------------------------
    // PendingIntent builders
    // -------------------------------------------------------------------------

    /**
     * Build the broadcast Intent that AlarmManager fires to invoke
     * [AlarmReceiver]. Carries the full alarm payload as extras so
     * the receiver can self-reschedule repeating alarms without
     * needing SharedPreferences lookups.
     */
    private fun buildFireIntent(context: Context, data: AlarmData): Intent {
        return Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_FIRE_ALARM
            // Unique per alarmId so PendingIntents for different
            // alarms don't collide. FLAG_UPDATE_CURRENT still
            // updates the extras on a re-schedule.
            this.data = Uri.parse("$SCHEME_ALARM://$URI_HOST_ALARM/${data.alarmId}")
            putExtra(AlarmReceiver.EXTRA_ALARM_ID, data.alarmId)
            putExtra(AlarmReceiver.EXTRA_TIME_HOUR, data.timeHour)
            putExtra(AlarmReceiver.EXTRA_TIME_MINUTE, data.timeMinute)
            putExtra(AlarmReceiver.EXTRA_REPEAT_DAYS, data.repeatDays)
            putExtra(AlarmReceiver.EXTRA_LABEL, data.label)
            putExtra(AlarmReceiver.EXTRA_SOUND_URI, data.soundUri)
            putExtra(AlarmReceiver.EXTRA_VIBRATE, data.vibrate)
            putExtra(AlarmReceiver.EXTRA_SNOOZE_DURATION_MIN, data.snoozeDurationMin)
            putExtra(AlarmReceiver.EXTRA_MAX_SNOOZE_COUNT, data.maxSnoozeCount)
        }
    }

    /**
     * Build the activity Intent that the system fires when the
     * user taps the status-bar alarm icon. Points at
     * [RingingActivity] so the full-screen dismiss/snooze UI is
     * shown directly.
     */
    private fun buildShowIntent(context: Context, data: AlarmData): Intent {
        return Intent(context, RingingActivity::class.java).apply {
            // `this.data` (the Intent's data URI) — disambiguated
            // from the outer `data` parameter via `this` so the
            // compiler doesn't think we're trying to reassign it.
            this.data = Uri.parse("$SCHEME_ALARM://$URI_HOST_RING/${data.alarmId}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(AlarmReceiver.EXTRA_ALARM_ID, data.alarmId)
            putExtra(AlarmReceiver.EXTRA_LABEL, data.label)
            putExtra(AlarmReceiver.EXTRA_SOUND_URI, data.soundUri)
            putExtra(AlarmReceiver.EXTRA_VIBRATE, data.vibrate)
            putExtra(AlarmReceiver.EXTRA_SNOOZE_DURATION_MIN, data.snoozeDurationMin)
            putExtra(AlarmReceiver.EXTRA_MAX_SNOOZE_COUNT, data.maxSnoozeCount)
        }
    }

    // -------------------------------------------------------------------------
    // SharedPreferences persistence
    // -------------------------------------------------------------------------

    private fun persistAlarmData(context: Context, data: AlarmData) {
        val prefs = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val all = readAllInternal(prefs).toMutableList()
        all.removeAll { it.alarmId == data.alarmId }
        all.add(data)
        writeAllInternal(prefs, all)
    }

    private fun removePersistedAlarmData(context: Context, alarmId: Int) {
        val prefs = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val all = readAllInternal(prefs).toMutableList()
        if (all.removeAll { it.alarmId == alarmId }) {
            writeAllInternal(prefs, all)
        }
    }

    private fun readAllPersisted(context: Context): List<AlarmData> {
        val prefs = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return readAllInternal(prefs)
    }

    private fun readAllInternal(prefs: SharedPreferences): List<AlarmData> {
        val json = prefs.getString(KEY_SCHEDULED_ALARMS, "[]") ?: "[]"
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).mapNotNull { i ->
                runCatching { fromJson(arr.getJSONObject(i)) }.getOrNull()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read persisted alarms: $json", e)
            emptyList()
        }
    }

    private fun writeAllInternal(prefs: SharedPreferences, alarms: List<AlarmData>) {
        val arr = JSONArray()
        alarms.forEach { arr.put(toJson(it)) }
        // commit() is synchronous; we want BootReceiver's read to
        // see the latest value without waiting for a disk flush.
        prefs.edit().putString(KEY_SCHEDULED_ALARMS, arr.toString()).commit()
    }

    private fun toJson(d: AlarmData): JSONObject = JSONObject().apply {
        put("alarmId", d.alarmId)
        put("timeHour", d.timeHour)
        put("timeMinute", d.timeMinute)
        put("repeatDays", d.repeatDays)
        put("label", d.label)
        put("soundUri", d.soundUri)
        put("vibrate", d.vibrate)
        put("snoozeDurationMin", d.snoozeDurationMin)
        put("maxSnoozeCount", d.maxSnoozeCount)
    }

    private fun fromJson(o: JSONObject): AlarmData = AlarmData(
        alarmId = o.getInt("alarmId"),
        timeHour = o.getInt("timeHour"),
        timeMinute = o.getInt("timeMinute"),
        repeatDays = if (o.isNull("repeatDays")) null else o.getString("repeatDays"),
        label = o.optString("label", "Alarm"),
        soundUri = o.optString("soundUri", ""),
        vibrate = o.optBoolean("vibrate", true),
        snoozeDurationMin = o.optInt("snoozeDurationMin", 10),
        maxSnoozeCount = o.optInt("maxSnoozeCount", -1),
    )
}
