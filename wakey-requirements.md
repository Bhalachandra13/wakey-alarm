# Wakey — GeoFence Alarm App
## Requirements Document for GitHub Copilot (Claude Sonnet 4.6)

---

## 🤖 Copilot Agent Instructions

You are an **expert full-stack mobile app developer** with deep specialisation in:
- **Kotlin** + Spring Boot backend architecture
- **React Native** (Expo) frontend development
- **Geospatial** systems and location-based services
- **Test-driven development** (TDD) — write unit tests alongside every module
- Clean architecture, SOLID principles, and production-grade error handling

**Your operating rules:**
1. Always scaffold the full file structure before writing implementation code
2. Write unit tests for every service, controller, and utility function — co-located in the same PR/commit as the feature
3. Use dependency injection everywhere — never instantiate services directly in consuming classes
4. Every API endpoint must have input validation, error handling, and a corresponding test
5. Comment complex logic (geospatial math, scheduler edge cases) — but do not over-comment trivial code
6. Use environment variables for all secrets and external service URLs — never hardcode
7. Follow the build order defined in Section 8

---

## 1. Project Overview

**App name:** Wakey  
**Tagline:** Wake up at the right place, at the right time.  
**Platform:** Android-first, iOS secondary  
**Frontend:** React Native + Expo (TypeScript)  
**Backend:** Kotlin + Spring Boot 3.x  
**Database:** PostgreSQL 15 + PostGIS extension  
**Cache:** Redis 7  
**Queue:** RabbitMQ  
**Push notifications:** Firebase Cloud Messaging (FCM)  
**Maps:** Google Maps SDK / react-native-maps  

---

## 2. Core Features

### 2.1 Clock Module
- Digital and analog clock display (current local time)
- World clock: add multiple time zones
- Fully functional **stopwatch** with lap recording
- Fully functional **countdown timer** with custom label
- All clock features run client-side only — no backend calls required

### 2.2 Standard Alarm
- Create, edit, delete time-based alarms
- Repeat rules: once, daily, custom weekdays (e.g. Mon/Wed/Fri)
- Custom alarm label and ringtone selection
- Snooze with configurable duration (1–30 min)
- Gradual volume increase option
- Alarms persist via backend and sync on app launch

### 2.3 GeoFence Alarm
- Draw circular geofence zones on an interactive map
- Set zone name, centre coordinates, and radius (50m – 50km)
- Trigger types:
  - **On Enter** — alarm fires when device enters the zone
  - **On Exit** — alarm fires when device leaves the zone
  - **Combined** — time-based alarm that only fires when inside/outside a zone
- Multiple active geofence zones per user
- Visual overlay of zones on map with enter/exit status indicator
- Background location tracking with battery optimisation

### 2.4 Notifications
- Local notifications for time-based alarms (device-side, works offline)
- Push notifications via FCM for geofence-triggered alarms
- WebSocket channel for real-time geo event streaming to the app UI
- In-app notification history log

### 2.5 User Accounts
- Email/password registration and login
- JWT access tokens (15 min expiry) + refresh tokens (30 day expiry)
- User preferences: default snooze duration, default alarm tone, theme
- All alarms and zones are user-scoped

---

## 3. Backend Specification (Kotlin + Spring Boot)

### 3.1 Project Setup

```
Tech stack:
- Kotlin 1.9+
- Spring Boot 3.2+
- Gradle (Kotlin DSL)
- Spring Data JPA + Hibernate Spatial
- Spring Security (JWT)
- Spring WebSocket (STOMP)
- Quartz Scheduler
- Firebase Admin SDK
- PostgreSQL + PostGIS
- Redis (Spring Cache + Spring Session)
- RabbitMQ (Spring AMQP)
- Flyway (DB migrations)
- JUnit 5 + MockK + Testcontainers (testing)
```

### 3.2 Directory Structure

