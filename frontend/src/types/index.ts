// API Response Types
export interface AuthResponse {
  accessToken: string;
  refreshToken: string;
  user: User;
}

export interface User {
  id: string;
  email: string;
  name: string;
  preferences: UserPreferences;
  fcmToken?: string;
  createdAt: string;
  updatedAt: string;
}

export interface UserPreferences {
  notificationsEnabled: boolean;
  soundEnabled: boolean;
  vibrationEnabled: boolean;
  theme: 'light' | 'dark';
}

// Alarm Types
export interface Alarm {
  id: string;
  userId: string;
  name: string;
  description?: string;
  triggerType: 'TIME' | 'GEO_ENTER' | 'GEO_EXIT' | 'COMBINED';
  repeatRule: 'ONCE' | 'DAILY' | 'WEEKDAYS' | 'CUSTOM';
  scheduledAt: string;
  geofenceZoneId?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface AlarmCreateRequest {
  name: string;
  description?: string;
  triggerType: 'TIME' | 'GEO_ENTER' | 'GEO_EXIT' | 'COMBINED';
  repeatRule: 'ONCE' | 'DAILY' | 'WEEKDAYS' | 'CUSTOM';
  scheduledAt: string;
  geofenceZoneId?: string;
}

// Geofence Types
export interface GeofenceZone {
  id: string;
  userId: string;
  name: string;
  latitude: number;
  longitude: number;
  radius: number; // in meters
  isActive: boolean;
  description?: string;
  createdAt: string;
  updatedAt: string;
}

export interface GeofenceZoneCreateRequest {
  name: string;
  latitude: number;
  longitude: number;
  radius: number;
  description?: string;
}

// Location Types
export interface LocationEvent {
  id: string;
  userId: string;
  latitude: number;
  longitude: number;
  accuracy: number;
  timestamp: string;
}

export interface LocationUpdateRequest {
  latitude: number;
  longitude: number;
  accuracy: number;
}

// WebSocket Event Types
export interface GeofenceTransitionEvent {
  type: 'ENTER' | 'EXIT';
  zoneId: string;
  userId: string;
  timestamp: string;
  latitude: number;
  longitude: number;
}

export interface AlarmTriggerEvent {
  type: 'TRIGGER';
  alarmId: string;
  userId: string;
  timestamp: string;
  triggerType: string;
}

// Notification Types
export interface NotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

// Timer/Stopwatch Types
export interface TimerState {
  seconds: number;
  isRunning: boolean;
  isActive: boolean;
}

export interface StopwatchState {
  elapsed: number;
  isRunning: boolean;
  laps: number[];
}

// Clock Types
export interface ClockState {
  currentTime: Date;
  timezone: string;
  is24HourFormat: boolean;
}

// API Error Response
export interface ApiError {
  code: string;
  message: string;
  details?: Record<string, unknown>;
}

// Pagination
export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}
