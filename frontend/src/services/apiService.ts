import axios, { AxiosInstance, AxiosError } from 'axios';
import * as SecureStore from 'expo-secure-store';
import { useAuthStore } from '../store/authStore';
import * as Types from '../types';

const API_BASE_URL = process.env.EXPO_PUBLIC_API_URL || 'http://localhost:8080/api';

class ApiClient {
  private client: AxiosInstance;
  private isRefreshing = false;
  private failedQueue: Array<{
    onSuccess: (token: string) => void;
    onFail: (error: Error) => void;
  }> = [];

  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    this.client.interceptors.request.use(
      async (config) => {
        const token = await SecureStore.getItemAsync('accessToken');
        if (token) {
          config.headers.Authorization = `Bearer ${token}`;
        }
        return config;
      },
      (error) => Promise.reject(error)
    );

    this.client.interceptors.response.use(
      (response) => response,
      async (error) => {
        const originalRequest = error.config;

        if (error.response?.status === 401 && !originalRequest._retry) {
          if (this.isRefreshing) {
            return new Promise((resolve, reject) => {
              this.failedQueue.push({
                onSuccess: (token: string) => {
                  originalRequest.headers.Authorization = `Bearer ${token}`;
                  resolve(this.client(originalRequest));
                },
                onFail: (err: Error) => reject(err),
              });
            });
          }

          this.isRefreshing = true;
          originalRequest._retry = true;

          try {
            const refreshToken = await SecureStore.getItemAsync('refreshToken');
            if (!refreshToken) {
              throw new Error('No refresh token available');
            }

            const response = await this.client.post('/auth/refresh', {
              refreshToken,
            });

            const { accessToken, refreshToken: newRefreshToken } = response.data;

            await SecureStore.setItemAsync('accessToken', accessToken);
            await SecureStore.setItemAsync('refreshToken', newRefreshToken);

            this.client.defaults.headers.Authorization = `Bearer ${accessToken}`;
            originalRequest.headers.Authorization = `Bearer ${accessToken}`;

            this.failedQueue.forEach((item) => item.onSuccess(accessToken));
            this.failedQueue = [];

            return this.client(originalRequest);
          } catch (err) {
            this.failedQueue.forEach((item) => item.onFail(err as Error));
            this.failedQueue = [];

            // Clear auth and redirect to login
            useAuthStore.setState({ isAuthenticated: false });
            return Promise.reject(err);
          } finally {
            this.isRefreshing = false;
          }
        }

        return Promise.reject(error);
      }
    );
  }

  // Authentication endpoints
  async register(email: string, password: string): Promise<Types.AuthResponse> {
    const response = await this.client.post('/auth/register', { email, password });
    return response.data;
  }

  async login(email: string, password: string): Promise<Types.AuthResponse> {
    const response = await this.client.post('/auth/login', { email, password });
    return response.data;
  }

  async refreshToken(refreshToken: string): Promise<Types.AuthResponse> {
    const response = await this.client.post('/auth/refresh', { refreshToken });
    return response.data;
  }

  async updateFcmToken(fcmToken: string): Promise<void> {
    await this.client.post('/auth/fcm-token', { fcmToken });
  }

  async logout(): Promise<void> {
    await this.client.post('/auth/logout');
  }

  // User endpoints
  async getUserProfile(): Promise<Types.User> {
    const response = await this.client.get('/users/me');
    return response.data;
  }

  async updateUserProfile(name: string): Promise<Types.User> {
    const response = await this.client.put('/users/me', { name });
    return response.data;
  }

  async updateUserPreferences(preferences: Partial<Types.UserPreferences>): Promise<Types.User> {
    const response = await this.client.patch('/users/me/preferences', preferences);
    return response.data;
  }

  async deleteAccount(): Promise<void> {
    await this.client.delete('/users/me');
  }

  // Alarm endpoints
  async getAlarms(): Promise<Types.Alarm[]> {
    const response = await this.client.get('/alarms');
    return response.data;
  }

  async getAlarmById(id: string): Promise<Types.Alarm> {
    const response = await this.client.get(`/alarms/${id}`);
    return response.data;
  }

  async createAlarm(alarm: Types.AlarmCreateRequest): Promise<Types.Alarm> {
    const response = await this.client.post('/alarms', alarm);
    return response.data;
  }

  async updateAlarm(id: string, alarm: Partial<Types.AlarmCreateRequest>): Promise<Types.Alarm> {
    const response = await this.client.put(`/alarms/${id}`, alarm);
    return response.data;
  }

  async deleteAlarm(id: string): Promise<void> {
    await this.client.delete(`/alarms/${id}`);
  }

  async toggleAlarm(id: string, isActive: boolean): Promise<Types.Alarm> {
    const response = await this.client.patch(`/alarms/${id}`, { isActive });
    return response.data;
  }

  // Geofence endpoints
  async getGeofences(): Promise<Types.GeofenceZone[]> {
    const response = await this.client.get('/geofences');
    return response.data;
  }

  async getGeofenceById(id: string): Promise<Types.GeofenceZone> {
    const response = await this.client.get(`/geofences/${id}`);
    return response.data;
  }

  async createGeofence(zone: Types.GeofenceZoneCreateRequest): Promise<Types.GeofenceZone> {
    const response = await this.client.post('/geofences', zone);
    return response.data;
  }

  async updateGeofence(id: string, zone: Partial<Types.GeofenceZoneCreateRequest>): Promise<Types.GeofenceZone> {
    const response = await this.client.put(`/geofences/${id}`, zone);
    return response.data;
  }

  async deleteGeofence(id: string): Promise<void> {
    await this.client.delete(`/geofences/${id}`);
  }

  // Location endpoints
  async updateLocation(location: Types.LocationUpdateRequest): Promise<Types.LocationEvent> {
    const response = await this.client.post('/location/update', location);
    return response.data;
  }

  async getCurrentLocation(): Promise<Types.LocationEvent> {
    const response = await this.client.get('/location/current');
    return response.data;
  }

  async getLocationHistory(limit: number = 100): Promise<Types.LocationEvent[]> {
    const response = await this.client.get(`/location/history?limit=${limit}`);
    return response.data;
  }

  getClient(): AxiosInstance {
    return this.client;
  }
}

export default new ApiClient();
