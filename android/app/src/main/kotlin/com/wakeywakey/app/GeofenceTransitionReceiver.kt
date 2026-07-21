package com.wakeywakey.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Receives [com.google.android.gms.location.GeofencingEvent] broadcasts
 * from the OS-managed [GeofencingClient] and hands off to the same
 * ringing pipeline used by time-based alarms.
 *
 * The native side already routes through the AlarmManager pipeline
 * (see [AlarmScheduler] / [AlarmReceiver]) so a geofence fire looks
 * like a normal alarm fire to the rest of the app:
 *
 *  1. [GeofenceTransitionReceiver] catches the `GEOFENCE_TRANSITION_ENTER`
 *     transition.
 *  2. It emits a `fired` event to Dart via [AlarmEventBus] with
 *     `triggerType = "location"`.
 *  3. It starts [AlarmService] with the alarm's metadata, which
 *     shows the ringing UI (full-screen on lock screen, same
 *     dismiss/snooze as a time-based alarm).
 *
 * The one-shot auto-disarm is handled in Dart: the [AlarmsNotifier]
 * sees the `dismissed`/`snoozed` event for the geofence-triggered
 * alarm and removes the native geofence, then flips `is_armed` to
 * `false` so the UI shows the alarm as ready to be re-armed.
 *
 * The native receiver itself is intentionally minimal — it just
 * forwards the transition to the existing alarm pipeline. All
 * state machine logic (one-shot disarm, max-snooze enforcement,
 * etc.) is in Dart, where it's easier to test.
 */
class GeofenceTransitionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // Importing the full GeofencingEvent class would require a
        // runtime dependency on the play-services-location artifact.
        // For the transition-ENTER case we only need the alarmId
        // (which the native side encodes as a request-code in the
        // PendingIntent extras) and the trigger type. Reading the
        // extras avoids loading the full event class.
        val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, -1)
        if (alarmId < 0) {
            Log.w(TAG, "Geofence transition missing alarmId extra")
            return
        }
        Log.d(TAG, "Geofence ENTER transition for alarmId=$alarmId")

        // Emit a fired event to Dart. The AlarmsNotifier listens to
        // this and can decide whether to surface a "ringing now"
        // banner, etc. (The banner is for time-based alarms; we
        // keep it that way to avoid confusion with the
        // location-triggered fire which already shows the full
        // ringing UI.)
        AlarmEventBus.emit(
            mapOf(
                "alarmId" to alarmId,
                "type" to "fired",
                "triggerType" to "location",
            ),
        )

        // Hand off to the same AlarmService pipeline used by
        // time-based alarms. The label, vibrate, snooze duration,
        // and max-snooze count are read from the persisted
        // AlarmData — see AlarmScheduler.readPersisted.
        val data = AlarmScheduler.readPersisted(context, alarmId)
        if (data == null) {
            // Could happen if the user disarmed the alarm after
            // the geofence was registered (e.g. the alarm was
            // deleted from the UI). Drop the event silently —
            // there is nothing to ring.
            Log.w(TAG, "Geofence fire for unknown alarmId=$alarmId")
            return
        }

        val serviceIntent = Intent(context, AlarmService::class.java).apply {
            putExtra(AlarmReceiver.EXTRA_ALARM_ID, data.alarmId)
            putExtra(AlarmReceiver.EXTRA_LABEL, data.label)
            putExtra(AlarmReceiver.EXTRA_SOUND_URI, data.soundUri)
            putExtra(AlarmReceiver.EXTRA_VIBRATE, data.vibrate)
            putExtra(
                AlarmReceiver.EXTRA_SNOOZE_DURATION_MIN,
                data.snoozeDurationMin,
            )
            putExtra(
                AlarmReceiver.EXTRA_MAX_SNOOZE_COUNT,
                data.maxSnoozeCount,
            )
            // A geofence fire is the alarm's natural fire time, NOT
            // a snooze follow-up. The receiver's cleanup path will
            // be no-op for non-repeating time-based alarms, but
            // for geofences the Dart side handles the one-shot
            // disarm on dismiss/snooze.
            putExtra(AlarmReceiver.EXTRA_IS_SNOOZE_FIRE, false)
            putExtra(AlarmReceiver.EXTRA_TRIGGER_TYPE, "LOCATION")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }

    companion object {
        private const val TAG = "GeofenceReceiver"
        const val EXTRA_ALARM_ID = "alarmId"
    }
}