```
backend/
├── build.gradle.kts
├── settings.gradle.kts
├── docker-compose.yml               # PostgreSQL, Redis, RabbitMQ
├── src/
│   ├── main/
│   │   ├── kotlin/com/wakey/
│   │   │   ├── WakeyApplication.kt
│   │   │   ├── api/
│   │   │   │   ├── AuthController.kt
│   │   │   │   ├── AlarmController.kt
│   │   │   │   ├── GeofenceController.kt
│   │   │   │   ├── LocationController.kt
│   │   │   │   └── UserController.kt
│   │   │   ├── service/
│   │   │   │   ├── AuthService.kt
│   │   │   │   ├── AlarmService.kt
│   │   │   │   ├── GeofenceService.kt
│   │   │   │   ├── LocationService.kt
│   │   │   │   ├── NotificationService.kt
│   │   │   │   └── UserService.kt
│   │   │   ├── scheduler/
│   │   │   │   ├── AlarmJob.kt
│   │   │   │   └── SchedulerConfig.kt
│   │   │   ├── model/
│   │   │   │   ├── User.kt
│   │   │   │   ├── Alarm.kt
│   │   │   │   ├── GeofenceZone.kt
│   │   │   │   ├── LocationEvent.kt
│   │   │   │   └── AlarmTriggerType.kt   # Enum: TIME, GEO_ENTER, GEO_EXIT, COMBINED
│   │   │   ├── repository/
│   │   │   │   ├── UserRepository.kt
│   │   │   │   ├── AlarmRepository.kt
│   │   │   │   ├── GeofenceRepository.kt
│   │   │   │   └── LocationEventRepository.kt
│   │   │   ├── dto/
│   │   │   │   ├── request/           # AlarmRequest, GeofenceRequest, LoginRequest, etc.
│   │   │   │   └── response/          # AlarmResponse, GeofenceResponse, AuthResponse, etc.
│   │   │   ├── config/
│   │   │   │   ├── SecurityConfig.kt
│   │   │   │   ├── WebSocketConfig.kt
│   │   │   │   ├── RedisConfig.kt
│   │   │   │   ├── RabbitMQConfig.kt
│   │   │   │   ├── FirebaseConfig.kt
│   │   │   │   └── JwtConfig.kt
│   │   │   ├── exception/
│   │   │   │   ├── GlobalExceptionHandler.kt
│   │   │   │   ├── ResourceNotFoundException.kt
│   │   │   │   └── UnauthorisedException.kt
│   │   │   └── util/
│   │   │       ├── HaversineUtil.kt     # Geospatial distance calculation
│   │   │       └── JwtUtil.kt
│   │   └── resources/
│   │       ├── application.yml
│   │       ├── application-local.yml
│   │       └── db/migration/            # Flyway SQL scripts
│   └── test/
│       └── kotlin/com/wakey/
│           ├── service/
│           │   ├── GeofenceServiceTest.kt
│           │   ├── AlarmServiceTest.kt
│           │   ├── AuthServiceTest.kt
│           │   └── NotificationServiceTest.kt
│           ├── api/
│           │   ├── AlarmControllerTest.kt
│           │   ├── GeofenceControllerTest.kt
│           │   └── AuthControllerTest.kt
│           └── util/
│               └── HaversineUtilTest.kt
```

### 3.3 Database Schema (Flyway migrations)

**V1__create_users.sql**
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  display_name VARCHAR(100),
  fcm_token VARCHAR(500),
  snooze_duration_minutes INT DEFAULT 9,
  theme VARCHAR(20) DEFAULT 'system',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

**V2__create_geofence_zones.sql**
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE TABLE geofence_zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  centre_lat DOUBLE PRECISION NOT NULL,
  centre_lng DOUBLE PRECISION NOT NULL,
  radius_metres INT NOT NULL CHECK (radius_metres BETWEEN 50 AND 50000),
  location GEOGRAPHY(POINT, 4326),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_geofence_user ON geofence_zones(user_id);
```

**V3__create_alarms.sql**
```sql
CREATE TYPE trigger_type AS ENUM ('TIME', 'GEO_ENTER', 'GEO_EXIT', 'COMBINED');
CREATE TYPE repeat_rule AS ENUM ('ONCE', 'DAILY', 'WEEKDAYS', 'CUSTOM');

