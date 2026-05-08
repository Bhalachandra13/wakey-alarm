package com.wakey.service

import com.wakey.model.Alarm
import com.wakey.model.AlarmTriggerType
import com.wakey.model.User
import io.mockk.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.DisplayName
import org.springframework.messaging.simp.SimpMessagingTemplate
import java.util.*
import kotlin.test.assertEquals

@DisplayName("NotificationService Test Suite")
class NotificationServiceTest {

    private val messagingTemplate = mockk<SimpMessagingTemplate>(relaxed = true)
    private val notificationService = NotificationService(messagingTemplate)

    private val userId = UUID.randomUUID()
    private val user = User(id = userId, email = "test@example.com", passwordHash = "hash", fcmToken = "fcm_token_123")

    @Test
    @DisplayName("sendAlarmNotification: sends WebSocket message")
    fun testSendAlarmNotificationWebSocket() {
        val alarm = Alarm(
            id = UUID.randomUUID(),
            user = user,
            label = "Wake up",
            triggerType = AlarmTriggerType.TIME
        )

        notificationService.sendAlarmNotification(alarm)

        verify { messagingTemplate.convertAndSend(match { it.contains(userId.toString()) }, any()) }
    }

    @Test
    @DisplayName("sendAlarmNotification: handles missing FCM token gracefully")
    fun testSendAlarmNotificationNoFcmToken() {
        val userWithoutFcm = user.copy(fcmToken = null)
        val alarm = Alarm(
            id = UUID.randomUUID(),
            user = userWithoutFcm,
            label = "Wake up",
            triggerType = AlarmTriggerType.TIME
        )

        // Should not throw exception
        notificationService.sendAlarmNotification(alarm)

        verify { messagingTemplate.convertAndSend(any(), any()) }
    }

    @Test
    @DisplayName("sendGeofenceUpdate: broadcasts zone status update")
    fun testSendGeofenceUpdate() {
        val event = GeofenceTransitionEvent(
            userId = userId,
            zoneId = UUID.randomUUID(),
            zoneName = "Office",
            transitionType = GeoTransitionType.ENTER
        )

        notificationService.sendGeofenceUpdate(userId, event)

        verify { messagingTemplate.convertAndSend(match { it.contains(userId.toString()) }, any()) }
    }
}
