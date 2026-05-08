package com.wakey.dto.response

import java.time.LocalDateTime
import java.util.*

data class GeofenceResponse(
    val id: UUID,
    val name: String,
    val centreLat: Double,
    val centreLng: Double,
    val radiusMetres: Int,
    val isActive: Boolean,
    val createdAt: LocalDateTime,
    val updatedAt: LocalDateTime
)
