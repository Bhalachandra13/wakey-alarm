package com.wakey.dto.response

import com.wakey.model.AlarmTriggerType
import com.wakey.model.RepeatRule
import java.time.LocalDateTime
import java.time.LocalTime
import java.util.*

data class AlarmResponse(
    val id: UUID,
    val label: String?,
    val triggerType: AlarmTriggerType,
    val scheduledTime: LocalTime? = null,
    val repeatRule: RepeatRule,
    val customDays: String? = null,
    val geofenceZoneId: UUID? = null,
    val geofenceZoneName: String? = null,
    val snoozeDurationMinutes: Int,
    val isActive: Boolean,
    val ringtone: String,
    val gradualVolume: Boolean,
    val createdAt: LocalDateTime,
    val updatedAt: LocalDateTime
)

data class LocationResponse(
    val latitude: Double,
    val longitude: Double,
    val accuracy: Double?,
    val recordedAt: LocalDateTime
)