CREATE TABLE alarms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label VARCHAR(100),
  trigger_type trigger_type NOT NULL,
  scheduled_time TIME,                     -- for TIME / COMBINED triggers
  repeat_rule repeat_rule DEFAULT 'ONCE',
  custom_days VARCHAR(20),                 -- e.g. "1,3,5" for Mon/Wed/Fri
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
```

**V4__create_location_events.sql**
```sql
CREATE TABLE location_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy_metres DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_location_user_time ON location_events(user_id, recorded_at DESC);
```

### 3.4 REST API Endpoints

#### Auth
```
POST   /api/v1/auth/register        Body: { email, password, displayName }
POST   /api/v1/auth/login           Body: { email, password }
POST   /api/v1/auth/refresh         Body: { refreshToken }
POST   /api/v1/auth/logout
PUT    /api/v1/auth/fcm-token       Body: { fcmToken }
```

#### Alarms
```
GET    /api/v1/alarms               Returns all alarms for authenticated user
POST   /api/v1/alarms               Body: AlarmRequest
GET    /api/v1/alarms/{id}
PUT    /api/v1/alarms/{id}          Body: AlarmRequest
DELETE /api/v1/alarms/{id}
PATCH  /api/v1/alarms/{id}/toggle   Enable/disable alarm
```

#### Geofence Zones
```
GET    /api/v1/geofences            Returns all zones for authenticated user
POST   /api/v1/geofences            Body: GeofenceRequest
GET    /api/v1/geofences/{id}
PUT    /api/v1/geofences/{id}
DELETE /api/v1/geofences/{id}
PATCH  /api/v1/geofences/{id}/toggle
```

#### Location
```
POST   /api/v1/location/update      Body: { latitude, longitude, accuracy }
GET    /api/v1/location/current     Returns last known location
```

#### User
```
GET    /api/v1/users/me
PUT    /api/v1/users/me/preferences Body: { snoozeDuration, theme, defaultRingtone }
DELETE /api/v1/users/me
```

### 3.5 Core Service Logic

#### GeofenceService.kt
```kotlin
// Implement these methods:

// evaluateLocation(userId: UUID, lat: Double, lng: Double)
//   1. Fetch all active geofence zones for the user
//   2. For each zone: call HaversineUtil.distanceMetres(zoneLat, zoneLng, lat, lng)
//   3. Determine if device is inside (distance < zone.radius)
//   4. Compare against cached previous state in Redis (key: "geo:state:{userId}:{zoneId}")
//   5. If state changed (outside→inside OR inside→outside):
//      a. Publish GeofenceTransitionEvent to RabbitMQ
//      b. Update Redis cache with new state
//   6. Return list of active zone statuses

// GeofenceTransitionEvent fields: userId, zoneId, zoneName, transitionType (ENTER/EXIT), timestamp
```

#### HaversineUtil.kt
```kotlin
// Implement distanceMetres(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double
// Use the Haversine formula:
//   R = 6371000 (Earth radius in metres)
//   φ1, φ2 = lat1 and lat2 in radians
//   Δφ = (lat2 - lat1) in radians
//   Δλ = (lng2 - lng1) in radians
//   a = sin²(Δφ/2) + cos(φ1) * cos(φ2) * sin²(Δλ/2)
//   c = 2 * atan2(√a, √(1−a))
//   d = R * c
// Return d (distance in metres)
```

#### AlarmService.kt
```kotlin
// Implement these methods:

// scheduleAlarm(alarm: Alarm)
//   - For TIME or COMBINED alarms: schedule a Quartz job using alarm.scheduledTime and repeatRule
//   - For GEO_ENTER / GEO_EXIT alarms: no scheduling needed — triggered by geo events
//   - Store quartz job key on the alarm entity

// cancelAlarm(alarm: Alarm)
//   - Unschedule the Quartz job if it exists
//   - Clear quartz job key

// triggerAlarm(alarm: Alarm)
//   - Call NotificationService.sendAlarmNotification(alarm)
//   - If alarm.repeatRule == ONCE: deactivate the alarm after triggering
//   - Log the trigger event

