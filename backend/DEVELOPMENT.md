# Wakey Backend - Development Guide

## Getting Started

### Prerequisites
- Java 17+
- Gradle 8+
- Docker & Docker Compose
- Git

### First-Time Setup

```bash
# Clone repository
git clone <repo-url>
cd wakey-alarm

# Start infrastructure (PostgreSQL, Redis, RabbitMQ)
cd backend
docker-compose up -d

# Build project
./gradlew build

# Run tests
./gradlew test

# Start development server
./gradlew bootRun
```

Server runs on `http://localhost:8080`

## Architecture Overview

### Layered Architecture

```
┌─────────────────────────────────┐
│   REST API Layer (Controllers)  │
│   GET, POST, PUT, DELETE, PATCH │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│   Service Layer (Business Logic)│
│   Handles domain operations     │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│ Repository Layer (Data Access)  │
│   JPA/Spring Data Repositories  │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│   Persistence Layer (Database)  │
│   PostgreSQL + PostGIS          │
└─────────────────────────────────┘
```

### Key Components

**API Layer** (`api/` package)
- Controllers handle HTTP requests/responses
- Path: `/api/v1/*`
- Endpoints: Auth, Alarms, Geofences, Location, User

**Service Layer** (`service/` package)
- Core business logic
- Transaction management
- External service coordination
- Event publishing

**Repository Layer** (`repository/` package)
- Spring Data JPA interfaces
- Custom JPQL queries when needed
- Automatic CRUD operations

**Model Layer** (`model/` package)
- JPA Entities with annotations
- Enums for type safety
- Database relationships

**Config Layer** (`config/` package)
- Spring Security configuration
- JWT authentication
- WebSocket setup
- Redis/RabbitMQ configuration

**Utility Layer** (`util/` package)
- Haversine distance calculations
- JWT token generation/validation
- Helper functions

**Exception Handling** (`exception/` package)
- Custom exception classes
- Global exception handler with @RestControllerAdvice
- Standardized error responses

## Development Workflow

### 1. Creating a New Feature

Example: Add feature to pause alarms

```
Step 1: Create test file (TDD approach)
├─ AlarmServiceTest.kt (add test for pauseAlarm)
└─ AlarmControllerTest.kt (add test for PATCH /alarms/{id}/pause)

Step 2: Update model if needed
├─ Modify Alarm.kt (add pausedUntil field)
└─ Create Flyway migration (V5__add_paused_until.sql)

Step 3: Update repository if needed
├─ AlarmRepository.kt (add custom query if needed)
└─ Verify JPA handles new field

Step 4: Implement service logic
├─ AlarmService.kt (add pauseAlarm method)
└─ Write business logic

Step 5: Implement API endpoint
├─ AlarmController.kt (add PATCH endpoint)
└─ Add request/response DTOs if needed

Step 6: Run tests
├─ ./gradlew test
└─ All tests must pass

Step 7: Commit
├─ git add -A
└─ git commit -m "feat: add pause alarm functionality"
```

### 2. Writing Tests

Always follow TDD (Test-Driven Development):

```kotlin
@DisplayName("AlarmService Test Suite")
class AlarmServiceTest {

    // Setup dependencies
    private val alarmRepository = mockk<AlarmRepository>()
    private val service = AlarmService(alarmRepository)

    @Test
    @DisplayName("pauseAlarm: sets pausedUntil timestamp")
    fun testPauseAlarm() {
        val alarm = Alarm(...)
        val futureTime = LocalDateTime.now().plusHours(1)

        every { alarmRepository.save(any()) } returns alarm
        
        val result = service.pauseAlarm(alarm.id, futureTime)

        assertEquals(futureTime, result.pausedUntil)
        verify { alarmRepository.save(any()) }
    }
}
```

### 3. Adding Database Changes

Flyway migrations run automatically on startup:

