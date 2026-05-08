package com.wakey.dto.request

data class GeofenceRequest(
    val name: String,
    val centreLat: Double,
    val centreLng: Double,
    val radiusMetres: Int,
    val isActive: Boolean = true
)
