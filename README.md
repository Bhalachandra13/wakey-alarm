# Wakey Alarm - Smart Geofence Alarm System

A full-stack mobile application combining time-based and location-based alarms with real-time notifications. Built with Kotlin/Spring Boot backend and React Native frontend.

## Project Overview

**Wakey** is an intelligent alarm system that allows users to:

- Set time-based alarms (one-time, daily, or custom schedules)
- Create geofence zones and trigger alarms on entry/exit
- Combine time and location for smart alarms
- Track location in real-time with background updates
- Receive instant push notifications
- Manage clock, timer, and stopwatch functionality
- Access their account and preferences from any device

## Architecture

```
┌─────────────────────────────────────────────┐
│         React Native Frontend (Expo)        │
│    (iOS, Android, Web via React Native Web) │
└──────────────────┬──────────────────────────┘
                   │ HTTP + WebSocket
                   │
┌──────────────────▼──────────────────────────┐
│  Kotlin Spring Boot REST API (Port 8080)    │
├──────────────────────────────────────────────┤
│ Controllers → Services → Repositories        │
│ JWT Auth | WebSocket | Event Streaming      │
└──────────────┬──────────────────────────────┘
               │
       ┌───────┼────────┬──────────┬──────────┐
       │       │        │          │          │
   ┌───▼─┐ ┌──▼──┐ ┌───▼──┐ ┌────▼──┐ ┌────▼──┐
   │ PG  │ │Redis│ │RabbitMQ│ │Quartz│ │Firebase│
   │+GIS │ │  7  │ │ 3.12 │ │      │ │  FCM   │
   └─────┘ └─────┘ └───────┘ └──────┘ └────────┘
```

## Technology Stack

### Backend (Kotlin)

- **Framework**: Spring Boot 3.2
- **Language**: Kotlin 1.9
- **Database**: PostgreSQL 15 + PostGIS (geospatial queries)
- **Caching**: Redis 7 (geofence state, session management)
- **Message Queue**: RabbitMQ 3.12 (event streaming)
- **Scheduler**: Quartz (time-based alarm scheduling)
- **Authentication**: JWT (15min access + 30day refresh tokens)
- **Real-time**: WebSocket over STOMP/SockJS
- **Push Notifications**: Firebase Admin SDK
- **Testing**: JUnit 5, MockK (37 test cases)

### Frontend (React Native)

- **Framework**: Expo 50, React Native 0.73
- **Language**: TypeScript
- **State Management**: Zustand
- **Navigation**: React Navigation (bottom tabs + stack)
- **HTTP Client**: Axios with JWT interceptors
- **Location**: expo-location with background tracking
- **Notifications**: expo-notifications + Firebase FCM
- **Maps**: react-native-maps (geofence visualization)
- **Testing**: Jest + React Testing Library
- **Code Quality**: ESLint + Prettier

## Project Structure

```
wakey-alarm/
├── backend/                           # Kotlin Spring Boot
│   ├── src/main/kotlin/com/wakey/
│   │   ├── api/                      # REST Controllers (5 endpoints)
│   │   ├── config/                   # Spring configs (7 files)
│   │   ├── dto/                      # Request/Response DTOs
│   │   ├── exception/                # Custom exceptions + handler
│   │   ├── model/                    # JPA entities (4 models)
│   │   ├── repository/               # Spring Data repos (4 repos)
│   │   ├── service/                  # Business logic (6 services)
│   │   ├── scheduler/                # Quartz scheduler + job
│   │   └── util/                     # Utilities (Haversine, JWT)
│   ├── src/main/resources/
│   │   ├── db/migration/             # Flyway migrations (V1-V4)
│   │   └── application.yml           # Spring Boot config
│   ├── src/test/kotlin/              # Unit tests (37 test cases)
│   ├── docker-compose.yml            # Local dev infrastructure
│   ├── Dockerfile                    # Production build
│   ├── build.gradle.kts              # Gradle build config
│   └── [README|API_DOCUMENTATION|DEVELOPMENT|TESTING|DEPLOYMENT].md
│
├── frontend/                          # React Native Expo
│   ├── src/
│   │   ├── screens/                  # 7 screen components
│   │   ├── components/               # Reusable UI components
│   │   ├── services/                 # API, location, notifications
│   │   ├── store/                    # Zustand state (auth, etc.)
│   │   ├── types/                    # TypeScript definitions
│   │   └── utils/                    # Helper functions
│   ├── App.tsx                       # Main app with navigation
│   ├── index.js                      # Entry point
│   ├── package.json                  # NPM dependencies
│   ├── tsconfig.json                 # TypeScript config
│   ├── jest.config.js                # Testing config
│   ├── .eslintrc.json                # Linting rules
│   ├── .prettierrc.json              # Code formatting
│   └── README.md                     # Frontend documentation
│
└── wakey-requirements.md             # Original requirements

```

## Quick Start

### Prerequisites

