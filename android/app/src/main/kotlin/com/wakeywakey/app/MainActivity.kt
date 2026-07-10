package com.wakeywakey.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
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
                    Log.d(TAG, "Received scheduleAlarm stub call: ${call.arguments}")
                    result.success(mapOf("scheduled" to true))
                }

                "cancelAlarm" -> {
                    Log.d(TAG, "Received cancelAlarm stub call: ${call.arguments}")
                    result.success(mapOf("cancelled" to true))
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

    companion object {
        private const val TAG = "WakeyAlarmBridge"
        private const val ALARM_BRIDGE_CHANNEL = "com.wakeywakey/alarm_bridge"
        private const val ALARM_EVENTS_CHANNEL = "com.wakeywakey/alarm_events"
        private const val PERMISSIONS_CHANNEL = "com.wakeywakey/permissions"
        private const val ALARM_NOTIFICATION_CHANNEL_ID = "alarm_alerts"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
    }
}
