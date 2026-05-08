package com.wakey.repository

import com.wakey.model.LocationEvent
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.stereotype.Repository
import java.util.*

@Repository
interface LocationEventRepository : JpaRepository<LocationEvent, UUID> {
    fun findAllByUserId(userId: UUID): List<LocationEvent>
    fun findFirstByUserIdOrderByRecordedAtDesc(userId: UUID): LocationEvent?
}
