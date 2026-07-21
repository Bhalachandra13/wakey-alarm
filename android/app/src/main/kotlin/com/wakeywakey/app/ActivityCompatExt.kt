package com.wakeywakey.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Helpers for requesting the location permissions used by the
 * geofence feature. Lives in its own file so the bulk of the
 * geofence logic (in [GeofenceController]) stays focused on the
 * `GeofencingClient` integration.
 *
 * Background location is *not* a runtime permission the app can
 * request directly — it is granted via a system Settings page,
 * which is why the foreground and background flows look so
 * different.
 */
object ActivityCompatExt {

    private const val FOREGROUND_REQUEST_CODE = 3001
    private const val BACKGROUND_REQUEST_CODE = 3002

    /**
     * Request the foreground location permission (either
     * `ACCESS_FINE_LOCATION` or `ACCESS_COARSE_LOCATION`).
     *
     * On API 29+ the user is presented with the system "Allow
     * only while using the app / One time / Don't allow"
     * dialog. The result is delivered to the activity's
     * `onRequestPermissionsResult` — Dart re-queries the
     * permission state via `getLocationPermissionStatus` after
     * the dialog closes.
     */
    fun requestForegroundLocation(activity: Activity): Boolean {
        val current = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.ACCESS_FINE_LOCATION,
        )
        if (current == PackageManager.PERMISSION_GRANTED) return true
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            FOREGROUND_REQUEST_CODE,
        )
        return false
    }

    /**
     * Open the system Settings page for the app so the user can
     * grant the "Allow all the time" background location
     * permission.
     *
     * There is no in-app dialog for this on Android 10+ — the OS
     * requires the user to navigate to the app's permission
     * page and pick "Allow all the time" out of three choices.
     * Showing a Dart-side explanation screen before this call
     * improves the grant rate (per `requirements.md` §4).
     *
     * Pre-Android-10 does not need this — the single location
     * permission covers both. Caller is expected to gate on the
     * API level.
     */
    fun requestBackgroundLocation(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        intent.data = Uri.fromParts("package", activity.packageName, null)
        // FLAG_ACTIVITY_NEW_TASK is required when starting an
        // activity from a non-activity context. We're inside an
        // Activity, but the intent is targeting a different
        // package's settings page, so this flag is harmless and
        // ensures the Settings activity launches correctly.
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            activity.startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.w(
                "ActivityCompatExt",
                "Failed to open app settings for background location",
                e,
            )
        }
    }
}