```
File naming: V{version}__{description}.sql
Example: V5__add_paused_until_column.sql

SQL content:
ALTER TABLE alarms ADD COLUMN paused_until TIMESTAMPTZ;
CREATE INDEX idx_alarm_paused ON alarms(paused_until);
```

**Important**: Always write migrations, never modify V1-V4 files!

### 4. API Development

#### Request Validation

```kotlin
data class AlarmRequest(
    @NotBlank(message = "Label cannot be empty")
    val label: String,

    @NotNull
    val triggerType: AlarmTriggerType,

    val scheduledTime: LocalTime?,

    @Min(1) @Max(30)
    val snoozeDurationMinutes: Int = 9
)
```

#### Error Handling

```kotlin
@PostMapping
fun createAlarm(
    authentication: Authentication,
    @Valid @RequestBody request: AlarmRequest
): ResponseEntity<AlarmResponse> {
    try {
        val userId = UUID.fromString(authentication.principal as String)
        val user = userService.getUserById(userId) // throws if not found
        val alarm = alarmService.createAlarm(...)
        return ResponseEntity.status(HttpStatus.CREATED).body(alarm.toResponse())
    } catch (e: ResourceNotFoundException) {
        // Caught by GlobalExceptionHandler → 404
        throw e
    }
}
```

## Project Structure Details

### Package Organization

```
com.wakey/
├── api/                     # REST Controllers
│   ├── AlarmController.kt
│   ├── GeofenceController.kt
│   ├── AuthController.kt
│   ├── LocationController.kt
│   └── UserController.kt
│
├── service/                 # Business Logic
│   ├── AlarmService.kt
│   ├── GeofenceService.kt
│   ├── AuthService.kt
│   ├── NotificationService.kt
│   └── UserService.kt
│
├── model/                   # JPA Entities
│   ├── User.kt
│   ├── Alarm.kt
│   ├── GeofenceZone.kt
│   ├── LocationEvent.kt
│   └── Enums.kt (AlarmTriggerType, RepeatRule)
│
├── repository/              # Data Access
│   ├── UserRepository.kt
│   ├── AlarmRepository.kt
│   ├── GeofenceRepository.kt
│   └── LocationEventRepository.kt
│
├── dto/                     # Transfer Objects
│   ├── request/
│   │   ├── AlarmRequests.kt
│   │   ├── GeofenceRequests.kt
│   │   └── AuthRequests.kt
│   └── response/
│       ├── AlarmResponses.kt
│       ├── GeofenceResponses.kt
│       └── AuthResponses.kt
│
├── config/                  # Spring Configuration
│   ├── SecurityConfig.kt
│   ├── WebSocketConfig.kt
│   ├── RedisConfig.kt
│   ├── RabbitMQConfig.kt
│   └── JwtAuthenticationFilter.kt
│
├── exception/               # Error Handling
│   ├── CustomExceptions.kt
│   └── GlobalExceptionHandler.kt
│
└── util/                    # Utilities
    ├── HaversineUtil.kt
    └── JwtUtil.kt
```

## Testing Guide

### Test Organization

```
backend/src/test/kotlin/com/wakey/

service/                    # Service layer tests
├── AuthServiceTest.kt
├── AlarmServiceTest.kt
├── GeofenceServiceTest.kt
├── NotificationServiceTest.kt
└── UserServiceTest.kt

api/                        # Controller layer tests
├── AlarmControllerTest.kt
├── AuthControllerTest.kt
└── GeofenceControllerTest.kt

util/                       # Utility tests
└── HaversineUtilTest.kt
```

### Running Tests

```bash
# Run all tests
./gradlew test

# Run specific test class
./gradlew test --tests AlarmServiceTest

# Run tests matching pattern
./gradlew test --tests "*Service*"

# Run with coverage
./gradlew test jacocoTestReport
```

## Database Guide

### Connection

```bash
# PostgreSQL
Host: localhost
Port: 5432
Database: wakey
User: wakey_user
Password: wakey_password

# Connect with psql
psql -h localhost -U wakey_user -d wakey
```

