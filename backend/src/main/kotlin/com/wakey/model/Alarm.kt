package com.wakey.model

import jakarta.persistence.*
import org.hibernate.annotations.CreationTimestamp
import org.hibernate.annotations.UpdateTimestamp
import java.time.LocalDateTime
import java.time.LocalTime
import java.util.*

@Entity
@Table(name = "alarms")
data class Alarm(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID = UUID.randomUUID(),

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    val user: User,

    @Column
    var label: String? = null,

    @Column(nullable = false)
    @Enumerated(EnumType.STRING)
    val triggerType: AlarmTriggerType,

    @Column
    var scheduledTime: LocalTime? = null,

    @Column
    @Enumerated(EnumType.STRING)
    var repeatRule: RepeatRule = RepeatRule.ONCE,

    @Column
    var customDays: String? = null,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "geofence_zone_id")
    val geofenceZone: GeofenceZone? = null,

    @Column
    var snoozeDurationMinutes: Int = 9,

    @Column
    var isActive: Boolean = true,

    @Column
    var ringtone: String = "default",

    @Column
    var gradualVolume: Boolean = false,

    @Column
    var quartzJobKey: String? = null,

    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    val createdAt: LocalDateTime = LocalDateTime.now(),

    @UpdateTimestamp
    @Column(nullable = false)
    var updatedAt: LocalDateTime = LocalDateTime.now()
)
