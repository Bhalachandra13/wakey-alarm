package com.wakeywakey.app

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/**
 * Full-screen alarm ringing UI.
 *
 * Launched by [AlarmService] via the `fullScreenIntent` on its
 * high-priority notification, so the activity appears on top of the
 * lock screen when the alarm fires.
 *
 * Responsibilities:
 * - Display the alarm label.
 * - Let the user **Snooze** (re-schedule the same alarm for
 *   `snoozeDurationMin` minutes from now) or **Dismiss** (just stop the
 *   ringing service).
 * - Send the appropriate stop signal to [AlarmService] in both cases.
 *
 * This is a pure Android `Activity` (not a Flutter activity) on purpose:
 * the ringing UI must work even if the Flutter engine is dead (e.g. the
 * process was cold-started by the `AlarmManager` broadcast after a
 * force-kill). Tying it to Flutter would re-introduce the very failure
 * mode the native pipeline exists to prevent.
 *
 * The dismiss/snooze outcomes are *also* sent back to Dart via
 * [MainActivity]'s MethodChannel in a follow-up task; the native side
 * of the contract is complete here.
 */
class RingingActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Show over the lock screen and turn the screen on.
        // API 27+ has dedicated setters; older devices need the window flags.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            )
        }

        val alarmId = intent.getIntExtra(AlarmReceiver.EXTRA_ALARM_ID, -1)
        val label = intent.getStringExtra(AlarmReceiver.EXTRA_LABEL) ?: "Alarm"
        val soundUri = intent.getStringExtra(AlarmReceiver.EXTRA_SOUND_URI) ?: ""
        val vibrate = intent.getBooleanExtra(AlarmReceiver.EXTRA_VIBRATE, true)
        val snoozeDurationMin = intent.getIntExtra(AlarmReceiver.EXTRA_SNOOZE_DURATION_MIN, 10)
        val maxSnoozeCount = intent.getIntExtra(AlarmReceiver.EXTRA_MAX_SNOOZE_COUNT, -1)

        setContentView(R.layout.activity_ringing)

        findViewById<TextView>(R.id.ringing_label).text = label
        findViewById<Button>(R.id.snooze_button).text =
            "Snooze ($snoozeDurationMin min)"

        findViewById<Button>(R.id.snooze_button).setOnClickListener {
            Log.d(TAG, "Snooze tapped for alarmId=$alarmId")
            val snoozed = scheduleSnooze(alarmId, snoozeDurationMin, maxSnoozeCount)
            stopAlarmService()
            // If the user has hit max snoozes, the tap is reported
            // as a dismiss so the Dart side clears any "ringing"
            // state correctly. Otherwise it goes through as a snooze.
            emitOutcome(if (snoozed) "snoozed" else "dismissed")
            finish()
        }

        findViewById<Button>(R.id.dismiss_button).setOnClickListener {
            Log.d(TAG, "Dismiss tapped for alarmId=$alarmId")
            // Clean up the alarm's persisted data and PendingIntent
            // BEFORE stopping the service, so the next natural fire
            // (for repeats) is queued up before the system can deliver
            // a fresh broadcast from any other source. See
            // [dismissAlarm] for the full reasoning.
            dismissAlarm(alarmId)
            stopAlarmService()
            emitOutcome("dismissed")
            finish()
        }
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        // Alarms must be explicitly dismissed or snoozed. Sending the
        // activity to the back keeps the AlarmService running and lets
        // the user re-open the ringing UI from the notification.
        moveTaskToBack(true)
    }

    // -------------------------------------------------------------------------
    // Snooze
    // -------------------------------------------------------------------------

    /**
     * Re-schedule the same alarm for [snoozeDurationMin] minutes
     * from now. Reads the persisted [AlarmScheduler.AlarmData]
     * (which carries the sound, label, vibrate, repeatDays, and
     * the running snooze counter) and delegates to
     * [AlarmScheduler.schedule] so the snoozed alarm is visible
     * to [BootReceiver] on the next reboot.
     *
     * Enforces [maxSnoozeCount] against the persisted
     * [AlarmData.currentSnoozeCount]:
     *  - `maxSnoozeCount < 0` (the sentinel for "unlimited")
     *    always allows the snooze.
     *  - Otherwise, once `currentSnoozeCount` has reached the
     *    limit, the function logs and returns `false` without
     *    rescheduling. The caller treats this as a dismiss.
     *
     * @return true if the snooze was actually scheduled, false if
     *   the user has already hit the limit (caller should emit a
     *   "dismissed" event in that case).
     */
    private fun scheduleSnooze(
        alarmId: Int,
        snoozeDurationMin: Int,
        maxSnoozeCount: Int,
    ): Boolean {
        if (alarmId < 0) {
            Log.w(TAG, "Cannot snooze: missing alarmId in intent")
            return false
        }

        val data = AlarmScheduler.readPersisted(this, alarmId)
        if (data == null) {
            Log.w(TAG, "Cannot snooze: no persisted AlarmData for id=$alarmId")
            return false
        }

        if (maxSnoozeCount >= 0 && data.currentSnoozeCount >= maxSnoozeCount) {
            Log.w(
                TAG,
                "Snooze blocked: alarmId=$alarmId current=${data.currentSnoozeCount} " +
                    "max=$maxSnoozeCount (treating as dismiss)",
            )
            return false
        }

        val nextCount = data.currentSnoozeCount + 1
        val incremented = data.copy(currentSnoozeCount = nextCount)
        val triggerTime = System.currentTimeMillis() + snoozeDurationMin * 60_000L
        // isSnoozeFire=true is what tells AlarmReceiver, on the
        // follow-up fire, to leave both the persisted count and the
        // next-occurrence scheduling alone. Without this flag, the
        // receiver would either cancel the one-shot or reset the
        // snooze count back to 0 — both wrong.
        AlarmScheduler.schedule(this, incremented, triggerTime, isSnoozeFire = true)
        return true
    }

    // -------------------------------------------------------------------------
    // Dismiss
    // -------------------------------------------------------------------------

    /**
     * Clean up the alarm's persisted data and pending PendingIntent
     * when the user taps Dismiss.
     *
     * Two cases, depending on whether the alarm is a one-shot or
     * a repeating alarm:
     *
     *  - **One-shot**: call [AlarmScheduler.cancel], which removes
     *    the persisted record AND cancels the PendingIntent. This is
     *    the only place one-shots get removed from persistence now —
     *    the receiver deliberately leaves the data alone on a natural
     *    fire so that the user can still snooze it (the snooze path
     *    needs the persisted data to read the current snooze count).
     *
     *  - **Repeating**: re-schedule the next *natural* fire (using
     *    [NextAlarmTime.compute] on the persisted data) with
     *    [AlarmData.currentSnoozeCount] reset to 0, then persist it.
     *    The snooze fire that the receiver just delivered is gone;
     *    the user has chosen to stop the current ringing cycle, and
     *    the next alarm should fire at the next matching day-of-week
     *    with a fresh snooze budget. Cancelling outright would lose
     *    the alarm entirely until the user re-enables it manually.
     *
     * If the persisted data is gone (e.g. a one-shot whose
     * AlarmScheduler.schedule was never called), the cancel call
     * is a safe no-op and we just log.
     */
    private fun dismissAlarm(alarmId: Int) {
        if (alarmId < 0) {
            Log.w(TAG, "Cannot dismiss: missing alarmId in intent")
            return
        }
        val data = AlarmScheduler.readPersisted(this, alarmId)
        if (data == null) {
            // Already cancelled (e.g. one-shot that was cleaned up
            // before the activity was created), or never persisted.
            // Nothing to do.
            Log.d(TAG, "Dismiss: no persisted data for id=$alarmId (already clean)")
            return
        }
        if (data.isRepeating) {
            val fresh = data.copy(currentSnoozeCount = 0)
            val nextTrigger = NextAlarmTime.compute(
                fresh.timeHour,
                fresh.timeMinute,
                fresh.repeatDays,
            )
            val ok = AlarmScheduler.schedule(this, fresh, nextTrigger)
            Log.d(
                TAG,
                "Dismiss: repeating alarm re-scheduled id=$alarmId next=$nextTrigger ok=$ok",
            )
        } else {
            AlarmScheduler.cancel(this, alarmId)
            Log.d(TAG, "Dismiss: one-shot alarm cancelled id=$alarmId")
        }
    }

    // -------------------------------------------------------------------------
    // Service control
    // -------------------------------------------------------------------------

    private fun stopAlarmService() {
        val stopIntent = Intent(this, AlarmService::class.java).apply {
            action = AlarmService.ACTION_STOP_ALARM
        }
        startService(stopIntent)
    }

    // -------------------------------------------------------------------------
    // Event reporting
    // -------------------------------------------------------------------------

    /**
     * Push a dismiss/snooze event to the Dart side via
     * [AlarmEventBus]. No-op if no Dart listener is attached
     * (e.g. the process was cold-started by the alarm broadcast
     * and the user never opened the app).
     */
    private fun emitOutcome(type: String) {
        val currentAlarmId = intent.getIntExtra(AlarmReceiver.EXTRA_ALARM_ID, -1)
        if (currentAlarmId < 0) return
        AlarmEventBus.emit(
            mapOf(
                "alarmId" to currentAlarmId,
                "type" to type,
            ),
        )
    }

    companion object {
        private const val TAG = "RingingActivity"
    }
}
