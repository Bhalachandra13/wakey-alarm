# Backend Testing Guide

## Test Organization

All tests are located in `backend/src/test/kotlin/com/wakey/`

### Test Layers

```
util/                           # Utility function tests
├── HaversineUtilTest.kt         # Geospatial calculations (5 tests)

service/                        # Business logic tests
├── AuthServiceTest.kt           # Authentication (5 tests)
├── GeofenceServiceTest.kt       # Geofence operations (7 tests)
├── AlarmServiceTest.kt          # Alarm scheduling (10 tests)
└── NotificationServiceTest.kt   # Notifications (3 tests)

api/                            # Controller/API tests
└── AlarmControllerTest.kt       # REST endpoints (7 tests)
```

**Total Test Coverage**: 37 test cases covering:
- Distance calculations
- User authentication & JWT
- Geofence zone state transitions
- Alarm creation, scheduling, triggering
- Geofence-triggered alarms
- REST API validation
- Error handling

## Running Tests

### All Tests
```bash
./gradlew test
```

### Specific Test Class
```bash
./gradlew test --tests HaversineUtilTest
./gradlew test --tests AlarmServiceTest
./gradlew test --tests GeofenceServiceTest
```

### Specific Test Method
```bash
./gradlew test --tests HaversineUtilTest::testSamePoint
./gradlew test --tests AlarmServiceTest::testTriggerOnceAlarm
```

### With Coverage Report
```bash
./gradlew test jacocoTestReport
# Report available at: build/reports/jacoco/test/html/index.html
```

### Watch Mode (continuous testing)
```bash
./gradlew test --continuous
```

## Test Frameworks

### JUnit 5
Primary testing framework with modern Jupiter API:
- `@Test` - marks test methods
- `@DisplayName` - human-readable test names
- `@BeforeEach` / `@AfterEach` - setup/teardown
- Nested test classes support
- Parameterized tests support

### MockK
Kotlin-native mocking framework:
```kotlin
val repository = mockk<UserRepository>()
every { repository.findById(any()) } returns Optional.of(user)
verify { repository.save(any()) }
```

### Testcontainers
Integration testing with real containers:
- PostgreSQL (for repository tests)
- Redis (for cache tests)
- RabbitMQ (for event tests)

## Writing Tests - Best Practices

### 1. Test Structure (AAA Pattern)

```kotlin
@Test
@DisplayName("descriptive test name")
fun testFeatureBehavior() {
    // Arrange - setup test data and mocks
    val user = User(email = "test@example.com", passwordHash = "hash")
    every { userRepository.findByEmail(email) } returns user

    // Act - execute the feature
    val result = authService.login(LoginRequest("test@example.com", "password"))

    // Assert - verify expected outcome
    assertNotNull(result)
    assertEquals("test@example.com", result.user.email)
}
```

### 2. Meaningful Test Names

Good:
```kotlin
fun testLoginFailsWithInvalidPassword()
fun testGeofenceTransitionPublishesEventToRabbitMQ()
fun testAlarmSnoozeDurationDefaultsTo9Minutes()
```

Bad:
```kotlin
fun test1()
fun testMethod()
fun testAlarm()
```

### 3. Single Responsibility

Each test verifies ONE behavior:

```kotlin
// Good - one assertion focus
@Test
fun testAlarmDeactivatedAfterSingleTrigger() {
    alarmService.triggerAlarm(onceAlarm)
    assertTrue(alarmRepository.findById(alarm.id).isActive == false)
}

// Bad - multiple behaviors
@Test
fun testAlarmBehavior() {
    alarmService.triggerAlarm(alarm)
    assertTrue(notification.sent)
    assertTrue(!alarm.isActive)
    // Now we don't know which assertion failed
}
```

### 4. Mock External Dependencies

```kotlin
@Test
fun testCreateAlarm() {
    // Mock external calls
    every { geofenceRepository.findById(zoneId) } returns zone
    every { rabbitTemplate.convertAndSend(any(), any(), any()) } just Runs
    
    // Don't mock domain logic
    val alarm = Alarm(user, label = "Wake up", triggerType = TIME)
    
    val result = alarmService.createAlarm(alarm)
    
    // Verify behavior
    assertNotNull(result.id)
    verify { geofenceRepository.findById(zoneId) }
}
```

### 5. Use DisplayName for Documentation

```kotlin
@DisplayName("AlarmService - Alarm Triggering")
class AlarmServiceTest {

    @DisplayName("triggerAlarm: ONCE alarm is deactivated")
    @Test
    fun testOnceAlarmDeactivation() { ... }

    @DisplayName("triggerAlarm: DAILY alarm remains active")
    @Test
    fun testDailyAlarmRemains Active() { ... }
}
```

## Test Data Builders

For complex test objects, use builders:

