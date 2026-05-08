CREATE TABLE location_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy_metres DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_location_user_time ON location_events(user_id, recorded_at DESC);
CREATE INDEX idx_location_recent ON location_events(recorded_at DESC) WHERE recorded_at > NOW() - INTERVAL '7 days';
