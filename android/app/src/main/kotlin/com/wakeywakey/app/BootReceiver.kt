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

        val count = AlarmScheduler.rescheduleAllPersisted(context)
        Log.d(TAG, "BootReceiver: re-scheduled $count alarms after $intent.action")
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