- **Backend**: Java 17+, Gradle 8+, Docker & Docker Compose
- **Frontend**: Node.js 18+, Expo CLI, iOS/Android emulator or device

### Backend Setup

```bash
cd backend

# Start infrastructure (PostgreSQL, Redis, RabbitMQ)
docker-compose up -d

# Run tests
./gradlew test

# Start application
./gradlew bootRun

# Application runs on http://localhost:8080
```

### Frontend Setup

```bash
cd frontend

# Install dependencies
npm install

# Start Expo development server
npm start

# Run on emulator
npm run android    # or
npm run ios

# Run tests
npm run test
```

## Key Features

### 1. User Authentication

- Secure registration with password validation
- JWT-based login (email + password)
- Token refresh mechanism (15min access + 30day refresh)
- FCM token management for push notifications
- Account deletion

### 2. Alarm Management

- **Time-based Alarms**:
  - One-time (specific datetime)
  - Daily (same time every day)
  - Weekdays (Mon-Fri)
  - Custom (future: cron-based)

- **Geofence-based Alarms**:
  - Enter geofence (GEO_ENTER)
  - Exit geofence (GEO_EXIT)
  - Combined time + location

- **Alarm Lifecycle**:
  - Create / Read / Update / Delete
  - Toggle active/inactive
  - Automatic deactivation on trigger (ONCE)
  - Quartz-based scheduling

### 3. Geofencing

- Create custom geofence zones with name, location, radius
- Real-time geofence evaluation using Haversine formula
- Background location tracking with 1-minute updates
- Redis-cached zone states for performance
- RabbitMQ event streaming on zone transitions

### 4. Real-time Updates

- WebSocket over STOMP/SockJS at `/ws`
- Topic-based subscriptions: `/topic/alarms/{userId}`, `/topic/geo/{userId}`
- Instant alarm trigger notifications
- Geofence transition events

### 5. Clock Features (UI Framework Ready)

- Current time display with 24-hour format
- Timer with start/pause/reset
- Stopwatch with lap recording
- Timezone support (future)

### 6. Push Notifications

