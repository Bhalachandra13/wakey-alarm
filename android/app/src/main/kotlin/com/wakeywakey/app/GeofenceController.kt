package com.wakeywakey.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.plugin.common.MethodChannel

/**
 * Native side of the geofence bridge.
 *
 * The bridge is intentionally thin — the bulk of the alarm state
 * machine lives in Dart (see the requirements.md discussion in
 * `AlarmsNotifier` for why). This class is responsible for:
 *
 *  1. **Permission state** — reporting and updating the
 *     foreground / background location permissions.
 *  2. **One-shot location reads** — `getCurrentLocation` for the
 *     "already inside the geofence?" pre-arm check.
 *  3. **Geofence registration** — `addGeofence` / `removeGeofence`
 *     using the Google Play Services `GeofencingClient`.
 *  4. **Battery optimization state** — exposing
 *     `isBatteryOptimizationExempt` and the request flow, since
 *     OEM battery killers are the #1 cause of "geofence didn't
 *     fire" complaints.
 *
 * Geofence *transition* handling lives in
 * [GeofenceTransitionReceiver] because it must be a
 * `BroadcastReceiver` registered in the manifest, not a
 * `MethodChannel` handler.
 */
object GeofenceController {

    private const val TAG = "GeofenceController"

    /**
     * One geofence can have at most 100 active registrations per
     * app. We hold them by [alarmId], so multiple armed geofence
     * alarms (a "wake me up before X, and before Y" use case) all
     * fit. The cap is per-app, not per-alarm, so we don't need to
     * worry about it here — just be aware it exists.
     */

