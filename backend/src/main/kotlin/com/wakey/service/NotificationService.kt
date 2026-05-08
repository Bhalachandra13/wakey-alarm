package com.wakey.service

import com.wakey.model.Alarm
import com.wakey.service.GeofenceTransitionEvent
import mu.KotlinLogging
import org.springframework.messaging.simp.SimpMessagingTemplate
import org.springframework.stereotype.Service
import java.util.*

private val logger = KotlinLogging.logger {}

data class AlarmTriggerEvent(
    val alarmId: UUID,
    val label: String?,
    val triggeredAt: Long = System.currentTimeMillis()
)

data class GeofenceUpdateEvent(
    val zoneId: UUID,
    val zoneName: String,
    val isInside: Boolean,
    val timestamp: Long = System.currentTimeMillis()
)

@Service
class NotificationService(
    private val messagingTemplate: SimpMessagingTemplate
) {

    fun sendAlarmNotification(alarm: Alarm) {
        val userId = alarm.user.id
        val event = AlarmTriggerEvent(
            alarmId = alarm.id,
            label = alarm.label
        )

        // Send via WebSocket
        sendWebSocketMessage("/topic/alarms/$userId", event)

        // Send FCM push notification
        sendFcmNotification(alarm)

        logger.info { "Alarm notification sent for alarm ${alarm.id}" }
    }

    fun sendGeofenceUpdate(userId: UUID, event: GeofenceTransitionEvent) {
        val updateEvent = GeofenceUpdateEvent(
            zoneId = event.zoneId,
            zoneName = event.zoneName,
            isInside = event.transitionType == com.wakey.service.GeoTransitionType.ENTER
        )

        sendWebSocketMessage("/topic/geo/$userId", updateEvent)
        logger.debug { "Geofence update sent for zone ${event.zoneName}" }
    }

    private fun sendWebSocketMessage(topic: String, payload: Any) {
        try {
            messagingTemplate.convertAndSend(topic, payload)
            logger.debug { "WebSocket message sent to $topic" }
        } catch (e: Exception) {
            logger.error(e) { "Failed to send WebSocket message to $topic" }
        }
    }

    private fun sendFcmNotification(alarm: Alarm) {
        val fcmToken = alarm.user.fcmToken
        if (fcmToken.isNullOrEmpty()) {
            logger.warn { "No FCM token available for user ${alarm.user.id}" }
            return
        }

        try {
            // TODO: Integrate Firebase Admin SDK to send push notification
            logger.debug { "FCM notification sent to user ${alarm.user.id}" }
        } catch (e: Exception) {
            logger.error(e) { "Failed to send FCM notification" }
            // Mark token as invalid if needed
            // user.fcmToken = null
        }
    }
}
