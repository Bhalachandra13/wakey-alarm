package com.wakey.model

import jakarta.persistence.*
import org.hibernate.annotations.CreationTimestamp
import org.hibernate.annotations.UpdateTimestamp
import org.locationtech.jts.geom.Point
import org.locationtech.jts.io.WKTReader
import java.time.LocalDateTime
import java.util.*

@Entity
@Table(name = "geofence_zones")
data class GeofenceZone(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID = UUID.randomUUID(),

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    val user: User,

    @Column(nullable = false)
    val name: String,

    @Column(nullable = false)
    val centreLat: Double,

    @Column(nullable = false)
    val centreLng: Double,

    @Column(nullable = false)
    val radiusMetres: Int,

    @Column(columnDefinition = "GEOGRAPHY(POINT, 4326)")
    val location: Point? = null,

    @Column
    val isActive: Boolean = true,

    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    val createdAt: LocalDateTime = LocalDateTime.now(),

    @UpdateTimestamp
    @Column(nullable = false)
    var updatedAt: LocalDateTime = LocalDateTime.now(),

    @OneToMany(mappedBy = "geofenceZone", cascade = [CascadeType.ALL], orphanRemoval = true)
    val alarms: MutableSet<Alarm> = mutableSetOf()
) {
    companion object {
        fun createWithLocation(
            id: UUID = UUID.randomUUID(),
            user: User,
            name: String,
            centreLat: Double,
            centreLng: Double,
            radiusMetres: Int,
            isActive: Boolean = true
        ): GeofenceZone {
            val wktReader = WKTReader()
            val location = wktReader.read("POINT($centreLng $centreLat)") as Point
            return GeofenceZone(
                id = id,
                user = user,
                name = name,
                centreLat = centreLat,
                centreLng = centreLng,
                radiusMetres = radiusMetres,
                location = location,
                isActive = isActive
            )
        }
    }
}
