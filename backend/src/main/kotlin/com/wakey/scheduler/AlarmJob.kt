package com.wakey.scheduler

import mu.KotlinLogging
import org.quartz.Job
import org.quartz.JobExecutionContext
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.stereotype.Component
import com.wakey.service.AlarmService
import com.wakey.repository.AlarmRepository
import java.util.*

private val logger = KotlinLogging.logger {}

@Component
class AlarmJob : Job {

    @Autowired
    private lateinit var alarmService: AlarmService

    @Autowired
    private lateinit var alarmRepository: AlarmRepository

    override fun execute(context: JobExecutionContext) {
        try {
            val alarmId = context.jobDetail.jobDataMap.getString("alarmId")
            val userId = context.jobDetail.jobDataMap.getString("userId")

            if (alarmId != null && userId != null) {
                val alarm = alarmRepository.findByIdAndUserId(UUID.fromString(alarmId), UUID.fromString(userId))
                if (alarm != null && alarm.isActive) {
                    logger.info { "Triggering alarm: $alarmId" }
                    alarmService.triggerAlarm(alarm)
                } else {
                    logger.warn { "Alarm not found or inactive: $alarmId" }
                }
            }
        } catch (e: Exception) {
            logger.error(e) { "Error executing alarm job" }
        }
    }
}