// onGeofenceTransition(event: GeofenceTransitionEvent)
//   - Consume RabbitMQ message
//   - Find all active GEO_ENTER / GEO_EXIT alarms linked to event.zoneId
//   - Match alarm.triggerType to event.transitionType
//   - For COMBINED alarms: also check current time is within ±5 minutes of scheduledTime
//   - Call triggerAlarm() for each matching alarm
```

#### NotificationService.kt
```kotlin
// sendAlarmNotification(alarm: Alarm)
//   1. Send FCM push notification to user's fcmToken (alarm.user.fcmToken)
//      Payload: { title: alarm.label, body: "Time to wake up!", data: { alarmId, type } }
//   2. Send WebSocket message to /topic/alarms/{userId}
//      Payload: AlarmTriggerEvent (alarmId, label, triggeredAt)
//   3. Handle missing fcmToken gracefully (log warning, continue)
//   4. Handle FCM errors (invalid token: mark token as null in DB, retry logic for network errors)
```

### 3.6 WebSocket Configuration

```kotlin
// STOMP over WebSocket
// Endpoint: /ws  (SockJS fallback enabled)
// Message broker topics:
//   /topic/alarms/{userId}    — alarm trigger events pushed to app
//   /topic/geo/{userId}       — real-time geofence state updates
// App destination prefix: /app
// Authentication: validate JWT token in HandshakeInterceptor before upgrading connection
```

### 3.7 Unit Test Requirements (Backend)

Every test class must use **JUnit 5 + MockK**. Use **Testcontainers** for repository-level integration tests.

#### HaversineUtilTest.kt — test cases required:
```
- distanceMetres: same point → 0.0
- distanceMetres: London to Paris → ~341,000m (within 1% tolerance)
- distanceMetres: 10m apart coordinates → result within expected range
- distanceMetres: antipodal points → ~20,015,000m
- distanceMetres: negative latitudes/longitudes (southern hemisphere)
```

#### GeofenceServiceTest.kt — test cases required:
```
- evaluateLocation: device inside zone → returns INSIDE status
- evaluateLocation: device outside zone → returns OUTSIDE status
- evaluateLocation: transition outside→inside → publishes ENTER event to queue
- evaluateLocation: transition inside→outside → publishes EXIT event to queue
- evaluateLocation: no state change → does NOT publish event
- evaluateLocation: no active zones for user → returns empty list
- evaluateLocation: multiple zones, device inside only one → correct statuses for all
```

#### AlarmServiceTest.kt — test cases required:
```
- scheduleAlarm: TIME alarm → Quartz job created with correct trigger time
- scheduleAlarm: GEO_ENTER alarm → no Quartz job created
- cancelAlarm: existing job → Quartz job deleted
- cancelAlarm: no job key → no error thrown
- triggerAlarm: ONCE alarm → alarm deactivated after trigger
- triggerAlarm: DAILY alarm → alarm remains active after trigger
- onGeofenceTransition: matching GEO_ENTER alarm → alarm triggered
- onGeofenceTransition: GEO_EXIT event with only GEO_ENTER alarm → NOT triggered
- onGeofenceTransition: COMBINED alarm within time window → triggered
- onGeofenceTransition: COMBINED alarm outside time window → NOT triggered
```

#### AlarmControllerTest.kt — test cases required:
```
- POST /alarms: valid request → 201 Created with alarm in body
- POST /alarms: missing required fields → 400 Bad Request
- POST /alarms: unauthenticated → 401 Unauthorized
- GET /alarms: returns only alarms belonging to authenticated user
- PUT /alarms/{id}: other user's alarm → 403 Forbidden
- DELETE /alarms/{id}: own alarm → 204 No Content
- PATCH /alarms/{id}/toggle: toggles isActive field
```

---

## 4. Frontend Specification (React Native + Expo)

### 4.1 Project Setup

```
Tech stack:
- React Native 0.74+
- Expo SDK 51+
- TypeScript (strict mode)
- Expo Router (file-based navigation)
- Zustand (state management)
- React Query / TanStack Query (server state + caching)
- Axios (HTTP client)
- react-native-maps (Google Maps)
- expo-location (GPS + background tracking)
- expo-notifications (local push notifications)
- expo-av (alarm audio playback)
- React Native Reanimated 3 (animations)
- Jest + React Native Testing Library (unit tests)
```

### 4.2 Directory Structure

```
frontend/
├── app/                          # Expo Router screens
│   ├── (tabs)/
│   │   ├── _layout.tsx           # Tab navigator: Clock | Alarms | Map | Settings
│   │   ├── clock.tsx             # Clock, Timer, Stopwatch tabs
│   │   ├── alarms.tsx            # Alarm list + create
│   │   ├── map.tsx               # GeoFence map view
│   │   └── settings.tsx
│   ├── alarm/
│   │   ├── [id].tsx              # Edit alarm screen
│   │   └── new.tsx               # Create alarm screen
│   ├── geofence/
│   │   ├── [id].tsx              # Edit zone screen
│   │   └── new.tsx               # Draw new zone screen
│   ├── auth/
│   │   ├── login.tsx
│   │   └── register.tsx
│   └── _layout.tsx               # Root layout + auth guard
├── src/
│   ├── components/
│   │   ├── clock/
│   │   │   ├── AnalogClock.tsx
│   │   │   ├── DigitalClock.tsx
│   │   │   ├── Stopwatch.tsx
│   │   │   └── CountdownTimer.tsx
│   │   ├── alarm/
│   │   │   ├── AlarmCard.tsx
│   │   │   ├── AlarmForm.tsx
│   │   │   ├── AlarmRingingModal.tsx
│   │   │   └── RepeatRulePicker.tsx
│   │   ├── map/
│   │   │   ├── GeofenceMap.tsx
│   │   │   ├── ZoneOverlay.tsx
│   │   │   └── RadiusPicker.tsx
│   │   └── shared/
│   │       ├── Button.tsx
│   │       ├── Input.tsx
│   │       └── LoadingSpinner.tsx
│   ├── store/
│   │   ├── authStore.ts          # JWT tokens, user object
│   │   ├── alarmStore.ts         # Local alarm state + optimistic updates
│   │   └── geofenceStore.ts      # Zone state + active geo statuses
│   ├── services/
│   │   ├── api.ts                # Axios instance with JWT interceptor
│   │   ├── alarmApi.ts           # CRUD calls for alarms
│   │   ├── geofenceApi.ts        # CRUD calls for zones
│   │   ├── locationService.ts    # Background GPS + polling to backend
│   │   ├── notificationService.ts# Local notification scheduling
│   │   └── websocketService.ts   # STOMP client for real-time events
│   ├── hooks/
│   │   ├── useStopwatch.ts       # Stopwatch logic (start/stop/lap/reset)
│   │   ├── useCountdownTimer.ts  # Timer logic (start/pause/reset)
│   │   ├── useCurrentTime.ts     # Updates every second for clock display
│   │   ├── useAlarms.ts          # React Query wrapper for alarm API
│   │   └── useGeofences.ts       # React Query wrapper for geofence API
│   ├── types/
│   │   ├── Alarm.ts
│   │   ├── GeofenceZone.ts
│   │   └── User.ts
│   └── utils/
│       ├── timeFormat.ts         # formatDuration, formatTime, pad helpers
│       └── mapHelpers.ts         # latLng helpers, radius circle coords
├── __tests__/
│   ├── hooks/
│   │   ├── useStopwatch.test.ts
│   │   ├── useCountdownTimer.test.ts
│   │   └── useCurrentTime.test.ts
│   ├── components/
│   │   ├── AlarmCard.test.tsx
│   │   └── AlarmForm.test.tsx
│   └── utils/
│       └── timeFormat.test.ts
└── app.json
```

### 4.3 Screen Specifications

#### Clock Screen (`clock.tsx`)
- Three sub-tabs: **Clock**, **Timer**, **Stopwatch**
- **Clock tab**: `AnalogClock` + `DigitalClock` components side by side. Uses `useCurrentTime` hook that updates state every second via `setInterval`. No API calls.
- **Timer tab**: HH:MM:SS input. Start/Pause/Reset buttons. Progress ring animation (Reanimated). Plays alarm tone via `expo-av` when complete. Schedules local notification as backup.
- **Stopwatch tab**: MM:SS.ms display. Start/Stop/Lap/Reset. Scrollable lap list showing split and total time per lap.

#### Alarms Screen (`alarms.tsx`)
- List of all user alarms grouped by type (Standard / GeoFence)
- Each `AlarmCard` shows: label, time or zone name, trigger type icon, toggle switch, next-trigger preview
- Swipe left to delete with confirmation
- FAB (floating action button) → navigate to `alarm/new.tsx`
- Pull-to-refresh syncs from backend

#### Alarm Form (`alarm/new.tsx` + `alarm/[id].tsx`)
- Label input
- Trigger type selector: Time / On Enter / On Exit / Combined
- If TIME or COMBINED: time picker (native)
- If geo trigger: zone selector (dropdown from user's zones)
- Repeat rule picker
- Ringtone picker
- Snooze duration picker
- Gradual volume toggle
- Save triggers POST or PUT to backend, then schedules/updates local notification

#### Map Screen (`map.tsx`)
- Full-screen Google Map via `react-native-maps`
- All user's geofence zones rendered as semi-transparent circles (`ZoneOverlay`)
- Active zone: green tint. Inactive: grey tint.
- Long-press map → begins drawing new zone (drops pin at press point)
- After long-press: radius slider appears → shows expanding circle preview
- Confirm → navigate to `geofence/new.tsx` with coordinates pre-filled
- Tap existing zone circle → bottom sheet with zone name, radius, edit/delete actions

#### Geofence Form (`geofence/new.tsx` + `geofence/[id].tsx`)
- Zone name input
- Coordinates display (read-only, set from map interaction or manual lat/lng entry)
- Radius slider (50m – 50km, with live map preview)
- Active toggle
- Save triggers POST or PUT

### 4.4 Background Location Service

```typescript
// locationService.ts

