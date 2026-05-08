# Wakey - GeoFence Alarm API Documentation

## Base URL
```
http://localhost:8080/api/v1
```

## Authentication
All endpoints (except /auth/register and /auth/login) require JWT token in Authorization header:
```
Authorization: Bearer <access_token>
```

---

## Authentication Endpoints

### 1. Register User
**POST** `/auth/register`

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "secure_password",
  "displayName": "John Doe"
}
```

**Response (201 Created):**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIs...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIs...",
  "expiresIn": 900,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "displayName": "John Doe",
    "snoozeDurationMinutes": 9,
    "theme": "system",
    "createdAt": "2024-01-15T10:30:00Z"
  }
}
```

### 2. Login User
**POST** `/auth/login`

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "secure_password"
}
```

**Response (200 OK):**
Same as register response

### 3. Refresh Access Token
**POST** `/auth/refresh`
- Requires: Valid JWT token in Authorization header

**Response (200 OK):**
```json
{
  "accessToken": "new_access_token",
  "refreshToken": "new_refresh_token",
  "expiresIn": 900,
  "user": {...}
}
```

### 4. Update FCM Token
**PUT** `/auth/fcm-token`
- Requires: Valid JWT token

**Request Body:**
```json
{
  "fcmToken": "cP1NRp9L_qQ:APA91b..."
}
```

**Response (204 No Content)**

### 5. Logout
**POST** `/auth/logout`
- Requires: Valid JWT token

**Response (200 OK):**
```json
{
  "message": "Logged out successfully"
}
```

---

## Alarm Endpoints

### 1. Get All Alarms
**GET** `/alarms`
- Requires: Valid JWT token

**Response (200 OK):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "label": "Wake up for work",
    "triggerType": "TIME",
    "scheduledTime": "07:00:00",
    "repeatRule": "DAILY",
    "customDays": null,
    "geofenceZoneId": null,
    "geofenceZoneName": null,
    "snoozeDurationMinutes": 9,
    "isActive": true,
    "ringtone": "default",
    "gradualVolume": false,
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T10:30:00Z"
  }
]
```

### 2. Create Alarm
**POST** `/alarms`
- Requires: Valid JWT token

**Request Body:**
```json
{
  "label": "Wake up for work",
  "triggerType": "TIME",
  "scheduledTime": "07:00:00",
  "repeatRule": "DAILY",
  "customDays": null,
  "geofenceZoneId": null,
  "snoozeDurationMinutes": 9,
  "ringtone": "default",
  "gradualVolume": false
}
```

**Response (201 Created):**
Same as Get All Alarms response (single alarm)

### 3. Get Alarm Details
**GET** `/alarms/{id}`
- Requires: Valid JWT token

**Response (200 OK):**
Single alarm object

### 4. Update Alarm
**PUT** `/alarms/{id}`
- Requires: Valid JWT token

**Request Body:**
Same as Create Alarm

**Response (200 OK):**
Updated alarm object

### 5. Delete Alarm
**DELETE** `/alarms/{id}`
- Requires: Valid JWT token

**Response (204 No Content)**

### 6. Toggle Alarm Active Status
**PATCH** `/alarms/{id}/toggle`
- Requires: Valid JWT token

**Response (200 OK):**
Updated alarm object with toggled `isActive`

---

## Geofence Endpoints

### 1. Get All Geofence Zones
**GET** `/geofences`
- Requires: Valid JWT token

