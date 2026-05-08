package com.wakey.config

import org.springframework.amqp.core.Queue
import org.springframework.amqp.core.TopicExchange
import org.springframework.amqp.core.Binding
import org.springframework.amqp.core.BindingBuilder
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration

@Configuration
class RabbitMQConfig {

    companion object {
        const val GEOFENCE_EXCHANGE = "geofence.exchange"
        const val GEOFENCE_QUEUE = "geofence.queue"
        const val GEOFENCE_ROUTING_KEY = "geofence.transition"

        const val ALARM_EXCHANGE = "alarm.exchange"
        const val ALARM_QUEUE = "alarm.queue"
        const val ALARM_ROUTING_KEY = "alarm.trigger"
    }

    @Bean
    fun geofenceExchange(): TopicExchange = TopicExchange(GEOFENCE_EXCHANGE, true, false)

    @Bean
    fun geofenceQueue(): Queue = Queue(GEOFENCE_QUEUE, true)

    @Bean
    fun geofenceBinding(geofenceQueue: Queue, geofenceExchange: TopicExchange): Binding =
        BindingBuilder.bind(geofenceQueue).to(geofenceExchange).with(GEOFENCE_ROUTING_KEY)

    @Bean
    fun alarmExchange(): TopicExchange = TopicExchange(ALARM_EXCHANGE, true, false)

    @Bean
    fun alarmQueue(): Queue = Queue(ALARM_QUEUE, true)

    @Bean
    fun alarmBinding(alarmQueue: Queue, alarmExchange: TopicExchange): Binding =
        BindingBuilder.bind(alarmQueue).to(alarmExchange).with(ALARM_ROUTING_KEY)
}