// startBackgroundTracking()
//   - Request foreground then background location permissions
//   - Use expo-location startLocationUpdatesAsync with task name 'WAKEY_LOCATION'
//   - Config: accuracy: Location.Accuracy.Balanced, distanceInterval: 20 (metres)
//   - Defined task (via TaskManager.defineTask) calls backend POST /api/v1/location/update
//   - On backend response: if geofence transition detected, WebSocket event will arrive separately

// stopBackgroundTracking()
//   - Call expo-location stopLocationUpdatesAsync('WAKEY_LOCATION')
```

### 4.5 WebSocket / Real-time

```typescript
// websocketService.ts

// connect(userId: string, token: string)
//   - Create STOMP client over SockJS at {API_URL}/ws
//   - Pass JWT in connection headers
//   - Subscribe to /topic/alarms/{userId} → on message: dispatch to alarmStore
//   - Subscribe to /topic/geo/{userId} → on message: update geofenceStore zone statuses
//   - On alarm trigger message: show AlarmRingingModal

// disconnect()
//   - Deactivate STOMP client
```

### 4.6 Unit Test Requirements (Frontend)

Use **Jest + React Native Testing Library**.

#### useStopwatch.test.ts
```
- Initial state: running=false, elapsed=0, laps=[]
- start(): running becomes true
- stop(): running becomes false, elapsed preserved
- reset(): running=false, elapsed=0, laps=[]
- lap(): appends current elapsed to laps array
- Elapsed increments correctly over mocked time intervals
```

#### useCountdownTimer.test.ts
```
- Initial state: remaining=targetDuration, running=false, finished=false
- start(): running becomes true
- pause(): running becomes false, remaining preserved
- reset(): remaining=targetDuration, running=false, finished=false
- Timer reaches zero: finished=true, running=false
- Does not go below zero
```

#### timeFormat.test.ts
```
- formatDuration(0) → "00:00"
- formatDuration(61000) → "01:01"
- formatDuration(3661000) → "01:01:01"
- formatTime(new Date('2024-01-01T09:05:00')) → "09:05"
- pad(5, 2) → "05"
- pad(123, 2) → "123" (no truncation)
```

#### AlarmCard.test.tsx
```
- Renders alarm label
- Renders formatted scheduled time for TIME alarms
- Renders zone name for GEO_ENTER alarms
- Toggle switch fires onToggle callback with alarm id
- Swipe delete renders confirmation prompt
```

---

## 5. Environment Variables

### Backend (`application.yml` + env)
```yaml
POSTGRES_URL: jdbc:postgresql://localhost:5432/wakey
POSTGRES_USER: wakey
POSTGRES_PASSWORD: <secret>
REDIS_HOST: localhost
REDIS_PORT: 6379
RABBITMQ_HOST: localhost
RABBITMQ_PORT: 5672
RABBITMQ_USER: wakey
RABBITMQ_PASSWORD: <secret>
JWT_SECRET: <256-bit-secret>
JWT_ACCESS_EXPIRY_MINUTES: 15
JWT_REFRESH_EXPIRY_DAYS: 30
FIREBASE_CREDENTIALS_PATH: /secrets/firebase-service-account.json
```

### Frontend (`.env`)
```
EXPO_PUBLIC_API_URL=http://localhost:8080
EXPO_PUBLIC_GOOGLE_MAPS_API_KEY=<secret>
EXPO_PUBLIC_WS_URL=ws://localhost:8080/ws
```

---

## 6. Docker Compose (Local Dev)

```yaml
# docker-compose.yml — provides all backend dependencies for local development
services:
  postgres:
    image: postgis/postgis:15-3.4
    environment:
      POSTGRES_DB: wakey
      POSTGRES_USER: wakey
      POSTGRES_PASSWORD: wakey
    ports: ["5432:5432"]
    volumes: ["postgres_data:/var/lib/postgresql/data"]

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    ports: ["5672:5672", "15672:15672"]
    environment:
      RABBITMQ_DEFAULT_USER: wakey
      RABBITMQ_DEFAULT_PASS: wakey