    @Suppress("UNCHECKED_CAST")
    @JvmStatic
    fun handleMethodCall(
        context: Context,
        method: String,
        args: Map<String, Any?>?,
        result: MethodChannel.Result,
    ) {
        try {
            when (method) {
                "getLocationPermissionStatus" -> {
                    result.success(getLocationPermissionStatus(context))
                }

                "requestForegroundLocation" -> {
                    // The actual permission request is fired by
                    // `ActivityCompat.requestPermissions`, which
                    // requires an Activity. From MainActivity we
                    // can launch it directly; from a broadcast
                    // receiver we cannot. This is fine for the
                    // current call site (always from the Flutter
                    // UI via MainActivity), but if we ever call
                    // this from a non-Activity context, we'll
                    // need a different flow.
                    if (context !is android.app.Activity) {
                        result.error(
                            "needs_activity",
                            "Foreground location request must originate from an Activity",
                            null,
                        )
                        return
                    }
                    val granted = ActivityCompatExt.requestForegroundLocation(
                        context as android.app.Activity,
                    )
                    result.success(getLocationPermissionStatus(context))
                    // Suppress unused warning when the returned
                    // value isn't used downstream.
                    val _ignored = granted
                }

                "requestBackgroundLocation" -> {
                    if (context !is android.app.Activity) {
                        result.error(
                            "needs_activity",
                            "Background location request must originate from an Activity",
                            null,
                        )
                        return
                    }
                    ActivityCompatExt.requestBackgroundLocation(
                        context as android.app.Activity,
                    )
                    result.success(getLocationPermissionStatus(context))
                }

                "getCurrentLocation" -> {
                    val timeoutMs = (args?.get("timeoutMs") as? Number)?.toLong() ?: 10_000L
                    getCurrentLocation(context, timeoutMs, result)
                }

                "addGeofence" -> {
                    val alarmId = (args?.get("alarmId") as? Number)?.toInt() ?: -1
                    val lat = (args?.get("latitude") as? Number)?.toDouble() ?: return result.error(
                        "missing_field",
                        "latitude is required",
                        null,
                    )
                    val lon = (args?.get("longitude") as? Number)?.toDouble() ?: return result.error(
                        "missing_field",
                        "longitude is required",
                        null,
                    )
                    val radius = (args?.get("radiusMeters") as? Number)?.toInt() ?: return result.error(
                        "missing_field",
                        "radiusMeters is required",
                        null,
                    )
                    val expiration = (args?.get("expirationMillis") as? Number)?.toLong() ?: -1L
                    val label = (args?.get("label") as? String) ?: "Alarm"
                    val soundUri = (args?.get("soundUri") as? String) ?: ""
                    val vibrate = (args?.get("vibrate") as? Boolean) ?: true
                    val snoozeDurationMin = (args?.get("snoozeDurationMin") as? Number)?.toInt() ?: 10
                    val maxSnoozeCount = (args?.get("maxSnoozeCount") as? Number)?.toInt() ?: -1
                    addGeofence(
                        context,
                        alarmId,
                        lat,
                        lon,
                        radius,
                        expiration,
                        label,
                        soundUri,
                        vibrate,
                        snoozeDurationMin,
                        maxSnoozeCount,
                        result,
                    )
                }

                "removeGeofence" -> {
                    val alarmId = (args?.get("alarmId") as? Number)?.toInt() ?: -1
                    removeGeofence(context, alarmId, result)
                }

                "isBatteryOptimizationExempt" -> {
                    result.success(isBatteryOptimizationExempt(context))
                }

                "requestBatteryOptimizationExemption" -> {
                    if (context !is android.app.Activity) {
                        result.error(
                            "needs_activity",
                            "Battery optimization request must originate from an Activity",
                            null,
                        )
                        return
                    }
                    requestBatteryOptimizationExemption(
                        context as android.app.Activity,
                    )
                    result.success(isBatteryOptimizationExempt(context))
                }

                else -> result.notImplemented()
            }
        } catch (se: SecurityException) {
            // Location permission was revoked between the status
            // check and the actual operation. Surface a structured
            // failure to the caller so the Dart arming flow can
            // re-route through the permission prompt instead of
            // bubbling up a raw PlatformException that the UI
            // doesn't know how to render. We use a result.success
            // with `added=false` + a specific error code rather
            // than result.error because the MethodChannel contract
            // for `addGeofence` is `returns {added: bool, error?:
            // string}`; a result.error here would surface as an
            // uncaught PlatformException in the Dart code.
            Log.w(TAG, "SecurityException in $method", se)
            result.success(
                mapOf("added" to false, "error" to "permission_denied"),
            )
        } catch (api: com.google.android.gms.common.api.ApiException) {
            // Play Services geofence operations throw ApiException
            // with a status code from
            // GeofenceStatusCodes / CommonStatusCodes. The human
            // message is usually empty or generic ("8: "), so
            // translating the code into something the UI can
            // surface is essential. Without this, a failed
            // addGeofences() looks like an opaque crash to the
            // user.
            val code = api.statusCode
            val humanMessage = humanizeGeofenceError(code)
            Log.w(
                TAG,
                "ApiException in $method: code=$code message=${api.message}",
            )
            result.success(
                mapOf("added" to false, "error" to humanMessage, "code" to code),
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error in $method", e)
            result.success(
                mapOf("added" to false, "error" to (e.message ?: "unknown_error")),
            )
        }
    }

    // -------------------------------------------------------------------------
    // Permission state
    // -------------------------------------------------------------------------

    /**
     * Map the device's location permission state to one of:
     *  * `"granted_foreground_and_background"` — `ACCESS_FINE_LOCATION`
     *    is granted and, on Android 10+, the user has set
     *    "Allow all the time" in the system Settings page.
     *  * `"granted_foreground_only"` — fine or coarse location is
     *    granted, but on Android 10+ the user has not (yet) granted
     *    the all-the-time variant.
     *  * `"denied"` — no location permission, or "denied permanently"
     *    on Android 11+.
     *  * `"not_required"` — pre-Android 10; the single location
     *    permission covers both foreground and background, so we
     *    don't need to walk the user through the two-step flow.
     */
    private fun getLocationPermissionStatus(context: Context): String {
        // Pre-Android 10: foreground == background. Report
        // "granted_foreground_and_background" if either is
        // granted, "denied" otherwise.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val fine = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
            val coarse = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
            return if (fine || coarse) "granted_foreground_and_background"
            else "denied"
        }

        // Android 10+: foreground and background are separate.
        val foreground = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!foreground) return "denied"

