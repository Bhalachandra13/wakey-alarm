package com.wakey.service

import mu.KotlinLogging
import org.springframework.amqp.rabbit.core.RabbitTemplate
import org.springframework.stereotype.Service
import com.wakey.config.RabbitMQConfig

private val logger = KotlinLogging.logger {}

@Service
class GeofenceEventPublisher(private val rabbitTemplate: RabbitTemplate) {

    fun publishGeofenceTransition(event: GeofenceTransitionEvent) {
        try {
            rabbitTemplate.convertAndSend(
                RabbitMQConfig.GEOFENCE_EXCHANGE,
                RabbitMQConfig.GEOFENCE_ROUTING_KEY,
                event
            )
            logger.debug { "Geofence event published: ${event.zoneName}" }
        } catch (e: Exception) {
            logger.error(e) { "Failed to publish geofence event" }
        }
    }
}
