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
        // EXTRA_MAX_SNOOZE_COUNT is intentionally not enforced yet — that
        // requires a persisted snooze counter (DB or SharedPreferences)
        // and is handled in a follow-up task.

        setContentView(R.layout.activity_ringing)

        findViewById<TextView>(R.id.ringing_label).text = label
        findViewById<Button>(R.id.snooze_button).text =
            "Snooze ($snoozeDurationMin min)"

        findViewById<Button>(R.id.snooze_button).setOnClickListener {
            Log.d(TAG, "Snooze tapped for alarmId=$alarmId")
            scheduleSnooze(alarmId, snoozeDurationMin)
            stopAlarmService()
            emitOutcome("snoozed")
            finish()
        }

        findViewById<Button>(R.id.dismiss_button).setOnClickListener {
            Log.d(TAG, "Dismiss tapped for alarmId=$alarmId")
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
     * (which carries the sound, label, vibrate, repeatDays, etc.)
     * and delegates to [AlarmScheduler.schedule] so the snoozed
     * alarm is visible to [BootReceiver] on the next reboot.
     */
    private fun scheduleSnooze(alarmId: Int, snoozeDurationMin: Int) {
        if (alarmId < 0) {
            Log.w(TAG, "Cannot snooze: missing alarmId in intent")
            return
        }

        val data = AlarmScheduler.readPersisted(this, alarmId)
        if (data == null) {
            Log.w(TAG, "Cannot snooze: no persisted AlarmData for id=$alarmId")
            return
        }

        val triggerTime = System.currentTimeMillis() + snoozeDurationMin * 60_000L
        AlarmScheduler.schedule(this, data, triggerTime)
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
