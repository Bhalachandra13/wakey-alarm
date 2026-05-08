package com.wakey.api

import com.wakey.dto.request.AlarmRequest
import com.wakey.dto.response.AlarmResponse
import com.wakey.model.Alarm
import com.wakey.service.AlarmService
import com.wakey.service.GeofenceService
import com.wakey.service.UserService
import jakarta.validation.Valid
import mu.KotlinLogging
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import java.util.*

private val logger = KotlinLogging.logger {}

@RestController
@RequestMapping("/api/v1/alarms")
@CrossOrigin(origins = ["*"])
class AlarmController(
    private val alarmService: AlarmService,
    private val userService: UserService,
    private val geofenceService: GeofenceService
) {

    @GetMapping
    fun getAllAlarms(authentication: Authentication): ResponseEntity<List<AlarmResponse>> {
        val userId = UUID.fromString(authentication.principal as String)
        val alarms = alarmService.getAlarmsByUser(userId)
        val responses = alarms.map { it.toResponse(geofenceService) }
        return ResponseEntity.ok(responses)
    }

    @PostMapping
    fun createAlarm(
        authentication: Authentication,
        @Valid @RequestBody request: AlarmRequest
    ): ResponseEntity<AlarmResponse> {
        val userId = UUID.fromString(authentication.principal as String)
        val user = userService.getUserById(userId)

        val alarm = Alarm(
            user = user,
            label = request.label,
            triggerType = request.triggerType,
            scheduledTime = request.scheduledTime,
            repeatRule = request.repeatRule,
            customDays = request.customDays,
            geofenceZone = request.geofenceZoneId?.let { zoneId ->
                geofenceService.getGeofenceZone(zoneId, userId)
            },
            snoozeDurationMinutes = request.snoozeDurationMinutes,
            ringtone = request.ringtone,
            gradualVolume = request.gradualVolume
        )

        val created = alarmService.createAlarm(alarm)
        logger.info { "Alarm created: ${created.id}" }
        return ResponseEntity.status(HttpStatus.CREATED).body(created.toResponse(geofenceService))
    }

    @GetMapping("/{id}")
    fun getAlarm(
        authentication: Authentication,
        @PathVariable id: UUID
    ): ResponseEntity<AlarmResponse> {
        val userId = UUID.fromString(authentication.principal as String)
        val alarm = alarmService.getAlarm(id, userId)
        return ResponseEntity.ok(alarm.toResponse(geofenceService))
    }

    @PutMapping("/{id}")
    fun updateAlarm(
        authentication: Authentication,
        @PathVariable id: UUID,
        @Valid @RequestBody request: AlarmRequest
    ): ResponseEntity<AlarmResponse> {
        val userId = UUID.fromString(authentication.principal as String)
        val alarm = alarmService.getAlarm(id, userId)

        val updates = Alarm(
            user = alarm.user,
            label = request.label,
            triggerType = request.triggerType,
            scheduledTime = request.scheduledTime,
            repeatRule = request.repeatRule,
            customDays = request.customDays,
            geofenceZone = request.geofenceZoneId?.let { zoneId ->
                geofenceService.getGeofenceZone(zoneId, userId)
            },
            snoozeDurationMinutes = request.snoozeDurationMinutes,
            ringtone = request.ringtone,
            gradualVolume = request.gradualVolume
        )

        val updated = alarmService.updateAlarm(id, userId, updates)
        logger.info { "Alarm updated: $id" }
        return ResponseEntity.ok(updated.toResponse(geofenceService))
    }

    @DeleteMapping("/{id}")
    fun deleteAlarm(
        authentication: Authentication,
        @PathVariable id: UUID
    ): ResponseEntity<Void> {
        val userId = UUID.fromString(authentication.principal as String)
        alarmService.deleteAlarm(id, userId)
        logger.info { "Alarm deleted: $id" }
        return ResponseEntity.noContent().build()
    }

    @PatchMapping("/{id}/toggle")
    fun toggleAlarm(
        authentication: Authentication,
        @PathVariable id: UUID
    ): ResponseEntity<AlarmResponse> {
        val userId = UUID.fromString(authentication.principal as String)
        val toggled = alarmService.toggleAlarm(id, userId)
        return ResponseEntity.ok(toggled.toResponse(geofenceService))
    }

    private fun Alarm.toResponse(geofenceService: GeofenceService) = AlarmResponse(
        id = this.id,
        label = this.label,
        triggerType = this.triggerType,
        scheduledTime = this.scheduledTime,
        repeatRule = this.repeatRule,
        customDays = this.customDays,
        geofenceZoneId = this.geofenceZone?.id,
        geofenceZoneName = this.geofenceZone?.name,
        snoozeDurationMinutes = this.snoozeDurationMinutes,
        isActive = this.isActive,
        ringtone = this.ringtone,
        gradualVolume = this.gradualVolume,
        createdAt = this.createdAt,
        updatedAt = this.updatedAt
    )
}
