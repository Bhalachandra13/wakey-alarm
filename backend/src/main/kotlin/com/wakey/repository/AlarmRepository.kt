package com.wakey.repository

import com.wakey.model.Alarm
import com.wakey.model.AlarmTriggerType
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.stereotype.Repository
import java.util.*

@Repository
interface AlarmRepository : JpaRepository<Alarm, UUID> {
    fun findAllByUserId(userId: UUID): List<Alarm>
    fun findByIdAndUserId(id: UUID, userId: UUID): Alarm?
    fun findAllByUserIdAndIsActive(userId: UUID, isActive: Boolean): List<Alarm>
    fun findAllByUserIdAndTriggerType(userId: UUID, triggerType: AlarmTriggerType): List<Alarm>
    fun findAllByGeofenceZoneId(zoneId: UUID): List<Alarm>
}
