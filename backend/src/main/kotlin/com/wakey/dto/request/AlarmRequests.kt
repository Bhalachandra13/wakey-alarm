package com.wakey.dto.request

import com.wakey.model.AlarmTriggerType
import com.wakey.model.RepeatRule
import java.time.LocalTime
import java.util.*

data class AlarmRequest(
    val label: String?,
    val triggerType: AlarmTriggerType,
    val scheduledTime: LocalTime? = null,
    val repeatRule: RepeatRule = RepeatRule.ONCE,
    val customDays: String? = null,
    val geofenceZoneId: UUID? = null,
    val snoozeDurationMinutes: Int = 9,
    val ringtone: String = "default",
    val gradualVolume: Boolean = false
)

data class LocationUpdateRequest(
    val latitude: Double,
    val longitude: Double,
    val accuracy: Double? = null
)
