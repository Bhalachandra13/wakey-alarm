package com.wakeywakey.app

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alarmEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
    }

    companion object {
        private const val TAG = "WakeyAlarmBridge"
        private const val ALARM_BRIDGE_CHANNEL = "com.wakeywakey/alarm_bridge"
        private const val ALARM_EVENTS_CHANNEL = "com.wakeywakey/alarm_events"
    }
}
