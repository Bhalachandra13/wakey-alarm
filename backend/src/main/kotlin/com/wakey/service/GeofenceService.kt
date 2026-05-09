package com.wakey.service

import com.wakey.exception.ResourceNotFoundException
import com.wakey.model.GeofenceZone
import com.wakey.repository.GeofenceRepository
import com.wakey.util.HaversineUtil
import mu.KotlinLogging
import org.springframework.data.redis.core.RedisTemplate
import org.springframework.stereotype.Service
import java.util.*

private val logger = KotlinLogging.logger {}

enum class GeoTransitionType {
    ENTER, EXIT
}

data class GeofenceTransitionEvent(
    val userId: UUID,
    val zoneId: UUID,
    val zoneName: String,
    val transitionType: GeoTransitionType,
    val timestamp: Long = System.currentTimeMillis()
)

data class ZoneStatus(
    val zoneId: UUID,
    val zoneName: String,
    val isInside: Boolean
)

@Service
class GeofenceService(
    private val geofenceRepository: GeofenceRepository,
    private val redisTemplate: RedisTemplate<String, String>,
    private val notificationService: NotificationService? = null,
    private val eventPublisher: GeofenceEventPublisher? = null
) {

    fun evaluateLocation(userId: UUID, lat: Double, lng: Double): List<ZoneStatus> {
        val zones = geofenceRepository.findAllByUserId(userId)
        val statuses = mutableListOf<ZoneStatus>()

        for (zone in zones) {
            val isInside = HaversineUtil.isPointInZone(
                lat, lng,
                zone.centreLat, zone.centreLng,
                zone.radiusMetres
            )

            val cacheKey = "geo:state:${userId}:${zone.id}"
            val previousState = redisTemplate.opsForValue().get(cacheKey)?.toBoolean()

            // Persist current state to Redis
            redisTemplate.opsForValue().set(cacheKey, isInside.toString())

            // Detect state transition
            if (previousState != null && previousState != isInside) {
                val transitionType = if (isInside) GeoTransitionType.ENTER else GeoTransitionType.EXIT
                val event = GeofenceTransitionEvent(
                    userId = userId,
                    zoneId = zone.id,
                    zoneName = zone.name,
                    transitionType = transitionType
                )

                logger.info { "Geofence transition: ${event.zoneName} - ${event.transitionType} for user $userId" }

                // Publish event to RabbitMQ
                publishGeofenceEvent(event)

                // Notify WebSocket clients
                notificationService?.sendGeofenceUpdate(userId, event)
            }

            statuses.add(
                ZoneStatus(
                    zoneId = zone.id,
                    zoneName = zone.name,
                    isInside = isInside
                )
            )
        }

        return statuses
    }

    fun createGeofenceZone(zone: GeofenceZone): GeofenceZone {
        logger.debug { "Creating geofence zone: ${zone.name}" }
        return geofenceRepository.save(zone)
    }

    fun updateGeofenceZone(zoneId: UUID, userId: UUID, updates: GeofenceZone): GeofenceZone {
        val zone = getGeofenceZone(zoneId, userId)
        val updated = zone.copy(
            name = updates.name,
            centreLat = updates.centreLat,
            centreLng = updates.centreLng,
            radiusMetres = updates.radiusMetres,
            isActive = updates.isActive
        )
        logger.debug { "Updating geofence zone: $zoneId" }
        return geofenceRepository.save(updated)
    }

    fun getGeofenceZone(zoneId: UUID, userId: UUID): GeofenceZone {
        return geofenceRepository.findByIdAndUserId(zoneId, userId)
            ?: throw ResourceNotFoundException("Geofence zone not found: $zoneId")
    }

    fun getActiveGeofenceZones(userId: UUID): List<GeofenceZone> {
        return geofenceRepository.findAllByUserIdAndIsActive(userId, true)
    }

    fun getAllGeofenceZones(userId: UUID): List<GeofenceZone> {
        return geofenceRepository.findAllByUserId(userId)
    }

    fun deleteGeofenceZone(zoneId: UUID, userId: UUID) {
        val zone = getGeofenceZone(zoneId, userId)
        geofenceRepository.delete(zone)
        logger.info { "Geofence zone deleted: $zoneId" }
    }

    fun toggleGeofenceZone(zoneId: UUID, userId: UUID): GeofenceZone {
        val zone = getGeofenceZone(zoneId, userId)
        val updated = zone.copy(isActive = !zone.isActive)
        return geofenceRepository.save(updated)
    }

    private fun publishGeofenceEvent(event: GeofenceTransitionEvent) {
        eventPublisher?.publishGeofenceTransition(event)
        logger.debug { "Publishing geofence event: ${event.zoneName}" }
    }
}
