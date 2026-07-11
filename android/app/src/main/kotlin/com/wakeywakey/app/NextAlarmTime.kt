package com.wakeywakey.app

import java.util.Calendar

/**
 * Utility object for computing the next wall-clock fire time for a
 * time-based alarm.
 *
 * Used by both [MainActivity] (when scheduling from Dart) and
 * [BootReceiver] (when rescheduling after reboot without a running
 * Flutter engine).
 */
object NextAlarmTime {

    /**
     * Returns the epoch-millisecond timestamp of the next occurrence of
     * [hour]:[minute] given optional [repeatDays].
     *
     * @param hour       0-23
     * @param minute     0-59
     * @param repeatDays Comma-separated day abbreviations, e.g. "MON,WED,FRI",
     *                   or null / blank for a one-shot alarm.
     */
    fun compute(hour: Int, minute: Int, repeatDays: String?): Long {
        val now = Calendar.getInstance()
        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val days = parseRepeatDays(repeatDays)

        return if (days.isEmpty()) {
            // One-shot: if the time has already passed today, fire tomorrow.
            if (!target.after(now)) {
                target.add(Calendar.DAY_OF_YEAR, 1)
            }
            target.timeInMillis
        } else {
            // Repeating: find the soonest upcoming day-of-week.
            nextRepeatOccurrence(now, target, days)
        }
    }

    /**
     * Parses the comma-separated repeat-day string into a set of
     * [Calendar.DAY_OF_WEEK] integers.
     */
    private fun parseRepeatDays(repeatDays: String?): Set<Int> {
        if (repeatDays.isNullOrBlank()) return emptySet()
        val dayMap = mapOf(
            "SUN" to Calendar.SUNDAY,
            "MON" to Calendar.MONDAY,
            "TUE" to Calendar.TUESDAY,
            "WED" to Calendar.WEDNESDAY,
            "THU" to Calendar.THURSDAY,
            "FRI" to Calendar.FRIDAY,
            "SAT" to Calendar.SATURDAY,
        )
        return repeatDays.split(",")
            .mapNotNull { dayMap[it.trim().uppercase()] }
            .toSet()
    }

    /**
     * Among the [repeatDays], find the next Calendar day that is strictly
     * in the future relative to [now] at [hour]:[minute].
     */
    private fun nextRepeatOccurrence(
        now: Calendar,
        target: Calendar,
        repeatDays: Set<Int>,
    ): Long {
        // Check today first (target may already be set to today).
        if (repeatDays.contains(target.get(Calendar.DAY_OF_WEEK)) && target.after(now)) {
            return target.timeInMillis
        }
        // Walk forward up to 7 days to find the next matching day.
        for (offset in 1..7) {
            target.add(Calendar.DAY_OF_YEAR, 1)
            if (repeatDays.contains(target.get(Calendar.DAY_OF_WEEK))) {
                return target.timeInMillis
            }
        }
        // Should never reach here with a non-empty repeatDays set.
        return target.timeInMillis
    }
}