- Expo notification support (development)
- Firebase Cloud Messaging (production)
- Rich notifications with custom data
- Notification scheduling

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/auth/register` | POST | Register new user |
| `/api/auth/login` | POST | User login |
| `/api/auth/refresh` | POST | Refresh JWT token |
| `/api/auth/fcm-token` | POST | Update FCM token |
| `/api/auth/logout` | POST | User logout |
| `/api/users/me` | GET | Get user profile |
| `/api/users/me` | PUT | Update profile |
| `/api/users/me/preferences` | PATCH | Update preferences |
| `/api/users/me` | DELETE | Delete account |
| `/api/alarms` | GET | List alarms |
| `/api/alarms/{id}` | GET | Get alarm |
| `/api/alarms` | POST | Create alarm |
| `/api/alarms/{id}` | PUT | Update alarm |
| `/api/alarms/{id}` | DELETE | Delete alarm |
| `/api/alarms/{id}` | PATCH | Toggle alarm |
| `/api/geofences` | GET | List geofences |
| `/api/geofences/{id}` | GET | Get geofence |
| `/api/geofences` | POST | Create geofence |
| `/api/geofences/{id}` | PUT | Update geofence |
| `/api/geofences/{id}` | DELETE | Delete geofence |
| `/api/location/update` | POST | Update location |
| `/api/location/current` | GET | Get current location |
| `/api/location/history` | GET | Get location history |

## WebSocket Events

**Subscribe to**: `/topic/alarms/{userId}`
```json
{
  "type": "TRIGGER",
  "alarmId": "uuid",
  "timestamp": "2024-01-15T10:30:00Z",
  "triggerType": "TIME|GEO_ENTER|GEO_EXIT"
}
```

**Subscribe to**: `/topic/geo/{userId}`
```json
{
  "type": "ENTER|EXIT",
  "zoneId": "uuid",
  "latitude": 37.7749,
  "longitude": -122.4194,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## Database Schema

### Users
- id (UUID)
- email (unique)
- password_hash
- fcm_token
- preferences (JSON)
- created_at, updated_at

### Alarms
- id (UUID)
- user_id (FK)
- name, description
- trigger_type (enum: TIME, GEO_ENTER, GEO_EXIT, COMBINED)
- repeat_rule (enum: ONCE, DAILY, WEEKDAYS, CUSTOM)
- scheduled_at (timestamp)
- geofence_zone_id (FK, nullable)
- is_active (boolean)
- quartz_job_key (string, for scheduler)
- created_at, updated_at

### Geofence Zones
- id (UUID)
- user_id (FK)
- name, description
- location (PostGIS GEOGRAPHY POINT)
- radius (meters, integer)
- is_active (boolean)
- created_at, updated_at

### Location Events
- id (UUID)
- user_id (FK)
- location (PostGIS GEOGRAPHY POINT)
- accuracy (meters)
- timestamp

## Testing

### Backend

```bash
cd backend
./gradlew test                # Run all tests
./gradlew test --tests HaversineUtilTest  # Run specific test
```

**Test Coverage**: 37 unit tests covering:
- Haversine distance calculations
- JWT authentication flows
- Geofence zone detection
- Alarm scheduling and triggering
- Notification delivery
- REST API endpoints

### Frontend

```bash
cd frontend
npm run test                  # Run tests
npm run test:watch          # Watch mode
npm run test:coverage       # Coverage report
```

## Deployment

### Docker (Single Node)

```bash
cd backend

# Build image
docker build -t wakey-backend:latest .

# Deploy with docker-compose
docker-compose -f docker-compose.prod.yml up -d
```

### Kubernetes (High Availability)

```bash
kubectl apply -f kubernetes/deployment.yaml
kubectl scale deployment wakey-backend --replicas=5
kubectl autoscale deployment wakey-backend --min=2 --max=10 --cpu-percent=70
```

### Environment Variables

```env
SPRING_PROFILES_ACTIVE=prod
POSTGRES_URL=jdbc:postgresql://postgres:5432/wakey
POSTGRES_USER=wakey_user
POSTGRES_PASSWORD=<strong_password>
REDIS_HOST=redis
REDIS_PASSWORD=<strong_password>
RABBITMQ_HOST=rabbitmq
RABBITMQ_USER=wakey_user
RABBITMQ_PASSWORD=<strong_password>
JWT_SECRET=<cryptographically_secure_key>
FIREBASE_CONFIG_JSON=<base64_encoded_service_account>
```

See [Backend Deployment Guide](backend/DEPLOYMENT.md) for detailed instructions.

## Documentation

### Backend
- [API Documentation](backend/API_DOCUMENTATION.md) - Complete REST API reference
- [README](backend/README.md) - Setup and architecture
- [Development Guide](backend/DEVELOPMENT.md) - Development workflow and TDD
- [Testing Guide](backend/TESTING.md) - Test organization and patterns
- [Deployment Guide](backend/DEPLOYMENT.md) - Production deployment

### Frontend
- [Frontend README](frontend/README.md) - Setup, development, and building

## Development Workflow

### Backend Development

1. **Read requirements**: Check `wakey-requirements.md`
2. **Write tests first** (TDD): `src/test/kotlin/`
3. **Implement**: Follow layered architecture
4. **Document**: Update API_DOCUMENTATION.md
5. **Commit**: Include tests in commit

### Frontend Development

1. **Create screen/component**
2. **Define types**: Add to `src/types/index.ts`
3. **Implement**: Write component logic
4. **Test**: Add Jest tests
5. **Format**: Run `npm run format`
6. **Commit**: With test files

## Performance Considerations

- **Geofence Caching**: Redis caches zone states (5min TTL)
- **Connection Pooling**: HikariCP with 20 max connections
- **Query Optimization**: Indexed by user_id, created_at
- **Background Location**: 1-minute update interval, 50m distance threshold
- **WebSocket**: Stateless, scales horizontally
- **RabbitMQ**: Topic-based routing for event distribution

## Security

- **Authentication**: JWT with secure expiration
- **Storage**: Tokens in secure enclave (expo-secure-store)
- **HTTPS**: All production endpoints use TLS
- **Database**: PostGIS validation, prepared statements
- **Input Validation**: DTO validation with Spring annotations
- **CORS**: Configured for frontend domain
- **Rate Limiting**: (Future enhancement)

## Known Limitations & Future Enhancements

### Current Limitations
- Firebase Admin SDK not yet fully integrated
- WebSocket JWT authentication interceptor not implemented
- No end-to-end integration tests (only unit tests)
- No performance/load testing
- Timer/stopwatch UI skeleton only

### Planned Enhancements
- Advanced recurring alarm patterns (cron-based)
- Smart alarm suggestions based on location history
- Alarm sound customization
- Dark mode support
- Multi-user family sharing
- Voice control
- Calendar integration
- Weather-based alarms
- Snooze with geofence override

## Contributing

1. Create feature branch: `git checkout -b feature/description`
2. Follow TDD: Write tests first
3. Code follows style guide (ESLint/Prettier)
4. Update documentation
5. Create pull request with clear description

## Troubleshooting

### Backend Won't Start
```bash
# Check if ports are in use
lsof -i :8080      # Application
lsof -i :5432      # PostgreSQL
lsof -i :6379      # Redis
lsof -i :5672      # RabbitMQ

# Clear database and restart
docker-compose down -v
docker-compose up -d
```

### Frontend Won't Connect to Backend
```bash
# Check API URL in package.json
# Ensure backend is running: curl http://localhost:8080/health
# Clear Expo cache: npm start -- --clear
```

### Location Not Updating
- Check location permissions in app settings
- Ensure background location is enabled
- Check device settings (Location Services)
- On iOS, may require Always permission

## License

Proprietary - Wakey Alarm

## Contact

For questions or support, contact the development team.

---

**Version**: 1.0.0  
**Last Updated**: January 2024  
**Status**: Active Development
