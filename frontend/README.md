# Wakey - React Native Frontend

A cross-platform React Native application for managing smart geofence-based alarms built with Expo.

## Features

- **User Authentication**: Secure JWT-based login and registration
- **Clock Features**: Current time display with 24-hour format support
- **Alarms**: Create, manage, and trigger time-based and geofence-based alarms
- **Geofencing**: Define custom geofence zones and track entries/exits
- **Real-time Updates**: WebSocket integration for live alarm and geofence events
- **Location Tracking**: Background location updates with geofence detection
- **Push Notifications**: Expo and FCM push notification support
- **User Profiles**: Manage user preferences and account settings

## Tech Stack

- **React Native 0.73** - Mobile framework
- **Expo 50** - Development and deployment platform
- **TypeScript** - Type-safe development
- **Zustand** - State management
- **Axios** - HTTP client with interceptors
- **React Navigation** - Navigation and routing
- **React Native Maps** - Geofence visualization
- **Jest & React Testing Library** - Testing framework

## Project Structure

```
frontend/
├── src/
│   ├── screens/          # Screen components (Login, Alarm, Geofence, etc.)
│   ├── components/       # Reusable UI components
│   ├── services/         # API client, location, notifications
│   ├── store/           # Zustand stores (auth, alarm, geofence)
│   ├── types/           # TypeScript type definitions
│   └── utils/           # Utility functions
├── assets/              # Images, icons, splash screen
├── App.tsx             # Main app component with navigation
├── package.json        # Dependencies and scripts
├── tsconfig.json       # TypeScript configuration
└── jest.config.js      # Testing configuration
```

## Installation

### Prerequisites

- Node.js 18+ and npm/yarn
- Expo CLI: `npm install -g expo-cli`
- iOS simulator (macOS) or Android emulator
- Physical device (optional)

### Setup

1. **Install dependencies**:
```bash
cd frontend
npm install
```

2. **Configure API endpoint** (in `package.json`):
```json
"extra": {
  "API_URL": "http://localhost:8080/api"
}
```

Or create `.env.local`:
```
EXPO_PUBLIC_API_URL=http://localhost:8080/api
```

3. **Start development server**:
```bash
npm start
```

4. **Run on specific platform**:
```bash
npm run android    # Android emulator
npm run ios        # iOS simulator
npm run web        # Web browser
```

## Development

### Code Quality

```bash
# Lint code
npm run lint

# Format code
npm run format

# Run tests
npm run test

# Watch tests
npm run test:watch

# Coverage report
npm run test:coverage
```

### Adding New Screens

1. Create a new screen file in `src/screens/`:
```typescript
import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

export default function MyScreen() {
  return (
    <View style={styles.container}>
      <Text>My Screen</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', alignItems: 'center' }
});
```

2. Register in `App.tsx`:
```typescript
<Tab.Screen
  name="MyScreen"
  component={MyScreen}
  options={{ title: 'My Screen' }}
/>
```

### API Integration

Use `apiService` to call backend endpoints:

```typescript
import apiService from '../services/apiService';

const alarms = await apiService.getAlarms();
const newAlarm = await apiService.createAlarm({
  name: 'Morning Alarm',
  triggerType: 'TIME',
  scheduledAt: new Date().toISOString(),
  repeatRule: 'DAILY'
});
```

### State Management with Zustand

Use auth store:
```typescript
import { useAuthStore } from '../store/authStore';

const { user, login, logout, isAuthenticated } = useAuthStore();
```

### Location Tracking

```typescript
import { startBackgroundLocationTracking, stopBackgroundLocationTracking } from '../services/locationService';

// Start tracking
await startBackgroundLocationTracking();

// Stop tracking
await stopBackgroundLocationTracking();
```

## Testing

### Unit Tests

```bash
npm run test
```

### Test Structure

```typescript
describe('LoginScreen', () => {
  it('should display login form', () => {
    const { getByPlaceholderText } = render(<LoginScreen />);
    expect(getByPlaceholderText('Email')).toBeTruthy();
  });
});
```

### Writing Tests

1. Create test file in same directory as component: `Component.test.tsx`
2. Use React Testing Library for component tests
3. Mock API calls and external services
4. Aim for 80%+ code coverage

## Building for Production

### Android Build

```bash
npm run build
# Select "Android" when prompted
# Builds APK and App Bundle
```

### iOS Build

```bash
npm run build
# Select "iOS" when prompted
# Builds IPA for TestFlight/App Store
```

### Web Build

```bash
npm run build
# Builds web-optimized app
# Deploy to web hosting
```

## Configuration

### Permissions

Add to `package.json` expo config:

```json
"plugins": [
  ["expo-location", {
    "locationAlwaysAndWhenInUsePermission": "Allow Wakey to access your location"
  }],
  ["expo-notifications", {
    "icon": "./assets/notification-icon.png"
  }]
]
```

### Environment Variables

```env
EXPO_PUBLIC_API_URL=http://localhost:8080/api
```

### App Configuration

Edit `package.json` expo section:
- `name` - App display name
- `slug` - App slug for Expo
- `icon` - App icon path
- `splash` - Splash screen config
- `ios.bundleIdentifier` - iOS bundle ID
- `android.package` - Android package name

## Debugging

### Logs

View logs in Expo CLI:
```
j - Open debugger
r - Reload app
c - Clear console
```

### React DevTools

```bash
npm install react-devtools
npx react-devtools
```

Then in app, press `Ctrl+D` (Android) or `Cmd+D` (iOS).

### Network Monitoring

Use Flipper or Reactotron for network inspection.

## Common Issues

### Build Failures

1. **Clear cache**:
```bash
npm start -- --clear
```

2. **Reinstall dependencies**:
```bash
rm -rf node_modules
npm install
```

### Location Permissions

- Android: Grant permission manually in Settings
- iOS: Ensure Info.plist has location permission keys
- Expo: Use `expo-location` plugin

### WebSocket Connection

- Ensure backend WebSocket is accessible
- Check firewall rules
- Verify JWT token is valid

## Performance Optimization

- Use `React.memo()` for component memoization
- Implement FlatList virtualization for lists
- Use `useMemo()` and `useCallback()` hooks
- Profile with React Native Performance Monitor

## Security

- Store tokens in Secure Store (not AsyncStorage)
- Validate JWT tokens before each request
- Implement certificate pinning for HTTPS
- Never log sensitive data
- Sanitize user input

## Contributing

1. Create feature branch: `git checkout -b feature/name`
2. Write tests for new code
3. Format code: `npm run format`
4. Lint code: `npm run lint`
5. Commit with clear message
6. Push and create pull request

## API Documentation

See [Backend API Documentation](../backend/API_DOCUMENTATION.md)

## License

Proprietary - Wakey Alarm

## Support

For issues and questions, contact the development team.

---

**Last Updated**: January 2024