volumes:
  postgres_data:
```

---

## 7. CI/CD Pipeline

Create `.github/workflows/ci.yml` with the following jobs:

### backend-test job
```
1. Checkout code
2. Set up JDK 21
3. Start docker-compose services (postgres, redis, rabbitmq)
4. Run: ./gradlew test
5. Run: ./gradlew jacocoTestReport
6. Fail if coverage < 80%
7. Upload test results and coverage report as artifacts
```

### frontend-test job
```
1. Checkout code
2. Set up Node 20
3. Run: npm ci
4. Run: npm test -- --coverage --watchAll=false
5. Fail if coverage < 75%
6. Upload coverage report as artifact
```

### build job (runs after both test jobs pass)
```
1. Backend: ./gradlew bootJar
2. Frontend: expo export
```

---

## 8. Build Order

Copilot must implement features in this exact sequence to ensure each layer builds on a working foundation:

```
Phase 1 — Backend Foundation
  1.1  Docker Compose + DB setup
  1.2  Flyway migrations (all 4 tables)
  1.3  JPA entities + repositories
  1.4  HaversineUtil + HaversineUtilTest (all 5 tests passing)
  1.5  Auth (register/login/JWT/refresh) + AuthControllerTest

Phase 2 — Backend Core Services
  2.1  GeofenceService + GeofenceServiceTest (all 7 tests passing)
  2.2  AlarmService + AlarmServiceTest (all 9 tests passing)
  2.3  NotificationService (FCM + WebSocket)
  2.4  REST controllers + controller tests
  2.5  RabbitMQ consumer wiring (AlarmService.onGeofenceTransition)

