# Wakey Backend - Kotlin + Spring Boot

A production-grade geofence alarm service built with **Kotlin**, **Spring Boot 3.2**, and **PostgreSQL**.

## Features

✅ User authentication with JWT tokens  
✅ Time-based alarms with repeat rules  
✅ Geofence zone management with real-time location tracking  
✅ Geofence-triggered alarms (on enter/exit/combined)  
✅ WebSocket support for real-time notifications  
✅ Firebase Cloud Messaging (FCM) push notifications  
✅ Redis caching for geofence state management  
✅ RabbitMQ event streaming  
✅ Comprehensive test coverage  
✅ Database migrations with Flyway  

## Tech Stack

- **Language**: Kotlin 1.9
- **Framework**: Spring Boot 3.2
- **Database**: PostgreSQL 15 + PostGIS
- **Cache**: Redis 7
- **Message Queue**: RabbitMQ 3.12
- **Scheduler**: Quartz 2.3
- **Auth**: JWT (JJWT 0.12)
- **Testing**: JUnit 5, MockK, Testcontainers
- **Build**: Gradle 8 (Kotlin DSL)

## Project Structure

```
backend/
├── src/
│   ├── main/kotlin/com/wakey/
│   │   ├── api/                    # REST Controllers
│   │   ├── service/                # Business Logic
│   │   ├── repository/             # Data Access Layer
│   │   ├── model/                  # JPA Entities & Enums
│   │   ├── dto/                    # Request/Response DTOs
│   │   ├── config/                 # Spring Configuration
│   │   ├── exception/              # Exception Handlers
│   │   ├── util/                   # Utility Functions
│   │   └── scheduler/              # Quartz Job Definitions
│   ├── main/resources/
│   │   ├── application.yml         # Spring Config
│   │   └── db/migration/           # Flyway SQL Scripts
│   └── test/
│       └── kotlin/com/wakey/       # Unit Tests
├── build.gradle.kts                # Gradle Build Config
├── docker-compose.yml              # Infrastructure Setup
├── API_DOCUMENTATION.md            # REST API Docs
└── README.md                       # This File
```

## Quick Start

### Prerequisites

- Java 17+
- Docker & Docker Compose
- Gradle 8+

### 1. Start Infrastructure

```bash
docker-compose up -d
```

This starts:
- PostgreSQL 15 (port 5432)
- Redis 7 (port 6379)
- RabbitMQ 3.12 (port 5672, Admin: 15672)

### 2. Build Project

```bash
./gradlew build
```

### 3. Run Application

```bash
./gradlew bootRun
```

Server runs on `http://localhost:8080`

### 4. API Documentation

See [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) for complete endpoint reference.

## Database Migrations

Migrations run automatically on startup via Flyway.

- **V1__create_users.sql** - User accounts and preferences
- **V2__create_geofence_zones.sql** - Geofence zones with PostGIS
- **V3__create_alarms.sql** - Alarms with geofence linking
- **V4__create_location_events.sql** - Location tracking history

## Configuration

### Environment Variables

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
JWT_SECRET=your_secret_key_here
```

### application.yml

Main configuration file at `src/main/resources/application.yml`

## Running Tests

```bash
# Run all tests
./gradlew test

# Run specific test class
./gradlew test --tests HaversineUtilTest

