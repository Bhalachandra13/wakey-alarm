package com.wakey.config

import com.wakey.service.AlarmService
import com.wakey.service.GeofenceTransitionEvent
import mu.KotlinLogging
import org.springframework.amqp.rabbit.annotation.RabbitListener
import org.springframework.stereotype.Component

private val logger = KotlinLogging.logger {}

@Component
class GeofenceEventListener(private val alarmService: AlarmService) {

    @RabbitListener(queues = [RabbitMQConfig.GEOFENCE_QUEUE])
    fun handleGeofenceTransition(event: GeofenceTransitionEvent) {
        logger.info { "Received geofence transition event: ${event.zoneName}" }
        try {
            alarmService.onGeofenceTransition(event)
        } catch (e: Exception) {
            logger.error(e) { "Failed to process geofence transition event" }
        }
    }
}
