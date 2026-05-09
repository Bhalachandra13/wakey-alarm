package com.wakey.scheduler

import mu.KotlinLogging
import org.quartz.*
import org.springframework.context.annotation.Configuration
import org.springframework.scheduling.quartz.SchedulerFactoryBean
import org.springframework.context.annotation.Bean
import java.time.LocalTime
import java.util.*

private val logger = KotlinLogging.logger {}

@Configuration
class SchedulerConfig {

    @Bean
    fun schedulerFactoryBean(): SchedulerFactoryBean {
        val schedulerFactory = SchedulerFactoryBean()
        schedulerFactory.setJobFactory(SpringBeanJobFactory())
        schedulerFactory.setWaitForJobsToCompleteOnShutdown(true)
        schedulerFactory.setOverwriteExistingJobs(true)
        return schedulerFactory
    }

    companion object {
        fun createAlarmJobKey(alarmId: UUID): String = "alarm_${alarmId}"

        fun createAlarmTriggerKey(alarmId: UUID): String = "trigger_${alarmId}"
    }
}

class SpringBeanJobFactory : org.springframework.scheduling.quartz.SpringBeanJobFactory() {
    override fun createJobInstance(bd: org.quartz.spi.TriggerFiredBundle): Any {
        val job = super.createJobInstance(bd)
        return job
    }
}

object QuartzJobScheduler {

    fun scheduleTimeAlarm(
        scheduler: Scheduler,
        alarmId: UUID,
        userId: UUID,
        scheduledTime: LocalTime,
        repeatRule: String
    ): String? {
        return try {
            val jobKey = JobKey(SchedulerConfig.createAlarmJobKey(alarmId))
            val triggerKey = TriggerKey(SchedulerConfig.createAlarmTriggerKey(alarmId))

            // Create job
            val job = JobBuilder.newJob(AlarmJob::class.java)
                .withIdentity(jobKey)
                .usingJobData("alarmId", alarmId.toString())
                .usingJobData("userId", userId.toString())
                .build()

            // Create trigger based on repeat rule
            val trigger = when (repeatRule) {
                "DAILY" -> {
                    TriggerBuilder.newTrigger()
                        .withIdentity(triggerKey)
                        .withSchedule(
                            CronScheduleBuilder.dailyAtHourAndMinute(
                                scheduledTime.hour,
                                scheduledTime.minute
                            )
                        )
                        .build()
                }
                "ONCE" -> {
                    // Schedule for today if time hasn't passed, else tomorrow
                    val calendar = Calendar.getInstance()
                    calendar.set(Calendar.HOUR_OF_DAY, scheduledTime.hour)
                    calendar.set(Calendar.MINUTE, scheduledTime.minute)
                    calendar.set(Calendar.SECOND, 0)

                    if (calendar.time.before(Date())) {
                        calendar.add(Calendar.DAY_OF_MONTH, 1)
                    }

                    TriggerBuilder.newTrigger()
                        .withIdentity(triggerKey)
                        .withSchedule(SimpleScheduleBuilder.simpleSchedule())
                        .startAt(calendar.time)
                        .build()
                }
                "WEEKDAYS" -> {
                    TriggerBuilder.newTrigger()
                        .withIdentity(triggerKey)
                        .withSchedule(
                            CronScheduleBuilder.cronSchedule(
                                "0 ${scheduledTime.minute} ${scheduledTime.hour} ? * MON-FRI"
                            )
                        )
                        .build()
                }
                else -> return null
            }

            scheduler.scheduleJob(job, trigger)
            logger.info { "Alarm scheduled: $alarmId with repeat rule: $repeatRule" }

            jobKey.name
        } catch (e: Exception) {
            logger.error(e) { "Failed to schedule alarm: $alarmId" }
            null
        }
    }

    fun cancelAlarm(scheduler: Scheduler, alarmId: UUID): Boolean {
        return try {
            val jobKey = JobKey(SchedulerConfig.createAlarmJobKey(alarmId))
            scheduler.deleteJob(jobKey)
            logger.info { "Alarm cancelled: $alarmId" }
            true
        } catch (e: Exception) {
            logger.error(e) { "Failed to cancel alarm: $alarmId" }
            false
        }
    }
}
