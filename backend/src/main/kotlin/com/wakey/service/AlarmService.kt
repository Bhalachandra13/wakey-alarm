package com.wakey.service

import com.wakey.exception.ResourceNotFoundException
import com.wakey.model.Alarm
import com.wakey.model.AlarmTriggerType
import com.wakey.model.RepeatRule
import com.wakey.repository.AlarmRepository
import com.wakey.scheduler.QuartzJobScheduler
import mu.KotlinLogging
import org.quartz.Scheduler
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.stereotype.Service
import java.time.LocalTime
import java.util.*

private val logger = KotlinLogging.logger {}

@Service
class AlarmService(
    private val alarmRepository: AlarmRepository,
    private val geofenceService: GeofenceService,
    private val notificationService: NotificationService,
    @Autowired(required = false)
    private val quartz: Scheduler? = null
) {

    fun createAlarm(alarm: Alarm): Alarm {
        val saved = alarmRepository.save(alarm)
        
        if (alarm.triggerType == AlarmTriggerType.TIME || alarm.triggerType == AlarmTriggerType.COMBINED) {
            scheduleAlarm(saved)
        }

        logger.info { "Alarm created: ${saved.id}" }
        return saved
    }

    fun updateAlarm(alarmId: UUID, userId: UUID, updates: Alarm): Alarm {
        val alarm = getAlarm(alarmId, userId)
        
        // Cancel existing job if it exists
        if (alarm.quartzJobKey != null) {
            cancelAlarm(alarm)
        }

        val updated = alarm.copy(
            label = updates.label,
            triggerType = updates.triggerType,
            scheduledTime = updates.scheduledTime,
            repeatRule = updates.repeatRule,
            customDays = updates.customDays,
            geofenceZone = updates.geofenceZone,
            snoozeDurationMinutes = updates.snoozeDurationMinutes,
            isActive = updates.isActive,
            ringtone = updates.ringtone,
            gradualVolume = updates.gradualVolume
        )

        val saved = alarmRepository.save(updated)

        if (saved.isActive && (saved.triggerType == AlarmTriggerType.TIME || saved.triggerType == AlarmTriggerType.COMBINED)) {
            scheduleAlarm(saved)
        }

        logger.info { "Alarm updated: $alarmId" }
        return saved
    }

    fun getAlarm(alarmId: UUID, userId: UUID): Alarm {
        return alarmRepository.findByIdAndUserId(alarmId, userId)
            ?: throw ResourceNotFoundException("Alarm not found: $alarmId")
    }

    fun getAlarmsByUser(userId: UUID): List<Alarm> {
        return alarmRepository.findAllByUserId(userId)
    }

    fun getActiveAlarmsByUser(userId: UUID): List<Alarm> {
        return alarmRepository.findAllByUserIdAndIsActive(userId, true)
    }

    fun deleteAlarm(alarmId: UUID, userId: UUID) {
        val alarm = getAlarm(alarmId, userId)
        
        if (alarm.quartzJobKey != null) {
            cancelAlarm(alarm)
        }

        alarmRepository.delete(alarm)
        logger.info { "Alarm deleted: $alarmId" }
    }

    fun toggleAlarm(alarmId: UUID, userId: UUID): Alarm {
        val alarm = getAlarm(alarmId, userId)
        val updated = alarm.copy(isActive = !alarm.isActive)

        if (!updated.isActive && alarm.quartzJobKey != null) {
            cancelAlarm(alarm)
        } else if (updated.isActive && (updated.triggerType == AlarmTriggerType.TIME || updated.triggerType == AlarmTriggerType.COMBINED)) {
            scheduleAlarm(updated)
        }

        val saved = alarmRepository.save(updated)
        logger.debug { "Alarm toggled: $alarmId, active: ${saved.isActive}" }
        return saved
    }

    fun triggerAlarm(alarm: Alarm) {
        logger.info { "Triggering alarm: ${alarm.id}" }

        // Send notifications
        notificationService.sendAlarmNotification(alarm)

        // Deactivate if one-time alarm
        if (alarm.repeatRule == RepeatRule.ONCE) {
            val updated = alarm.copy(isActive = false)
            alarmRepository.save(updated)
            logger.debug { "One-time alarm deactivated: ${alarm.id}" }
        }
    }

    fun onGeofenceTransition(event: GeofenceTransitionEvent) {
        logger.debug { "Processing geofence transition: ${event.zoneName}" }

        val alarms = alarmRepository.findAllByGeofenceZoneId(event.zoneId)
            .filter { it.isActive }

        for (alarm in alarms) {
            val shouldTrigger = when (alarm.triggerType) {
                AlarmTriggerType.GEO_ENTER -> event.transitionType == GeoTransitionType.ENTER
                AlarmTriggerType.GEO_EXIT -> event.transitionType == GeoTransitionType.EXIT
                AlarmTriggerType.COMBINED -> {
                    val timeMatch = isWithinTimeWindow(alarm.scheduledTime, 5)
                    (event.transitionType == GeoTransitionType.ENTER) && timeMatch
                }
                else -> false
            }

            if (shouldTrigger) {
                triggerAlarm(alarm)
            }
        }
    }

    private fun scheduleAlarm(alarm: Alarm) {
        if (quartz == null) {
            logger.warn { "Quartz scheduler not available, skipping job scheduling" }
            return
        }

        try {
            val jobKey = QuartzJobScheduler.scheduleTimeAlarm(
                quartz,
                alarm.id,
                alarm.user.id,
                alarm.scheduledTime ?: LocalTime.of(0, 0),
                alarm.repeatRule.toString()
            )
            
            if (jobKey != null) {
                val updated = alarm.copy(quartzJobKey = jobKey)
                alarmRepository.save(updated)
                logger.debug { "Alarm job scheduled: ${alarm.id}" }
            }
        } catch (e: Exception) {
            logger.error(e) { "Failed to schedule alarm: ${alarm.id}" }
        }
    }

    private fun cancelAlarm(alarm: Alarm) {
        if (quartz == null) {
            logger.warn { "Quartz scheduler not available" }
            return
        }

        try {
            QuartzJobScheduler.cancelAlarm(quartz, alarm.id)
            val updated = alarm.copy(quartzJobKey = null)
            alarmRepository.save(updated)
            logger.debug { "Alarm job cancelled: ${alarm.id}" }
        } catch (e: Exception) {
            logger.error(e) { "Failed to cancel alarm: ${alarm.id}" }
        }
    }

    private fun isWithinTimeWindow(targetTime: LocalTime?, windowMinutes: Int): Boolean {
        if (targetTime == null) return false

        val now = LocalTime.now()
        val windowStart = targetTime.minusMinutes(windowMinutes.toLong())
        val windowEnd = targetTime.plusMinutes(windowMinutes.toLong())

        return now.isAfter(windowStart) && now.isBefore(windowEnd)
    }
}
