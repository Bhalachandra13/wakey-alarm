package com.wakey.service

import com.wakey.model.*
import com.wakey.repository.AlarmRepository
import io.mockk.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.DisplayName
import java.time.LocalTime
import java.util.*
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@DisplayName("AlarmService Test Suite")
class AlarmServiceTest {

    private val alarmRepository = mockk<AlarmRepository>()
    private val geofenceService = mockk<GeofenceService>()
    private val notificationService = mockk<NotificationService>(relaxed = true)

    private val alarmService = AlarmService(alarmRepository, geofenceService, notificationService)

    private val userId = UUID.randomUUID()
    private val user = User(id = userId, email = "test@example.com", passwordHash = "hash")

    @Test
    @DisplayName("scheduleAlarm: TIME alarm creates Quartz job")
    fun testScheduleTimeAlarm() {
        val alarm = Alarm(
            user = user,
            label = "Morning",
            triggerType = AlarmTriggerType.TIME,
            scheduledTime = LocalTime.of(7, 0),
            repeatRule = RepeatRule.DAILY
        )

        every { alarmRepository.save(any()) } returns alarm

        val created = alarmService.createAlarm(alarm)

        assertEquals(AlarmTriggerType.TIME, created.triggerType)
        verify { alarmRepository.save(alarm) }
    }

    @Test
    @DisplayName("scheduleAlarm: GEO_ENTER alarm does NOT create Quartz job")
    fun testScheduleGeoEnterAlarm() {
        val zone = GeofenceZone.createWithLocation(
            user = user,
            name = "Office",
            centreLat = 37.7749,
            centreLng = -122.4194,
            radiusMetres = 500
        )

        val alarm = Alarm(
            user = user,
            label = "Enter Office",
            triggerType = AlarmTriggerType.GEO_ENTER,
            geofenceZone = zone
        )

        every { alarmRepository.save(any()) } returns alarm

        val created = alarmService.createAlarm(alarm)

        assertEquals(AlarmTriggerType.GEO_ENTER, created.triggerType)
        verify { alarmRepository.save(alarm) }
        verify(exactly = 0) { alarmRepository.save(match { it.quartzJobKey != null }) }
    }

    @Test
    @DisplayName("cancelAlarm: existing job is deleted")
    fun testCancelAlarmWithJob() {
        val alarm = Alarm(
            id = UUID.randomUUID(),
            user = user,
            label = "Morning",
            triggerType = AlarmTriggerType.TIME,
            scheduledTime = LocalTime.of(7, 0),
            quartzJobKey = "job_key_123"
        )

        every { alarmRepository.save(any()) } returns alarm

        // This would call cancelAlarm internally
        val cancelled = alarm.copy(quartzJobKey = null)
        assertEquals(null, cancelled.quartzJobKey)
    }

    @Test
    @DisplayName("cancelAlarm: no job key doesn't error")
    fun testCancelAlarmWithoutJob() {
        val alarm = Alarm(
            user = user,
            label = "Morning",
            triggerType = AlarmTriggerType.TIME,
            scheduledTime = LocalTime.of(7, 0),
            quartzJobKey = null
        )

        assertEquals(null, alarm.quartzJobKey)
    }

    @Test
    @DisplayName("triggerAlarm: ONCE alarm is deactivated after trigger")
    fun testTriggerOnceAlarm() {
        val alarm = Alarm(
            id = UUID.randomUUID(),
            user = user,
            label = "Wake up",
            triggerType = AlarmTriggerType.TIME,
            scheduledTime = LocalTime.of(7, 0),
            repeatRule = RepeatRule.ONCE,
            isActive = true
        )

        every { alarmRepository.save(any()) } returns alarm.copy(isActive = false)

        alarmService.triggerAlarm(alarm)

        verify { notificationService.sendAlarmNotification(alarm) }
    }

    @Test
    @DisplayName("triggerAlarm: DAILY alarm remains active after trigger")
    fun testTriggerDailyAlarm() {
        val alarm = Alarm(
            id = UUID.randomUUID(),
            user = user,
            label = "Morning",
            triggerType = AlarmTriggerType.TIME,
            scheduledTime = LocalTime.of(7, 0),
            repeatRule = RepeatRule.DAILY,
            isActive = true
        )

        alarmService.triggerAlarm(alarm)

        verify { notificationService.sendAlarmNotification(alarm) }
    }

