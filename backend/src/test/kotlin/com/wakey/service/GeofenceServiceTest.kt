package com.wakey.service

import com.wakey.model.GeofenceZone
import com.wakey.model.User
import com.wakey.repository.GeofenceRepository
import io.mockk.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.DisplayName
import org.springframework.data.redis.core.RedisTemplate
import java.util.*
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@DisplayName("GeofenceService Test Suite")
class GeofenceServiceTest {

    private val geofenceRepository = mockk<GeofenceRepository>()
    private val redisTemplate = mockk<RedisTemplate<String, String>>()
    private val notificationService = mockk<NotificationService>(relaxed = true)

    private val geofenceService = GeofenceService(geofenceRepository, redisTemplate, notificationService)

    private val userId = UUID.randomUUID()
    private val user = User(id = userId, email = "test@example.com", passwordHash = "hash")

    @Test
    @DisplayName("evaluateLocation: device inside zone returns INSIDE status")
    fun testDeviceInsideZone() {
        val zone = GeofenceZone.createWithLocation(
            user = user,
            name = "Office",
            centreLat = 37.7749,
            centreLng = -122.4194,
            radiusMetres = 500
        )

        every { geofenceRepository.findAllByUserId(userId) } returns listOf(zone)
        every { redisTemplate.opsForValue().get(any()) } returns null
        every { redisTemplate.opsForValue().set(any(), any()) } returns Unit

        val statuses = geofenceService.evaluateLocation(userId, 37.7749, -122.4194)

        assertEquals(1, statuses.size)
        assertTrue(statuses[0].isInside)
        assertEquals("Office", statuses[0].zoneName)
    }

    @Test
    @DisplayName("evaluateLocation: device outside zone returns OUTSIDE status")
    fun testDeviceOutsideZone() {
        val zone = GeofenceZone.createWithLocation(
            user = user,
            name = "Office",
            centreLat = 37.7749,
            centreLng = -122.4194,
            radiusMetres = 500
        )

        every { geofenceRepository.findAllByUserId(userId) } returns listOf(zone)
        every { redisTemplate.opsForValue().get(any()) } returns null
        every { redisTemplate.opsForValue().set(any(), any()) } returns Unit

        val statuses = geofenceService.evaluateLocation(userId, 37.8, -122.42)

        assertEquals(1, statuses.size)
        assertFalse(statuses[0].isInside)
    }

    @Test
    @DisplayName("evaluateLocation: transition outside→inside publishes ENTER event")
    fun testTransitionOutsideToInside() {
        val zoneId = UUID.randomUUID()
        val zone = GeofenceZone.createWithLocation(
            id = zoneId,
            user = user,
            name = "Office",
            centreLat = 37.7749,
            centreLng = -122.4194,
            radiusMetres = 500
        )

        every { geofenceRepository.findAllByUserId(userId) } returns listOf(zone)
        val cacheKey = "geo:state:${userId}:${zoneId}"
        every { redisTemplate.opsForValue().get(cacheKey) } returns "false" // was outside
        every { redisTemplate.opsForValue().set(any(), any()) } returns Unit

        val statuses = geofenceService.evaluateLocation(userId, 37.7749, -122.4194)

        assertTrue(statuses[0].isInside)
        verify { notificationService.sendGeofenceUpdate(userId, any()) }
    }

    @Test
    @DisplayName("evaluateLocation: transition inside→outside publishes EXIT event")
    fun testTransitionInsideToOutside() {
        val zoneId = UUID.randomUUID()
        val zone = GeofenceZone.createWithLocation(
            id = zoneId,
            user = user,
            name = "Office",
            centreLat = 37.7749,
            centreLng = -122.4194,
            radiusMetres = 500
        )

        every { geofenceRepository.findAllByUserId(userId) } returns listOf(zone)
        val cacheKey = "geo:state:${userId}:${zoneId}"
        every { redisTemplate.opsForValue().get(cacheKey) } returns "true" // was inside
        every { redisTemplate.opsForValue().set(any(), any()) } returns Unit

        val statuses = geofenceService.evaluateLocation(userId, 37.8, -122.42)

        assertFalse(statuses[0].isInside)
        verify { notificationService.sendGeofenceUpdate(userId, any()) }
    }

    @Test
    @DisplayName("evaluateLocation: no state change does NOT publish event")
    fun testNoStateChange() {
        val zoneId = UUID.randomUUID()
        val zone = GeofenceZone.createWithLocation(
            id = zoneId,
            user = user,
            name = "Office",
            centreLat = 37.7749,
            centreLng = -122.4194,
            radiusMetres = 500
        )

        every { geofenceRepository.findAllByUserId(userId) } returns listOf(zone)
        val cacheKey = "geo:state:${userId}:${zoneId}"
        every { redisTemplate.opsForValue().get(cacheKey) } returns "true" // was inside
        every { redisTemplate.opsForValue().set(any(), any()) } returns Unit

        geofenceService.evaluateLocation(userId, 37.7749, -122.4194)

        verify(exactly = 0) { notificationService.sendGeofenceUpdate(userId, any()) }
    }

    @Test
    @DisplayName("evaluateLocation: no active zones returns empty list")
    fun testNoActiveZones() {
        every { geofenceRepository.findAllByUserId(userId) } returns emptyList()

        val statuses = geofenceService.evaluateLocation(userId, 37.7749, -122.4194)

        assertEquals(0, statuses.size)
    }

    @Test
    @DisplayName("evaluateLocation: multiple zones, inside only one")
    fun testMultipleZonesInsideOne() {
        val zone1 = GeofenceZone.createWithLocation(
            user = user,
            name = "Office",
            centreLat = 37.7749,
            centreLng = -122.4194,
            radiusMetres = 500
        )

        val zone2 = GeofenceZone.createWithLocation(
            user = user,
            name = "Home",
            centreLat = 37.8,
            centreLng = -122.42,
            radiusMetres = 500
        )

        every { geofenceRepository.findAllByUserId(userId) } returns listOf(zone1, zone2)
        every { redisTemplate.opsForValue().get(any()) } returns null
        every { redisTemplate.opsForValue().set(any(), any()) } returns Unit

        val statuses = geofenceService.evaluateLocation(userId, 37.7749, -122.4194)

        assertEquals(2, statuses.size)
        assertTrue(statuses[0].isInside)  // Inside Office
        assertFalse(statuses[1].isInside) // Outside Home
    }
}