**Response (200 OK):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440002",
    "name": "Office",
    "centreLat": 37.7749,
    "centreLng": -122.4194,
    "radiusMetres": 500,
    "isActive": true,
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T10:30:00Z"
  }
]
```

### 2. Create Geofence Zone
**POST** `/geofences`
- Requires: Valid JWT token

**Request Body:**
```json
{
  "name": "Office",
  "centreLat": 37.7749,
  "centreLng": -122.4194,
  "radiusMetres": 500,
  "isActive": true
}
```

**Response (201 Created):**
Single geofence zone object

### 3. Get Geofence Details
**GET** `/geofences/{id}`
- Requires: Valid JWT token

**Response (200 OK):**
Single geofence zone object

### 4. Update Geofence Zone
**PUT** `/geofences/{id}`
- Requires: Valid JWT token

**Request Body:**
```json
{
  "name": "Office Updated",
  "centreLat": 37.7750,
  "centreLng": -122.4195,
  "radiusMetres": 600,
  "isActive": true
}
```

**Response (200 OK):**
Updated geofence zone object

### 5. Delete Geofence Zone
**DELETE** `/geofences/{id}`
- Requires: Valid JWT token

**Response (204 No Content)**

### 6. Toggle Geofence Active Status
**PATCH** `/geofences/{id}/toggle`
- Requires: Valid JWT token

**Response (200 OK):**
Updated geofence zone with toggled `isActive`

---

## Location Endpoints

### 1. Update User Location
**POST** `/location/update`
- Requires: Valid JWT token

**Request Body:**
```json
{
  "latitude": 37.7749,
  "longitude": -122.4194,
  "accuracy": 10.5
}
```

**Response (200 OK)**
- Triggers geofence evaluation server-side
- Publishes events to WebSocket subscribers if zone transitions detected

### 2. Get Current Location
**GET** `/location/current`
- Requires: Valid JWT token

**Response (200 OK):**
```json
{
  "latitude": 37.7749,
  "longitude": -122.4194,
  "accuracy": 10.5,
  "recordedAt": "2024-01-15T10:35:00Z"
}
```

---

## User Endpoints

### 1. Get Current User Profile
**GET** `/users/me`
- Requires: Valid JWT token

**Response (200 OK):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "displayName": "John Doe",
  "snoozeDurationMinutes": 9,
  "theme": "system",
  "createdAt": "2024-01-15T10:30:00Z"
}
```

### 2. Update User Preferences
**PUT** `/users/me/preferences`
- Requires: Valid JWT token

**Request Body:**
```json
{
  "snoozeDuration": 15,
  "theme": "dark",
  "defaultRingtone": "bells"
}
```

**Response (200 OK):**
Updated user profile object

### 3. Delete User Account
**DELETE** `/users/me`
- Requires: Valid JWT token
- Deletes all associated alarms, geofences, and location history

**Response (204 No Content)**

---

## WebSocket Events

### Connection
```
URL: ws://localhost:8080/ws
Headers: {
  "Authorization": "Bearer <token>"
}
```

### Subscribe to Alarm Events
```javascript
client.subscribe('/topic/alarms/{userId}', (message) => {
  // Message payload: AlarmTriggerEvent
  console.log("Alarm triggered:", message.body);
});
```

### Subscribe to Geofence Updates
```javascript
client.subscribe('/topic/geo/{userId}', (message) => {
  // Message payload: GeofenceUpdateEvent
  console.log("Geofence transition:", message.body);
});
```

### Sample Alarm Trigger Event
```json
{
  "alarmId": "550e8400-e29b-41d4-a716-446655440001",
  "label": "Wake up for work",
  "triggeredAt": 1705319400000
}
```

### Sample Geofence Update Event
```json
{
  "zoneId": "550e8400-e29b-41d4-a716-446655440002",
  "zoneName": "Office",
  "isInside": true,
  "timestamp": 1705319400000
}
```

---

## Error Responses

All error responses follow this format:

```json
{
  "code": "ERROR_CODE",
  "message": "Human-readable error message",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Common Error Codes

| HTTP Status | Code | Meaning |
|---|---|---|
| 400 | VALIDATION_ERROR | Invalid request parameters |
| 401 | UNAUTHORIZED | Missing or invalid JWT token |
| 403 | FORBIDDEN | Insufficient permissions |
| 404 | NOT_FOUND | Resource not found |
| 409 | CONFLICT | Resource already exists |
| 500 | INTERNAL_ERROR | Server error |

---

## Alarm Trigger Types

- **TIME**: Alarm triggers at a specific time (supports repeat rules)
- **GEO_ENTER**: Alarm triggers when entering a geofence zone
- **GEO_EXIT**: Alarm triggers when leaving a geofence zone
- **COMBINED**: Time-based alarm that only triggers if inside/outside a zone

## Repeat Rules

- **ONCE**: Single trigger (default)
- **DAILY**: Every day at the specified time
- **WEEKDAYS**: Monday through Friday
- **CUSTOM**: User-defined days (format: "1,3,5" for Mon/Wed/Fri)

---

## Environment Variables

```bash
# Database
POSTGRES_URL=jdbc:postgresql://localhost:5432/wakey
POSTGRES_USER=wakey_user
POSTGRES_PASSWORD=wakey_password

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# RabbitMQ
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USER=wakey_user
RABBITMQ_PASSWORD=wakey_password

# JWT
JWT_SECRET=your_super_secret_key_change_in_production
```

---

## Building and Running

### Start Infrastructure
```bash
docker-compose up -d
```

### Build Backend
```bash
./gradlew build
```

### Run Backend
```bash
./gradlew bootRun
```

Server runs on `http://localhost:8080`
