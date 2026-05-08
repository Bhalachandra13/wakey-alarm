package com.wakey.util

import kotlin.math.*

object HaversineUtil {
    private const val EARTH_RADIUS_METRES = 6371000.0

    fun distanceMetres(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val φ1 = lat1.toRadians()
        val φ2 = lat2.toRadians()
        val Δφ = (lat2 - lat1).toRadians()
        val Δλ = (lng2 - lng1).toRadians()

        val a = sin(Δφ / 2) * sin(Δφ / 2) +
                cos(φ1) * cos(φ2) *
                sin(Δλ / 2) * sin(Δλ / 2)

        val c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return EARTH_RADIUS_METRES * c
    }

    fun isPointInZone(pointLat: Double, pointLng: Double, zoneCentLat: Double, zoneCentLng: Double, radiusMetres: Int): Boolean {
        val distance = distanceMetres(zoneCentLat, zoneCentLng, pointLat, pointLng)
        return distance < radiusMetres
    }
}
