package com.wakeywakey.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-schedules every persisted alarm on `BOOT_COMPLETED`.
 *
 * The Android OS clears all `AlarmManager` state when the device
 * shuts down (or the user swaps the battery, or the system force-
 * stops the package). Without this receiver, every alarm the user
 * had set would silently disappear after a reboot — which is the
 * exact failure mode an alarm clock is supposed to prevent.
 *
 * The persisted list of alarms lives in SharedPreferences (see
 * [AlarmScheduler]) so it is readable synchronously from
 * `onReceive` — the sqflite database that the Dart side uses
 * cannot be read without a live Flutter engine, and the Flutter
 * engine is *not* running when `BOOT_COMPLETED` fires.
 *
 * Two re-arm paths:
 *  1. **Time alarms** — re-scheduled via
 *     [AlarmScheduler.schedule] using the next natural fire time
 *     computed by [NextAlarmTime.compute].
 *  2. **Geofence alarms** — re-registered with Play Services via
 *     [GeofenceController.rearmPersistedGeofences]. The OS wipes
 *     `GeofencingClient` registrations on reboot (and on app
 *     upgrade), so without this re-arm the user's armed geofence
 *     alarm would silently disappear — see the doc on that method
 *     for the failure mode this prevents.
 *
 * Lock-screen boot (`LOCKED_BOOT_COMPLETED`) is intentionally not
 * handled here: at that stage the user's credential-encrypted
 * storage is not yet available, so the persisted alarms live in
 * default-encrypted storage (not credential-encrypted). We just
 * rely on the regular `BOOT_COMPLETED` which fires after the
 * device is unlocked for the first time after boot.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON" &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            // Some OEMs send `QUICKBOOT_POWERON` on a hard reboot;
            // `MY_PACKAGE_REPLACED` fires when the app is upgraded
            // (so re-scheduling after an update is also desirable).
            return
        }

        val all = AlarmScheduler.readAllPersisted(context)
        if (all.isEmpty()) {
            // Nothing to re-arm. Avoids the SharedPreferences read
            // cost on every cold start of the receiver (some OEMs
            // fire BOOT_COMPLETED frequently during early-boot
            // hand-offs).
            Log.d(TAG, "BootReceiver: no persisted alarms; nothing to re-arm")
            return
        }

        // Countdown timers are transient by design: their fire time
        // is `now + duration`, and after a reboot that moment is
        // either already in the past (so the timer should not fire)
        // or no longer meaningful (the user would have expected the
        // app to be running to show the countdown). Persisted timer
        // metadata is still kept while the app is alive so that
        // snooze/dismiss work, but we must NOT re-schedule them via
        // AlarmManager on boot — doing so would fire them at
        // 00:00/timeHour=0,minute=0 instead of the original countdown.
        val timeOnly = all.filter { it.triggerType == "TIME" }
        var ok = 0
        for (data in timeOnly) {
            val fresh = data.copy(currentSnoozeCount = 0)
            val triggerAtMillis = NextAlarmTime.compute(
                fresh.timeHour,
                fresh.timeMinute,
                fresh.repeatDays,
            )
            if (AlarmScheduler.schedule(context, fresh, triggerAtMillis)) ok++
        }
        Log.d(TAG, "BootReceiver: re-scheduled $ok/${timeOnly.size} time alarms after $intent.action")

        // Geofence re-arm. The GeofencingClient is wiped on reboot
        // and on app upgrade (MY_PACKAGE_REPLACED), so the user's
        // armed geofence alarms would otherwise silently disappear.
        // See GeofenceController.rearmPersistedGeofences for the
        // full rationale and failure semantics.
        GeofenceController.rearmPersistedGeofences(context)
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
