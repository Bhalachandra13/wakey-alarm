package com.wakey.api

import com.wakey.dto.request.GeofenceRequest
import com.wakey.dto.response.GeofenceResponse
import com.wakey.model.GeofenceZone
import com.wakey.service.GeofenceService
import jakarta.validation.Valid
import mu.KotlinLogging
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import java.util.*

private val logger = KotlinLogging.logger {}

@RestController
@RequestMapping("/api/v1/geofences")
@CrossOrigin(origins = ["*"])
class GeofenceController(private val geofenceService: GeofenceService) {

    @GetMapping
    fun getAllGeofences(authentication: Authentication): ResponseEntity<List<GeofenceResponse>> {
        val userId = UUID.fromString(authentication.principal as String)
        val zones = geofenceService.getAllGeofenceZones(userId)
        val responses = zones.map { it.toResponse() }
        return ResponseEntity.ok(responses)
    }

    @PostMapping
    fun createGeofence(
        authentication: Authentication,
        @Valid @RequestBody request: GeofenceRequest
    ): ResponseEntity<GeofenceResponse> {
        val userId = UUID.fromString(authentication.principal as String)

        if (request.radiusMetres !in 50..50000) {
            return ResponseEntity.badRequest().build()
        }

        val zone = GeofenceZone.createWithLocation(
            user = com.wakey.model.User(id = userId, email = "", passwordHash = ""),
            name = request.name,
            centreLat = request.centreLat,
            centreLng = request.centreLng,
            radiusMetres = request.radiusMetres,
            isActive = request.isActive
        )

        val created = geofenceService.createGeofenceZone(zone)
        logger.info { "Geofence zone created: ${created.id}" }
        return ResponseEntity.status(HttpStatus.CREATED).body(created.toResponse())
    }

    @GetMapping("/{id}")
    fun getGeofence(
        authentication: Authentication,
        @PathVariable id: UUID
    ): ResponseEntity<GeofenceResponse> {
        val userId = UUID.fromString(authentication.principal as String)
        val zone = geofenceService.getGeofenceZone(id, userId)
        return ResponseEntity.ok(zone.toResponse())
    }

    @PutMapping("/{id}")
    fun updateGeofence(
        authentication: Authentication,
        @PathVariable id: UUID,
        @Valid @RequestBody request: GeofenceRequest
    ): ResponseEntity<GeofenceResponse> {
        val userId = UUID.fromString(authentication.principal as String)

        if (request.radiusMetres !in 50..50000) {
            return ResponseEntity.badRequest().build()
        }

        val updates = GeofenceZone.createWithLocation(
            user = com.wakey.model.User(id = userId, email = "", passwordHash = ""),
            name = request.name,
            centreLat = request.centreLat,
            centreLng = request.centreLng,
            radiusMetres = request.radiusMetres,
            isActive = request.isActive
        )

        val updated = geofenceService.updateGeofenceZone(id, userId, updates)
        logger.info { "Geofence zone updated: $id" }
        return ResponseEntity.ok(updated.toResponse())
    }

    @DeleteMapping("/{id}")
    fun deleteGeofence(
        authentication: Authentication,
        @PathVariable id: UUID
    ): ResponseEntity<Void> {
        val userId = UUID.fromString(authentication.principal as String)
        geofenceService.deleteGeofenceZone(id, userId)
        logger.info { "Geofence zone deleted: $id" }
        return ResponseEntity.noContent().build()
    }

    @PatchMapping("/{id}/toggle")
    fun toggleGeofence(
        authentication: Authentication,
        @PathVariable id: UUID
    ): ResponseEntity<GeofenceResponse> {
        val userId = UUID.fromString(authentication.principal as String)
        val toggled = geofenceService.toggleGeofenceZone(id, userId)
        return ResponseEntity.ok(toggled.toResponse())
    }

    private fun GeofenceZone.toResponse() = GeofenceResponse(
        id = this.id,
        name = this.name,
        centreLat = this.centreLat,
        centreLng = this.centreLng,
        radiusMetres = this.radiusMetres,
        isActive = this.isActive,
        createdAt = this.createdAt,
        updatedAt = this.updatedAt
    )
}