# Generate coverage report
./gradlew test jacocoTestReport
```

### Test Structure

- **HaversineUtilTest** - Geospatial distance calculations (5 test cases)
- **GeofenceServiceTest** - Zone state transitions (7 test cases)
- **AlarmServiceTest** - Alarm scheduling & triggering (10 test cases)
- **AlarmControllerTest** - REST endpoint validation (7 test cases)
- **AuthServiceTest** - Auth flow validation
- **AuthControllerTest** - Auth endpoint tests

## API Endpoints

### Authentication
```
POST   /api/v1/auth/register
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
PutMapping /api/v1/auth/fcm-token
POST   /api/v1/auth/logout
```

### Alarms
```
GET    /api/v1/alarms
POST   /api/v1/alarms
GET    /api/v1/alarms/{id}
PUT    /api/v1/alarms/{id}
DELETE /api/v1/alarms/{id}
PATCH  /api/v1/alarms/{id}/toggle
```

### Geofence Zones
```
GET    /api/v1/geofences
POST   /api/v1/geofences
GET    /api/v1/geofences/{id}
PUT    /api/v1/geofences/{id}
DELETE /api/v1/geofences/{id}
PATCH  /api/v1/geofences/{id}/toggle
```

### Location
```
POST   /api/v1/location/update
GET    /api/v1/location/current
```

### User
```
GET    /api/v1/users/me
PUT    /api/v1/users/me/preferences
DELETE /api/v1/users/me
```

## WebSocket Events

**Endpoint**: `ws://localhost:8080/ws`

**Topics**:
- `/topic/alarms/{userId}` - Alarm trigger notifications
- `/topic/geo/{userId}` - Geofence transition events

## Core Services

### AuthService
Handles user registration, login, and JWT token generation.

### UserService
Manages user profiles and preferences.

### GeofenceService
- Evaluates device location against zones
- Detects zone transitions
- Publishes transition events to RabbitMQ
- Caches zone state in Redis

### AlarmService
- Creates and schedules time-based alarms via Quartz
- Handles geofence-triggered alarms
- Supports repeat rules (once, daily, weekdays, custom)
- Manages alarm lifecycle (create, update, delete, toggle)

### NotificationService
- Sends FCM push notifications
- Broadcasts WebSocket messages
- Handles notification delivery & retry logic

## Geospatial Calculations

**HaversineUtil** implements the Haversine formula for accurate distance calculations between GPS coordinates.

```kotlin
// Calculate distance in meters
val meters = HaversineUtil.distanceMetres(lat1, lng1, lat2, lng2)

// Check if point is inside zone
val isInside = HaversineUtil.isPointInZone(lat, lng, zoneLat, zoneLng, radiusMetres)
```

## Error Handling

Centralized error handling via `GlobalExceptionHandler`:

- **400 Bad Request** - Validation errors
- **401 Unauthorized** - Missing/invalid JWT
- **403 Forbidden** - Insufficient permissions
- **404 Not Found** - Resource not found
- **409 Conflict** - Resource already exists
- **500 Internal Server Error** - Unexpected errors

## Logging

Structured logging via **kotlin-logging**:

```kotlin
logger.info { "User registered: ${user.email}" }
logger.debug { "Geofence transition: ${event.zoneName}" }
logger.error(e) { "FCM notification failed" }
```

Log level configured in `application.yml`.

## Performance Optimizations

- **Database indexing** on frequently queried columns
- **Redis caching** for geofence zone states
- **Connection pooling** via HikariCP
- **Lazy loading** for JPA relationships
- **Async WebSocket** broadcasting

## Security

✅ JWT token-based authentication  
✅ Password hashing with BCrypt  
✅ CORS enabled (configurable origins)  
✅ SQL injection protection via parameterized queries  
✅ CSRF protection disabled for API (stateless)  
✅ Rate limiting ready (implement via Spring Cloud Gateway)  

## Deployment

### Docker Build

```bash
docker build -t wakey-backend:0.1.0 .
```

### Environment-Specific Configs

- `application.yml` - Default (local)
- `application-prod.yml` - Production settings

## Future Enhancements

- [ ] Integrate Quartz scheduler for background jobs
- [ ] Firebase Admin SDK for FCM integration
- [ ] Multi-zone clustering detection
- [ ] Alarm statistics & analytics
- [ ] SMS notifications fallback
- [ ] Batch location updates
- [ ] Advanced repeat rule UI
- [ ] Alarm preview/simulation

## Contributing

1. Write tests first (TDD)
2. Follow Kotlin style guide
3. Use dependency injection
4. Add API docs for new endpoints
5. Update this README

## License

MIT License - See LICENSE file

## Support

For issues, feature requests, or documentation improvements, contact the development team.

---

**Last Updated**: January 2024  
**Version**: 0.1.0 (Beta)
