package com.wakey.api

import com.wakey.dto.request.LocationUpdateRequest
import com.wakey.dto.response.LocationResponse
import com.wakey.model.LocationEvent
import com.wakey.repository.LocationEventRepository
import com.wakey.service.GeofenceService
import com.wakey.service.UserService
import jakarta.validation.Valid
import mu.KotlinLogging
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import java.util.*

private val logger = KotlinLogging.logger {}

@RestController
@RequestMapping("/api/v1/location")
@CrossOrigin(origins = ["*"])
class LocationController(
    private val locationEventRepository: LocationEventRepository,
    private val userService: UserService,
    private val geofenceService: GeofenceService
) {

    @PostMapping("/update")
    fun updateLocation(
        authentication: Authentication,
        @Valid @RequestBody request: LocationUpdateRequest
    ): ResponseEntity<Void> {
        val userId = UUID.fromString(authentication.principal as String)
        val user = userService.getUserById(userId)

        // Save location event
        val locationEvent = LocationEvent(
            user = user,
            latitude = request.latitude,
            longitude = request.longitude,
            accuracyMetres = request.accuracy
        )
        locationEventRepository.save(locationEvent)

        // Evaluate geofence zones
        val zoneStatuses = geofenceService.evaluateLocation(
            userId,
            request.latitude,
            request.longitude
        )

        logger.debug { "Location updated for user $userId. Zones evaluated: ${zoneStatuses.size}" }

        return ResponseEntity.ok().build()
    }

    @GetMapping("/current")
    fun getCurrentLocation(authentication: Authentication): ResponseEntity<LocationResponse?> {
        val userId = UUID.fromString(authentication.principal as String)
        val lastLocation = locationEventRepository.findFirstByUserIdOrderByRecordedAtDesc(userId)

        return if (lastLocation != null) {
            ResponseEntity.ok(
                LocationResponse(
                    latitude = lastLocation.latitude,
                    longitude = lastLocation.longitude,
                    accuracy = lastLocation.accuracyMetres,
                    recordedAt = lastLocation.recordedAt
                )
            )
        } else {
            ResponseEntity.ok(null)
        }
    }
}
