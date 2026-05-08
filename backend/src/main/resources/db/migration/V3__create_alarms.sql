CREATE TYPE trigger_type AS ENUM ('TIME', 'GEO_ENTER', 'GEO_EXIT', 'COMBINED');
CREATE TYPE repeat_rule AS ENUM ('ONCE', 'DAILY', 'WEEKDAYS', 'CUSTOM');

CREATE TABLE alarms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label VARCHAR(100),
  trigger_type trigger_type NOT NULL,
  scheduled_time TIME,
  repeat_rule repeat_rule DEFAULT 'ONCE',
  custom_days VARCHAR(20),
  geofence_zone_id UUID REFERENCES geofence_zones(id) ON DELETE SET NULL,
  snooze_duration_minutes INT DEFAULT 9,
  is_active BOOLEAN DEFAULT TRUE,
  ringtone VARCHAR(100) DEFAULT 'default',
  gradual_volume BOOLEAN DEFAULT FALSE,
  quartz_job_key VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_alarm_user ON alarms(user_id);
CREATE INDEX idx_alarm_zone ON alarms(geofence_zone_id);
CREATE INDEX idx_alarm_active ON alarms(is_active, user_id);