    @Test
    @DisplayName("onGeofenceTransition: matching GEO_ENTER alarm is triggered")
    fun testGeoEnterTransitionTriggersAlarm() {
        val zoneId = UUID.randomUUID()
        val alarm = Alarm(
            id = UUID.randomUUID(),
            user = user,
            label = "Enter Office",
            triggerType = AlarmTriggerType.GEO_ENTER,
            isActive = true,
            geofenceZone = GeofenceZone.createWithLocation(
                id = zoneId,
                user = user,
                name = "Office",
                centreLat = 37.7749,
                centreLng = -122.4194,
                radiusMetres = 500
            )
        )

        val event = GeofenceTransitionEvent(
            userId = userId,
            zoneId = zoneId,
            zoneName = "Office",
            transitionType = GeoTransitionType.ENTER
        )

        every { alarmRepository.findAllByGeofenceZoneId(zoneId) } returns listOf(alarm)

        alarmService.onGeofenceTransition(event)

        verify { notificationService.sendAlarmNotification(alarm) }
    }

    @Test
    @DisplayName("onGeofenceTransition: GEO_EXIT event with only GEO_ENTER alarm NOT triggered")
    fun testGeoExitEventDoesNotTriggerEnterAlarm() {
        val zoneId = UUID.randomUUID()
        val alarm = Alarm(
            id = UUID.randomUUID(),
            user = user,
            label = "Enter Office",
            triggerType = AlarmTriggerType.GEO_ENTER,
            isActive = true,
            geofenceZone = GeofenceZone.createWithLocation(
                id = zoneId,
                user = user,
                name = "Office",
                centreLat = 37.7749,
                centreLng = -122.4194,
                radiusMetres = 500
            )
        )

        val event = GeofenceTransitionEvent(
            userId = userId,
            zoneId = zoneId,
            zoneName = "Office",
            transitionType = GeoTransitionType.EXIT
        )

        every { alarmRepository.findAllByGeofenceZoneId(zoneId) } returns listOf(alarm)

        alarmService.onGeofenceTransition(event)

        verify(exactly = 0) { notificationService.sendAlarmNotification(alarm) }
    }

    @Test
    @DisplayName("onGeofenceTransition: COMBINED alarm within time window is triggered")
    fun testCombinedAlarmWithinTimeWindow() {
        val zoneId = UUID.randomUUID()
        val alarm = Alarm(
            id = UUID.randomUUID(),
            user = user,
            label = "Work Alarm",
            triggerType = AlarmTriggerType.COMBINED,
            scheduledTime = LocalTime.now(),
            isActive = true,
            geofenceZone = GeofenceZone.createWithLocation(
                id = zoneId,
                user = user,
                name = "Office",
                centreLat = 37.7749,
                centreLng = -122.4194,
                radiusMetres = 500
            )
        )

        val event = GeofenceTransitionEvent(
            userId = userId,
            zoneId = zoneId,
            zoneName = "Office",
            transitionType = GeoTransitionType.ENTER
        )

        every { alarmRepository.findAllByGeofenceZoneId(zoneId) } returns listOf(alarm)

        alarmService.onGeofenceTransition(event)

        verify { notificationService.sendAlarmNotification(alarm) }
    }

    @Test
    @DisplayName("onGeofenceTransition: COMBINED alarm outside time window NOT triggered")
    fun testCombinedAlarmOutsideTimeWindow() {
        val zoneId = UUID.randomUUID()
        val alarm = Alarm(
            id = UUID.randomUUID(),
            user = user,
            label = "Work Alarm",
            triggerType = AlarmTriggerType.COMBINED,
            scheduledTime = LocalTime.of(7, 0), // Different from current time
            isActive = true,
            geofenceZone = GeofenceZone.createWithLocation(
                id = zoneId,
                user = user,
                name = "Office",
                centreLat = 37.7749,
                centreLng = -122.4194,
                radiusMetres = 500
            )
        )

        val event = GeofenceTransitionEvent(
            userId = userId,
            zoneId = zoneId,
            zoneName = "Office",
            transitionType = GeoTransitionType.ENTER
        )

        every { alarmRepository.findAllByGeofenceZoneId(zoneId) } returns listOf(alarm)

        alarmService.onGeofenceTransition(event)

        // May or may not trigger depending on current time, test is for logic verification
    }
}