### Useful Queries

```sql
-- List all users
SELECT id, email, display_name, created_at FROM users;

-- List user's alarms
SELECT a.id, a.label, a.trigger_type, a.scheduled_time 
FROM alarms a 
JOIN users u ON a.user_id = u.id 
WHERE u.email = 'test@example.com';

-- View geofence zones with geospatial data
SELECT id, name, ST_AsText(location), radius_metres 
FROM geofence_zones;

-- Check location events for a user
SELECT latitude, longitude, accuracy_metres, recorded_at 
FROM location_events 
WHERE user_id = '550e8400-e29b-41d4-a716-446655440000' 
ORDER BY recorded_at DESC LIMIT 10;
```

### Schema Management

```bash
# View current migration status
./gradlew flywayInfo

# Validate migrations
./gradlew flywayValidate

# Repair migration history (if needed)
./gradlew flywayRepair
```

## Performance Tips

1. **N+1 Query Prevention**
   - Use `@OneToMany(fetch = FetchType.LAZY)`
   - Only eager-load when necessary

2. **Database Indexing**
   - Check indices on frequently queried columns
   - See Flyway migrations for current indices

3. **Redis Caching**
   - Geofence zone state cached
   - User location cached temporarily

4. **Connection Pooling**
   - HikariCP handles connection pool automatically
   - Configure in `application.yml` if needed

## Git Workflow

### Commit Message Format

```
type(scope): subject

Body with more details if needed.

Footer with issue/PR references if applicable.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

**Types**: feat, fix, test, docs, refactor, perf, chore

**Example**:
```
feat(alarm): add pause functionality

Implements pauseAlarm method in AlarmService that pauses
active alarms until specified time. Works with all alarm
types and persists state to database.

Closes #42
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

### Branching

```bash
# Feature branch
git checkout -b feature/pause-alarm

# Develop locally
# Run tests: ./gradlew test
# Commit: git commit -m "feat: ..."

# Push and create PR
git push origin feature/pause-alarm
```

## Troubleshooting

### Build Issues

```bash
# Clean build
./gradlew clean build

# Check for dependency conflicts
./gradlew dependencies

# Update dependencies
./gradlew dependencyUpdates
```

### Database Issues

```bash
# Restart database
docker-compose down && docker-compose up -d

# Reset database (WARNING: loses data)
docker-compose down -v && docker-compose up -d

# View PostgreSQL logs
docker logs wakey_postgres
```

### Test Failures

```bash
# Run with debug output
./gradlew test --debug

# Run single test
./gradlew test --tests ClassName::methodName

# Rerun failed tests
./gradlew test --rerun-tasks
```

## Security Checklist

- [ ] JWT_SECRET changed in production
- [ ] POSTGRES_PASSWORD is strong
- [ ] RABBITMQ_PASSWORD is strong
- [ ] CORS origins configured correctly
- [ ] No hardcoded credentials in code
- [ ] All API endpoints require authentication (except /auth/*)
- [ ] Password hashing uses BCrypt
- [ ] SQL injection protection via parameterized queries

## Next Steps

1. **Quartz Integration**
   - Implement alarm scheduling with Quartz
   - Schedule jobs for TIME alarms
   - Handle cron expressions

2. **Firebase Integration**
   - Setup Firebase Admin SDK
   - Implement FCM push notifications
   - Handle token validation

3. **Performance**
   - Add query optimization
   - Implement caching strategy
   - Add database indices

4. **Frontend**
   - React Native/Expo project
   - Implement clock features
   - Build alarm UI

## Resources

- [Spring Boot Documentation](https://spring.io/projects/spring-boot)
- [Spring Data JPA](https://spring.io/projects/spring-data-jpa)
- [Kotlin Documentation](https://kotlinlang.org/docs)
- [JWT.io](https://jwt.io)
- [PostGIS Documentation](https://postgis.net)

---

**Last Updated**: January 2024
