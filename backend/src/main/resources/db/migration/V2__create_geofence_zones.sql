CREATE TABLE geofence_zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  centre_lat DOUBLE PRECISION NOT NULL,
  centre_lng DOUBLE PRECISION NOT NULL,
  radius_metres INT NOT NULL CHECK (radius_metres BETWEEN 50 AND 50000),
  location GEOGRAPHY(POINT, 4326),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_geofence_user ON geofence_zones(user_id);
CREATE INDEX idx_geofence_location ON geofence_zones USING GIST(location);