Phase 3 — Frontend Foundation
  3.1  Expo project init + Expo Router setup
  3.2  Auth screens (login/register) + authStore + API client with JWT interceptor
  3.3  Tab navigator shell (4 tabs, placeholder screens)

Phase 4 — Frontend Clock Module
  4.1  useCurrentTime hook + useCurrentTime.test.ts
  4.2  DigitalClock + AnalogClock components
  4.3  useStopwatch hook + useStopwatch.test.ts + Stopwatch component
  4.4  useCountdownTimer hook + useCountdownTimer.test.ts + CountdownTimer component

Phase 5 — Frontend Alarm Module
  5.1  useAlarms hook (React Query) + alarmApi.ts
  5.2  AlarmCard component + AlarmCard.test.tsx
  5.3  AlarmForm component + AlarmForm.test.tsx
  5.4  Alarms screen (list, toggle, delete)
  5.5  Local notification scheduling via notificationService.ts

Phase 6 — Frontend GeoFence Module
  6.1  useGeofences hook + geofenceApi.ts
  6.2  GeofenceMap + ZoneOverlay components
  6.3  Map screen (view zones, long-press to start new zone)
  6.4  Geofence form (name, radius, save)
  6.5  Background location tracking (locationService.ts)

Phase 7 — Real-time Integration
  7.1  WebSocket service (connect, subscribe, dispatch)
  7.2  AlarmRingingModal (triggered by WebSocket alarm event)
  7.3  Geo status indicators on map (live zone state from WebSocket)

Phase 8 — CI/CD
  8.1  GitHub Actions workflow (backend-test → frontend-test → build)
  8.2  Jacoco + coverage enforcement
```

---

## 9. Coding Standards

- **Kotlin**: use `data class` for DTOs, `sealed class` for result types, extension functions for utility logic
- **TypeScript**: strict mode on, no `any` types, prefer `type` over `interface` for shapes
- **Error handling**: backend returns RFC 7807 problem+json; frontend shows user-friendly toasts
- **Logging**: use SLF4J in Kotlin; all service method entries and errors logged at appropriate levels
- **Security**: sanitise all inputs, parameterise all DB queries (no string concatenation in SQL), store only hashed passwords (BCrypt, strength 12)
- **Accessibility**: all React Native components include `accessibilityLabel` props
- **No magic numbers**: extract all constants (earth radius, default snooze, polling interval) into named constants or config values

---

*End of wakey-requirements.md — feed this file to GitHub Copilot with the Claude Sonnet 4.6 model and instruct it to begin at Phase 1 of the Build Order.*
