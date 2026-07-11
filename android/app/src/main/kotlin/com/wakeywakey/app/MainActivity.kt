package com.wakeywakey.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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
                    Log.d(TAG, "alarmFiredEventStream listener attached")
                }

                override fun onCancel(arguments: Any?) {
                    alarmEventSink = null
                    Log.d(TAG, "alarmFiredEventStream listener detached")
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
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            ALARM_NOTIFICATION_CHANNEL_ID,
            "Alarm alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Ringing alarms and timers"
            setBypassDnd(true)
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
     * Schedule a time-based alarm with AlarmManager.setAlarmClock().
     *
     * This is the only API that (a) shows the alarm in the system tray and
     * (b) fires through Doze without requiring SCHEDULE_EXACT_ALARM on
     * API 31+ — both of which an actual alarm app needs.
     *
     * The fire (operation) PendingIntent goes to [AlarmReceiver] and
     * carries all alarm data as extras. The show PendingIntent points at
     * [RingingActivity] and is what the system fires when the user taps
     * the status-bar alarm icon.
     *
     * Returning `{scheduled: false}` (rather than throwing) keeps the
     * Dart-side contract symmetric: callers can check one boolean.
     */
    private fun handleScheduleAlarm(payload: Map<String, Any?>, result: MethodChannel.Result) {
        val alarmId = (payload["alarmId"] as? Number)?.toInt() ?: -1
        val hour = (payload["timeHour"] as? Number)?.toInt()
        val minute = (payload["timeMinute"] as? Number)?.toInt()

        if (alarmId < 0 || hour == null || minute == null) {
            Log.w(TAG, "scheduleAlarm rejected: missing alarmId/hour/minute in $payload")
            result.success(mapOf("scheduled" to false, "error" to "missing required fields"))
            return
        }

        val triggerAtMillis = NextAlarmTime.compute(
            hour,
            minute,
            payload["repeatDays"] as? String,
        )
        val label = payload["label"] as? String ?: "Alarm"
        val soundUri = payload["soundUri"] as? String
        val vibrate = (payload["vibrate"] as? Boolean) ?: true
        val snoozeDurationMin = (payload["snoozeDurationMin"] as? Number)?.toInt() ?: 10
        val maxSnoozeCount = (payload["maxSnoozeCount"] as? Number)?.toInt() ?: -1

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        if (alarmManager == null) {
            Log.e(TAG, "scheduleAlarm: AlarmManager service unavailable")
            result.error(
                "alarm_manager_unavailable",
                "AlarmManager service is unavailable.",
                null,
            )
            return
        }

        val firePendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId,
            Intent(this, AlarmReceiver::class.java).apply {
                putExtra(AlarmReceiver.EXTRA_ALARM_ID, alarmId)
                putExtra(AlarmReceiver.EXTRA_LABEL, label)
                putExtra(AlarmReceiver.EXTRA_SOUND_URI, soundUri.orEmpty())
                putExtra(AlarmReceiver.EXTRA_VIBRATE, vibrate)
                putExtra(AlarmReceiver.EXTRA_SNOOZE_DURATION_MIN, snoozeDurationMin)
                putExtra(AlarmReceiver.EXTRA_MAX_SNOOZE_COUNT, maxSnoozeCount)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val showPendingIntent = PendingIntent.getActivity(
            this,
            alarmId,
            Intent(this, RingingActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(AlarmReceiver.EXTRA_ALARM_ID, alarmId)
                putExtra(AlarmReceiver.EXTRA_LABEL, label)
                putExtra(AlarmReceiver.EXTRA_SOUND_URI, soundUri.orEmpty())
                putExtra(AlarmReceiver.EXTRA_VIBRATE, vibrate)
                putExtra(AlarmReceiver.EXTRA_SNOOZE_DURATION_MIN, snoozeDurationMin)
                putExtra(AlarmReceiver.EXTRA_MAX_SNOOZE_COUNT, maxSnoozeCount)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        try {
            val info = AlarmManager.AlarmClockInfo(triggerAtMillis, showPendingIntent)
            alarmManager.setAlarmClock(info, firePendingIntent)
            Log.d(TAG, "Scheduled alarm id=$alarmId at=$triggerAtMillis")
            result.success(mapOf("scheduled" to true, "triggerAtMillis" to triggerAtMillis))
        } catch (se: SecurityException) {
            Log.e(TAG, "setAlarmClock rejected for id=$alarmId", se)
            result.success(
                mapOf("scheduled" to false, "error" to (se.message ?: "security")),
            )
        }
    }

    /**
     * Cancel a previously-scheduled alarm. Uses FLAG_NO_CREATE so we
     * don't *create* a PendingIntent just to cancel it; if there is no
     * matching PendingIntent registered with AlarmManager, there is
     * nothing to cancel and the call is a no-op.
     */
    private fun handleCancelAlarm(payload: Map<String, Any?>, result: MethodChannel.Result) {
        val alarmId = (payload["alarmId"] as? Number)?.toInt() ?: -1
        if (alarmId < 0) {
            Log.w(TAG, "cancelAlarm rejected: missing alarmId in $payload")
            result.success(mapOf("cancelled" to false, "error" to "missing alarmId"))
            return
        }

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        if (alarmManager == null) {
            Log.e(TAG, "cancelAlarm: AlarmManager service unavailable")
            result.error(
                "alarm_manager_unavailable",
                "AlarmManager service is unavailable.",
                null,
            )
            return
        }

        // Must match the component used at schedule time. No extras
        // needed for equality (PendingIntent.filterEquals ignores them),
        // but the same Intent shape is required.
        val existing = PendingIntent.getBroadcast(
            this,
            alarmId,
            Intent(this, AlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )

        if (existing != null) {
            alarmManager.cancel(existing)
            Log.d(TAG, "Cancelled alarm id=$alarmId")
        } else {
            Log.d(TAG, "No PendingIntent to cancel for id=$alarmId (not scheduled?)")
        }
        result.success(mapOf("cancelled" to true))
    }

    companion object {
        private const val TAG = "WakeyAlarmBridge"
        private const val ALARM_BRIDGE_CHANNEL = "com.wakeywakey/alarm_bridge"
        private const val ALARM_EVENTS_CHANNEL = "com.wakeywakey/alarm_events"
        private const val PERMISSIONS_CHANNEL = "com.wakeywakey/permissions"
        private const val ALARM_NOTIFICATION_CHANNEL_ID = "alarm_alerts"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
    }
}
