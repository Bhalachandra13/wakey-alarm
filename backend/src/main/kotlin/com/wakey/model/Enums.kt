package com.wakey.model

enum class AlarmTriggerType {
    TIME,
    GEO_ENTER,
    GEO_EXIT,
    COMBINED
}

enum class RepeatRule {
    ONCE,
    DAILY,
    WEEKDAYS,
    CUSTOM
}