```kotlin
// Instead of repetitive setup
fun createTestAlarm(
    label: String = "Wake up",
    triggerType: AlarmTriggerType = AlarmTriggerType.TIME,
    isActive: Boolean = true
): Alarm = Alarm(
    user = createTestUser(),
    label = label,
    triggerType = triggerType,
    isActive = isActive
)

fun createTestUser(
    email: String = "test@example.com",
    displayName: String = "Test User"
): User = User(
    email = email,
    passwordHash = "hashed",
    displayName = displayName
)

// Use in tests
@Test
fun testCustomAlarm() {
    val alarm = createTestAlarm(label = "Bedtime", isActive = false)
    // ...
}
```

## Integration Testing (Future)

For testing full flows with real dependencies:

```kotlin
@SpringBootTest
@Testcontainers
class AlarmIntegrationTest {

    @Container
    static final PostgreSQLContainer<?> postgres = 
        new PostgreSQLContainer<>("postgres:15-alpine");

    @Test
    @DisplayName("end-to-end: create alarm and receive notification")
    fun testEndToEndAlarmFlow() {
        // Uses real database, not mocks
        val user = userRepository.save(testUser)
        val alarm = alarmService.createAlarm(testAlarm)
        
        // Trigger event
        geofenceService.evaluateLocation(user.id, lat, lng)
        
        // Verify database state changed
        val persisted = alarmRepository.findById(alarm.id)
        assertEquals(false, persisted.isActive)
    }
}
```

## Test Patterns

### Parameterized Tests

```kotlin
@ParameterizedTest
@ValueSource(strings = ["test@example.com", "user@domain.com"])
@DisplayName("login: works with multiple emails")
fun testLoginWithMultipleEmails(email: String) {
    val user = createTestUser(email = email)
    every { userRepository.findByEmail(email) } returns user
    
    val result = authService.login(LoginRequest(email, "password"))
    
    assertNotNull(result)
}
```

### Nested Test Classes

```kotlin
@DisplayName("AlarmService")
class AlarmServiceTest {

    @DisplayName("creation")
    @Nested
    inner class CreationTests {
        @Test
        fun testCreateTimeAlarm() { ... }
        
        @Test
        fun testCreateGeoAlarm() { ... }
    }

    @DisplayName("triggering")
    @Nested
    inner class TriggeringTests {
        @Test
        fun testTriggerOnceAlarm() { ... }
        
        @Test
        fun testTriggerDailyAlarm() { ... }
    }
}
```

## Debugging Tests

### Run with Debug Output
```bash
./gradlew test --debug
```

### Add Logging in Tests
```kotlin
@Test
fun testWithLogging() {
    println("Before action: alarm state = ${alarm.isActive}")
    alarmService.triggerAlarm(alarm)
    println("After action: alarm state = ${alarm.isActive}")
}
```

### Conditional Test Skipping
```kotlin
@Test
@DisabledIf("testingAgainstProduction")
fun testOnlyInDevelopment() {
    // Won't run in production
}

fun testingAgainstProduction() = System.getenv("ENV") == "prod"
```

## Test Coverage

### Current Coverage
```
util/HaversineUtil:        5/5 tests (100%)
service/AuthService:       5/5 tests (100%)
service/GeofenceService:   7/7 tests (100%)
service/AlarmService:      10/10 tests (100%)
service/Notification:      3/3 tests (100%)
api/AlarmController:       7/7 tests (100%)

Total: 37 tests covering core business logic
```

### Coverage Goals

- **Util Layer**: 100% (all utility functions tested)
- **Service Layer**: 90%+ (all public methods tested)
- **API Layer**: 80%+ (main flows tested, edge cases optional)
- **Config**: 50%+ (complex configs tested, beans validated)

### Check Coverage Report
```bash
./gradlew jacocoTestReport
open build/reports/jacoco/test/html/index.html
```

## Common Test Issues

### 1. Mock Not Working
```kotlin
// Wrong - using real instance
val service = AuthService(userRepository)

// Right - mock is injected
val authService = AuthService(mockk<UserRepository>())
```

### 2. Verifying Never Called
```kotlin
verify(exactly = 0) { userRepository.save(any()) }  // Good
verify { userRepository.save(any()).wasNotCalled }  // Bad MockK syntax
```

### 3. Testing Exceptions
```kotlin
// Good - specific exception
assertThrows<UnauthorisedException> {
    authService.login(LoginRequest("bad@test.com", "wrong"))
}

// Better - check exception message
val exception = assertThrows<UnauthorisedException> {
    authService.login(LoginRequest("bad@test.com", "wrong"))
}
assertEquals("Invalid email or password", exception.message)
```

## Performance Testing (Future)

```kotlin
@Test
@DisplayName("performance: geofence evaluation < 100ms for 10 zones")
fun testGeofencePerformance() {
    val startTime = System.currentTimeMillis()
    
    geofenceService.evaluateLocation(userId, lat, lng)
    
    val duration = System.currentTimeMillis() - startTime
    assertTrue(duration < 100, "Evaluation took ${duration}ms")
}
```

## Continuous Integration

Tests run automatically on:
- Every commit
- Pull requests
- Scheduled nightly builds

Build fails if:
- Any test fails
- Coverage drops below threshold
- Code style violations

---

**Last Updated**: January 2024