        // On Android 10+ the "background" grant is a separate
        // check; on Android 11+ the only way to know is whether
        // the user has set "Allow all the time" in Settings.
        val background = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return if (background) "granted_foreground_and_background"
        else "granted_foreground_only"
    }

    // -------------------------------------------------------------------------
    // Current location
    // -------------------------------------------------------------------------

    /**
     * Read a single high-accuracy location fix. Uses Play Services
     * Fused Location Provider so the request works on any device
     * with Google Play Services (the entire Phase 1 target).
     *
     * This is intentionally a one-shot — geofence transitions are
     * handled by the OS, not by polling. The Dart side only needs
     * a single fix for the "already inside?" pre-arm check.
     */
    @SuppressLint("MissingPermission")
    private fun getCurrentLocation(
        context: Context,
        timeoutMs: Long,
        result: MethodChannel.Result,
    ) {
        val client = LocationServices.getFusedLocationProviderClient(context)
        val cancellationSource = com.google.android.gms.tasks.CancellationTokenSource()
        val task = client.getCurrentLocation(
            Priority.PRIORITY_HIGH_ACCURACY,
            cancellationSource.token,
        )
        // Time out the request — Google Play Services does not
        // time out by default and we don't want a hung UI.
        val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
        mainHandler.postDelayed(
            { cancellationSource.cancel() },
            timeoutMs,
        )
        task.addOnSuccessListener { loc ->
            if (loc == null) {
                result.success(null)
            } else {
                result.success(
                    mapOf(
                        "latitude" to loc.latitude,
                        "longitude" to loc.longitude,
                    ),
                )
            }
        }
        task.addOnFailureListener { e ->
            Log.w(TAG, "getCurrentLocation failed", e)
            result.success(null)
        }
        task.addOnCanceledListener {
            Log.w(TAG, "getCurrentLocation timed out")
            result.success(null)
        }
    }

    // -------------------------------------------------------------------------
    // Geofence registration
    // -------------------------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun addGeofence(
        context: Context,
        alarmId: Int,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        expirationMillis: Long,
        label: String,
        soundUri: String,
        vibrate: Boolean,
        snoozeDurationMin: Int,
        maxSnoozeCount: Int,
        result: MethodChannel.Result,
    ) {
        if (alarmId < 0) {
            result.success(mapOf("added" to false, "error" to "invalid_alarm_id"))
            return
        }

        // Native-side hard cap: 20 km. Mirrors the Dart
        // GeofenceValidator range. Hard-coding here defends
        // against a buggy Dart caller trying to register an
        // oversized circle.
        if (radiusMeters !in 200..20_000) {
            result.success(
                mapOf("added" to false, "error" to "radius_out_of_range"),
            )
            return
        }

        val client = LocationServices.getGeofencingClient(context)
        val geofence = Geofence.Builder()
            .setRequestId(alarmId.toString())
            .setCircularRegion(latitude, longitude, radiusMeters.toFloat())
            .setExpirationDuration(expirationMillis)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
            .build()

        val pendingIntent = buildGeofencePendingIntent(context, alarmId)

        val request = GeofencingRequest.Builder()
            // INIT_TRIGGER_ENTER ensures the transition fires even
            // if the user is already inside the circle at the
            // moment of registration. Without this, the alarm
            // would silently not fire if the user armed the
            // geofence while already inside the radius — which is
            // the *exact* case the requirements §5.5 "Start Trip"
            // flow guards against, but also a useful safety net
            // for power-user direct manipulation.
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        client.removeGeofences(pendingIntent)
            .continueWithTask { preRemove ->
                if (!preRemove.isSuccessful) {
                    Log.w(
                        TAG,
                        "Pre-add removeGeofences for alarmId=$alarmId failed; " +
                            "proceeding to addGeofences anyway: ${preRemove.exception}",
                    )
                }
                client.addGeofences(request, pendingIntent)
            }
            .addOnSuccessListener {
                Log.d(TAG, "Geofence added for alarmId=$alarmId")
                // Persist the alarm metadata so that:
                //  1. The ringing UI has access to
                //     label/sound/vibrate/snooze settings when the
                //     geofence fires while the app process is dead.
                //  2. The BootReceiver can re-register the geofence
                //     with Play Services after a reboot. The OS
                //     wipes geofence registrations on reboot, so
                //     without persisting lat/lon/radius the user's
                //     armed geofence would silently disappear and
                //     the alarm would never fire. See
                //     [rearmPersistedGeofences] for the consumer.
                val data = AlarmScheduler.AlarmData(
                    alarmId = alarmId,
                    timeHour = 0,
                    timeMinute = 0,
                    repeatDays = null,
                    label = label,
                    soundUri = soundUri,
                    vibrate = vibrate,
                    snoozeDurationMin = snoozeDurationMin,
                    maxSnoozeCount = maxSnoozeCount,
                    currentSnoozeCount = 0,
                    triggerType = "LOCATION",
                    latitude = latitude,
                    longitude = longitude,
                    radiusMeters = radiusMeters,
                )
                AlarmScheduler.persistAlarmData(context, data)
                result.success(mapOf("added" to true))
            }
            .addOnFailureListener { e ->
                // The Play Services Tasks failure listener always
                // wraps the underlying cause in an `ApiException`,
                // so the human message is almost always empty or
                // useless ("8: "). Translate the status code into
                // something the UI can display — without this the
                // user just sees "Could not arm geofence" with no
                // indication of *why* (GEOFENCE_NOT_AVAILABLE when
                // location is off, TOO_MANY_GEOFENCES when the app
                // already has 100 registered, etc.).
                val (humanMessage, code) = when (e) {
                    is com.google.android.gms.common.api.ApiException ->
                        humanizeGeofenceError(e.statusCode) to e.statusCode
                    else -> (e.message ?: "unknown_error") to -1
                }
                Log.w(
                    TAG,
                    "addGeofences failed for alarmId=$alarmId code=$code",
                    e,
                )
                result.success(
                    mapOf("added" to false, "error" to humanMessage, "code" to code),
                )
            }
    }

    // -------------------------------------------------------------------------
    // Boot re-arm
    // -------------------------------------------------------------------------

    /**
     * Re-register every persisted LOCATION-typed [AlarmScheduler.AlarmData]
     * entry with the [com.google.android.gms.location.GeofencingClient].
     *
     * **Why this exists:** the OS wipes Play Services geofence
     * registrations on reboot (`GeofencingClient` registrations are
     * not durable across reboots). The persisted
     * [AlarmScheduler.AlarmData] mirror in SharedPreferences
     * survives, but the live registration does not — so without
     * this re-arm an armed geofence alarm would silently disappear
     * the next time the device restarts. This is the single most
     * common cause of "my location alarm didn't fire" reports in
     * user testing.
     *
     * Called from [BootReceiver] on `BOOT_COMPLETED`,
     * `QUICKBOOT_POWERON` and `MY_PACKAGE_REPLACED`. The latter
     * matters because app updates also wipe Play Services
     * registrations.
     *
     * Failures are logged and swallowed:
     *  * Entries missing lat/lon/radius (persisted before this
     *    feature shipped, or corrupted) are skipped with a warning.
     *    The user has to re-arm the alarm once in the UI.
     *  * A failed `addGeofences` (missing Play Services, revoked
     *    permission, out-of-range radius) is logged but does not
     *    throw — a boot-path exception would leave the system in
     *    a half-armed state and the user with no visible signal.
     *  * The pending [com.google.android.gms.tasks.Task] is not
     *    awaited (a [android.content.BroadcastReceiver] cannot
     *    block on it anyway). The [com.google.android.gms.location.GeofencingClient]
     *    completes the registration on its own thread; success or
     *    failure is logged asynchronously.
     */
    @JvmStatic
    fun rearmPersistedGeofences(context: Context) {
        val all = AlarmScheduler.readAllPersisted(context)
        val locationEntries = all.filter { it.triggerType == "LOCATION" }
        if (locationEntries.isEmpty()) {
            Log.d(TAG, "Rearm: no LOCATION entries to re-register")
            return
        }
        var ok = 0
        var skipped = 0
        for (data in locationEntries) {
            val lat = data.latitude
            val lon = data.longitude
            val radius = data.radiusMeters
            if (lat == null || lon == null || radius == null) {
                Log.w(
                    TAG,
                    "Rearm: skipping alarmId=${data.alarmId} — missing lat/lon/radius " +
                        "(persisted before the rearm-on-boot feature, or corrupted entry)",
                )
                skipped++
                continue
            }
            if (radius !in 200..20_000) {
                Log.w(
                    TAG,
                    "Rearm: skipping alarmId=${data.alarmId} — radius $radius out of range",
                )
                skipped++
                continue
            }
            try {
                val client = LocationServices.getGeofencingClient(context)
                val geofence = Geofence.Builder()
                    .setRequestId(data.alarmId.toString())
                    .setCircularRegion(lat, lon, radius.toFloat())
                    .setExpirationDuration(-1L) // NEVER_EXPIRE
                    .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                    .build()
                val request = GeofencingRequest.Builder()
                    // INIT_TRIGGER_ENTER: same as addGeofence — fires
                    // immediately if the user is already inside the
                    // circle at re-registration time. Consistent
                    // with first-time arming behaviour.
                    .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                    .addGeofence(geofence)
                    .build()
                val pendingIntent = buildGeofencePendingIntent(context, data.alarmId)
                client.addGeofences(request, pendingIntent)
                    .addOnSuccessListener {
                        Log.d(TAG, "Rearm: geofence re-registered for alarmId=${data.alarmId}")
                    }
                    .addOnFailureListener { e ->
                        Log.w(
                            TAG,
                            "Rearm: failed to re-register geofence for alarmId=${data.alarmId}",
                            e,
                        )
                    }
                ok++
            } catch (se: SecurityException) {
                // Location permission was revoked before boot
                // completed (rare but possible). Skip — the user
                // will see the _GeofenceHealthBanner next time they
                // open the app.
                Log.w(TAG, "Rearm: SecurityException for alarmId=${data.alarmId}", se)
                skipped++
            } catch (e: Exception) {
                Log.w(TAG, "Rearm: unexpected error for alarmId=${data.alarmId}", e)
                skipped++
            }
        }
        Log.d(
            TAG,
            "Rearm: re-registered $ok/${locationEntries.size} geofence(s) (skipped $skipped)",
        )
    }

    private fun removeGeofence(
        context: Context,
        alarmId: Int,
        result: MethodChannel.Result,
    ) {
        if (alarmId < 0) {
            result.success(mapOf("removed" to false, "error" to "invalid_alarm_id"))
            return
        }
        val client = LocationServices.getGeofencingClient(context)
        val pendingIntent = buildGeofencePendingIntent(context, alarmId)
        client.removeGeofences(pendingIntent)
            .addOnSuccessListener {
                Log.d(TAG, "Geofence removed for alarmId=$alarmId")
                // Clean up the persisted metadata so we don't try to
                // re-arm a geofence that the user explicitly disarmed.
                AlarmScheduler.removePersistedAlarmData(context, alarmId)
                result.success(mapOf("removed" to true))
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "removeGeofences failed for alarmId=$alarmId", e)
                result.success(
                    mapOf("removed" to false, "error" to (e.message ?: "unknown")),
                )
            }
    }

    /**
     * Build the [PendingIntent] that the GeofencingClient fires
     * when the user crosses into the registered circle. Each
     * alarmId gets its own PendingIntent (so the request code is
     * unique), which lets the receiver disambiguate which alarm
     * fired.
     */
    private fun buildGeofencePendingIntent(
        context: Context,
        alarmId: Int,
    ): PendingIntent {
        val intent = Intent(context, GeofenceTransitionReceiver::class.java).apply {
            // Disambiguate from the alarm fire PendingIntent
            // (AlarmScheduler) — they share the same receiver
            // class? No, this is a different receiver class
            // entirely. Keeping the action explicit makes the
            // intent filter easy to read.
            action = ACTION_GEOFENCE_TRANSITION
            putExtra(GeofenceTransitionReceiver.EXTRA_ALARM_ID, alarmId)
            // Unique per alarmId via the data URI — same pattern
            // as AlarmScheduler.buildFireIntent.
            data = Uri.parse("wakey://geofence/$alarmId")
        }
        return PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // -------------------------------------------------------------------------
    // Battery optimization
    // -------------------------------------------------------------------------

    private fun isBatteryOptimizationExempt(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestBatteryOptimizationExemption(
        activity: android.app.Activity,
    ) {
        if (isBatteryOptimizationExempt(activity)) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
        intent.data = Uri.parse("package:${activity.packageName}")
        try {
            activity.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to start battery-opt Settings intent", e)
        }
    }

    /**
     * Translate a Play Services geofence API status code into a
     * short, user-readable string. The raw codes are integers from
     * `GeofenceStatusCodes` (1000-range) and `CommonStatusCodes`
     * (0–21), and the human messages are usually empty strings.
     * Surfacing the *cause* — not just "geofence failed" — is the
     * single biggest usability win for this feature, because the
     * most common cause is "Location is off" (1004) and the fix is
     * a one-tap Settings toggle.
     *
     * Codes recognized:
     *  * 1000 — `GEOFENCE_TOO_MANY_GEOFENCES` (per-app cap of 100)
     *  * 1001 — `GEOFENCE_TOO_MANY_PENDING_INTENTS` (per-app cap)
     *  * 1004 — `GEOFENCE_NOT_AVAILABLE` (location services off)
     *  * 13   — `SUCCESS` (rare in failure path; defensive)
     *  * 6    — `INTERNAL_ERROR`
     *  * 7    — `ERROR` (generic)
     *  * anything else — generic "Geofence setup failed (code N)".
     */
    private fun humanizeGeofenceError(code: Int): String {
        return when (code) {
            1000 -> "Too many geofences registered (max 100). Disarm an existing location alarm and try again."
            1001 -> "Too many pending geofence intents. Restart the device and try again."
            1004 -> "Location services are off. Turn on Location in system Settings and try again."
            1005 -> "Geofence is no longer available. Update Google Play Services and try again."
            com.google.android.gms.common.api.CommonStatusCodes.SUCCESS ->
                "Unknown geofence error"
            com.google.android.gms.common.api.CommonStatusCodes.INTERNAL_ERROR ->
                "Internal error. Try again."
            com.google.android.gms.common.api.CommonStatusCodes.ERROR ->
                "Geofence setup failed. Try again."
            com.google.android.gms.common.api.CommonStatusCodes.DEVELOPER_ERROR ->
                "Stale geofence state. Reboot the device and try again. " +
                    "If the problem persists, clear the app storage in " +
                    "Android Settings \u2192 Apps \u2192 Wakey-Wakey \u2192 Storage."
            else -> "Geofence setup failed (code $code)"
        }
    }

    // Kept here so the same file declares the geofence constants
    // used by the receiver too. ACTION_GEOFENCE_TRANSITION is the
    // action filter the receiver is registered against in the
    // manifest.
    private const val ACTION_GEOFENCE_TRANSITION = "com.wakeywakey.action.GEOFENCE_TRANSITION"
}
