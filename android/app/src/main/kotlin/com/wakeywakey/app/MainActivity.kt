package com.wakeywakey.app

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alarmEventSink: EventChannel.EventSink? = null
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var pendingPickRingtoneResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannels()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ALARM_BRIDGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payload = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                    handleScheduleAlarm(payload, result)
                }

                "cancelAlarm" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payload = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                    handleCancelAlarm(payload, result)
                }

                "pickRingtone" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payload = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                    handlePickRingtone(payload, result)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ALARM_EVENTS_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    alarmEventSink = events
                    events?.let { AlarmEventBus.attach(it) }
                    Log.d(TAG, "alarmEventStream listener attached")
                }

                override fun onCancel(arguments: Any?) {
                    alarmEventSink = null
                    AlarmEventBus.detach()
                    Log.d(TAG, "alarmEventStream listener detached")
                }
            },
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSIONS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNotificationPermissionStatus" -> {
                    result.success(notificationPermissionStatus())
                }

                "requestNotificationPermission" -> {
                    requestNotificationPermission(result)
                }

                "canScheduleExactAlarms" -> {
                    result.success(canScheduleExactAlarms())
                }

                "requestExactAlarmPermission" -> {
                    result.success(requestExactAlarmPermission())
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GEOFENCE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            GeofenceController.handleMethodCall(
                this,
                call.method,
                call.arguments as? Map<String, Any?>,
                result,
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != NOTIFICATION_PERMISSION_REQUEST_CODE) {
            return
        }

        pendingNotificationResult?.success(notificationPermissionStatus())
        pendingNotificationResult = null
    }

    private fun createNotificationChannels() {
        // The channel is now created up-front in WakeyApplication.onCreate
        // so that the cold-start path (AlarmManager broadcast waking the
        // process before any Activity has run) also has a configured
        // channel. We keep this call as an idempotent re-declaration in
        // case the user re-installs or somehow loses the channel — it's
        // a no-op if the channel already exists with the same id.
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            WakeyApplication.ALARM_NOTIFICATION_CHANNEL_ID,
            "Alarm alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Ringing alarms and timers"
            setBypassDnd(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            enableVibration(true)
        }

        notificationManager.createNotificationChannel(channel)
    }

    private fun notificationPermissionStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return "notRequired"
        }

        return if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            "granted"
        } else {
            "denied"
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success("notRequired")
            return
        }

        if (notificationPermissionStatus() == "granted") {
            result.success("granted")
            return
        }

        if (pendingNotificationResult != null) {
            result.error(
                "notification_permission_request_active",
                "A notification permission request is already active.",
                null,
            )
            return
        }

        pendingNotificationResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun canScheduleExactAlarms(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true
        }

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    private fun requestExactAlarmPermission(): Boolean {
        if (canScheduleExactAlarms()) {
            return true
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val action = "android.app.action.REQUEST_SCHEDULE_EXACT_ALARM"
            val intent = Intent(action, Uri.parse("package:$packageName"))
            startActivity(intent)
        }

        return canScheduleExactAlarms()
    }

    // -------------------------------------------------------------------------
    // Alarm bridge
    // -------------------------------------------------------------------------

    /**
     * Schedule a time-based alarm by translating the Dart payload
     * into an [AlarmScheduler.AlarmData] and delegating to
     * [AlarmScheduler.schedule]. All the AlarmManager wiring
     * (fire PendingIntent, show PendingIntent, SharedPreferences
     * persistence) lives in [AlarmScheduler] — this method's only
     * job is payload validation and channel-result reporting.
     *
     * Returning `{scheduled: false}` (rather than throwing) keeps
     * the Dart-side contract symmetric: callers can check one
     * boolean.
     *
     * Supports two payload shapes:
     *
     *  1. **Wall-clock alarm** — Dart provides `timeHour` /
     *     `timeMinute` (and optional `repeatDays`). The fire time
     *     is computed via [NextAlarmTime.compute].
     *  2. **Absolute trigger (timer)** — Dart provides an explicit
     *     `triggerAtMillis` epoch-millis. The fire time is used
     *     directly. This is how Iteration 3 timers reuse the
     *     AlarmManager pipeline (see `requirements.md` §5.4).
     *
     * The optional `triggerType` field is `"TIME"` (default) for
     * alarms and `"TIMER"` for timers; the native UI uses it to
     * decide on the title/subtitle in [RingingActivity].
     */
    private fun handleScheduleAlarm(payload: Map<String, Any?>, result: MethodChannel.Result) {
        val alarmId = (payload["alarmId"] as? Number)?.toInt() ?: -1
        val explicitTrigger = (payload["triggerAtMillis"] as? Number)?.toLong()
        val hour = (payload["timeHour"] as? Number)?.toInt()
        val minute = (payload["timeMinute"] as? Number)?.toInt()
        val triggerType = (payload["triggerType"] as? String) ?: "TIME"

        if (alarmId < 0 || explicitTrigger == null && (hour == null || minute == null)) {
            Log.w(TAG, "scheduleAlarm rejected: missing alarmId/time fields in $payload")
            result.success(mapOf("scheduled" to false, "error" to "missing required fields"))
            return
        }

        // For the alarm path, use the supplied hour/minute as
        // placeholders. They are recorded in persistence so the
        // BootReceiver can re-schedule a one-shot if needed, but
        // for one-shot alarms the actual fire time is whatever the
        // caller computed (or `NextAlarmTime` derived). For the
        // timer path the values are 0/0 — they are never used
        // because timers never repeat and the explicit trigger time
        // is canonical.
        val effectiveHour = hour ?: 0
        val effectiveMinute = minute ?: 0

        val data = AlarmScheduler.AlarmData(
            alarmId = alarmId,
            timeHour = effectiveHour,
            timeMinute = effectiveMinute,
            repeatDays = payload["repeatDays"] as? String,
            label = payload["label"] as? String ?: "Alarm",
            soundUri = (payload["soundUri"] as? String) ?: "",
            vibrate = (payload["vibrate"] as? Boolean) ?: true,
            snoozeDurationMin = (payload["snoozeDurationMin"] as? Number)?.toInt() ?: 10,
            maxSnoozeCount = (payload["maxSnoozeCount"] as? Number)?.toInt() ?: -1,
            currentSnoozeCount = 0,
            triggerType = triggerType,
        )

        val triggerAtMillis: Long = explicitTrigger
            ?: NextAlarmTime.compute(effectiveHour, effectiveMinute, data.repeatDays)

        val ok = AlarmScheduler.schedule(this, data, triggerAtMillis)
        result.success(
            if (ok) {
                mapOf("scheduled" to true, "triggerAtMillis" to triggerAtMillis)
            } else {
                mapOf("scheduled" to false, "error" to "alarm_manager_unavailable")
            },
        )
    }

    /**
     * Cancel a previously-scheduled alarm. Delegates to
     * [AlarmScheduler.cancel], which handles the AlarmManager
     * cancel call and the SharedPreferences cleanup in one place.
     */
    private fun handleCancelAlarm(payload: Map<String, Any?>, result: MethodChannel.Result) {
        val alarmId = (payload["alarmId"] as? Number)?.toInt() ?: -1
        if (alarmId < 0) {
            Log.w(TAG, "cancelAlarm rejected: missing alarmId in $payload")
            result.success(mapOf("cancelled" to false, "error" to "missing alarmId"))
            return
        }
        AlarmScheduler.cancel(this, alarmId)
        result.success(mapOf("cancelled" to true))
    }

    // -------------------------------------------------------------------------
    // Ringtone picker
    // -------------------------------------------------------------------------

    /**
     * Launch the system ringtone picker (filtered to alarm sounds) and
     * report the picked URI back to Dart.
     *
     * Payload:
     *  - `currentUri`: String? — the alarm's currently-selected ringtone,
     *    so the picker can pre-select it. May be null for new alarms.
     *
     * Result:
     *  - `{ "uri": String }` on success (the picked URI as a string,
     *    or null/empty if the user cancelled).
     *
     * Implementation notes:
     *  - Uses `startActivityForResult` because the picker returns its
     *    selection via `onActivityResult` (the modern `ActivityResultLauncher`
     *    API would be cleaner but requires registering in `onCreate`,
     *    which interacts awkwardly with the `FlutterActivity` lifecycle).
     *  - Only one picker can be active at a time; if a second
     *    `pickRingtone` call arrives while a previous one is still open,
     *    it returns an error rather than queueing.
     */
    private fun handlePickRingtone(payload: Map<String, Any?>, result: MethodChannel.Result) {
        if (pendingPickRingtoneResult != null) {
            result.error(
                "ringtone_picker_active",
                "A ringtone picker is already active.",
                null,
            )
            return
        }

        val currentUriString = payload["currentUri"] as? String
        val currentUri = if (currentUriString.isNullOrBlank()) {
            null
        } else {
            runCatching { Uri.parse(currentUriString) }.getOrNull()
        }

        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Choose alarm sound")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, currentUri)
        }

        pendingPickRingtoneResult = result
        try {
            startActivityForResult(intent, PICK_RINGTONE_REQUEST_CODE)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start ringtone picker", e)
            pendingPickRingtoneResult = null
            result.success(mapOf("uri" to null, "error" to "picker_unavailable"))
        }
    }

    @Deprecated("Required to support startActivityForResult on API levels where the new Activity Result API is not viable.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_RINGTONE_REQUEST_CODE) return

        val pending = pendingPickRingtoneResult
        pendingPickRingtoneResult = null
        if (pending == null) return

        if (resultCode != Activity.RESULT_OK) {
            pending.success(mapOf("uri" to null))
            return
        }

        val pickedUri: Uri? = data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        // A null URI here means the user picked "Silent" — represent that
        // as an empty string so the Dart side can distinguish it from
        // "user cancelled" (which we already handled above).
        pending.success(mapOf("uri" to (pickedUri?.toString() ?: "")))
    }

    companion object {
        private const val TAG = "WakeyAlarmBridge"
        private const val ALARM_BRIDGE_CHANNEL = "com.wakeywakey/alarm_bridge"
        private const val ALARM_EVENTS_CHANNEL = "com.wakeywakey/alarm_events"
        private const val PERMISSIONS_CHANNEL = "com.wakeywakey/permissions"
        private const val GEOFENCE_CHANNEL = "com.wakeywakey/geofence"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
        private const val PICK_RINGTONE_REQUEST_CODE = 2001
    }
}
