package com.wakey.repository

import com.wakey.model.GeofenceZone
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.stereotype.Repository
import java.util.*

@Repository
interface GeofenceRepository : JpaRepository<GeofenceZone, UUID> {
    fun findAllByUserId(userId: UUID): List<GeofenceZone>
    fun findByIdAndUserId(id: UUID, userId: UUID): GeofenceZone?
    fun findAllByUserIdAndIsActive(userId: UUID, isActive: Boolean): List<GeofenceZone>
}
