import { create } from 'zustand';
import * as SecureStore from 'expo-secure-store';
import apiService from '../services/apiService';
import * as Types from '../types';

interface AuthState {
  user: Types.User | null;
  accessToken: string | null;
  refreshToken: string | null;
  isAuthenticated: boolean;
  loading: boolean;
  error: string | null;

  // Actions
  register: (email: string, password: string) => Promise<void>;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  initializeAuth: () => Promise<void>;
  updateUserProfile: (name: string) => Promise<void>;
  updateUserPreferences: (preferences: Partial<Types.UserPreferences>) => Promise<void>;
  deleteAccount: () => Promise<void>;
  clearError: () => void;
}

export const useAuthStore = create<AuthState>((set, get) => ({
  user: null,
  accessToken: null,
  refreshToken: null,
  isAuthenticated: false,
  loading: true,
  error: null,

  register: async (email: string, password: string) => {
    set({ loading: true, error: null });
    try {
      const response = await apiService.register(email, password);
      await SecureStore.setItemAsync('accessToken', response.accessToken);
      await SecureStore.setItemAsync('refreshToken', response.refreshToken);

      set({
        user: response.user,
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        isAuthenticated: true,
        loading: false,
      });
    } catch (error: any) {
      const errorMessage = error.response?.data?.message || error.message || 'Registration failed';
      set({ error: errorMessage, loading: false });
      throw error;
    }
  },

  login: async (email: string, password: string) => {
    set({ loading: true, error: null });
    try {
      const response = await apiService.login(email, password);
      await SecureStore.setItemAsync('accessToken', response.accessToken);
      await SecureStore.setItemAsync('refreshToken', response.refreshToken);

      set({
        user: response.user,
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        isAuthenticated: true,
        loading: false,
      });
    } catch (error: any) {
      const errorMessage = error.response?.data?.message || error.message || 'Login failed';
      set({ error: errorMessage, loading: false });
      throw error;
    }
  },

  logout: async () => {
    try {
      await apiService.logout();
    } catch (error) {
      console.error('Error logging out:', error);
    } finally {
      await SecureStore.deleteItemAsync('accessToken');
      await SecureStore.deleteItemAsync('refreshToken');
      set({
        user: null,
        accessToken: null,
        refreshToken: null,
        isAuthenticated: false,
        error: null,
      });
    }
  },

  initializeAuth: async () => {
    try {
      const accessToken = await SecureStore.getItemAsync('accessToken');
      const refreshToken = await SecureStore.getItemAsync('refreshToken');

      if (accessToken && refreshToken) {
        try {
          const user = await apiService.getUserProfile();
          set({
            user,
            accessToken,
            refreshToken,
            isAuthenticated: true,
            loading: false,
          });
        } catch (error) {
          console.error('Failed to fetch user profile:', error);
          await SecureStore.deleteItemAsync('accessToken');
          await SecureStore.deleteItemAsync('refreshToken');
          set({
            isAuthenticated: false,
            loading: false,
          });
        }
      } else {
        set({ isAuthenticated: false, loading: false });
      }
    } catch (error) {
      console.error('Failed to initialize auth:', error);
      set({ isAuthenticated: false, loading: false });
    }
  },

  updateUserProfile: async (name: string) => {
    set({ loading: true, error: null });
    try {
      const user = await apiService.updateUserProfile(name);
      set({ user, loading: false });
    } catch (error: any) {
      const errorMessage = error.response?.data?.message || error.message || 'Failed to update profile';
      set({ error: errorMessage, loading: false });
      throw error;
    }
  },

  updateUserPreferences: async (preferences: Partial<Types.UserPreferences>) => {
    set({ loading: true, error: null });
    try {
      const user = await apiService.updateUserPreferences(preferences);
      set({ user, loading: false });
    } catch (error: any) {
      const errorMessage = error.response?.data?.message || error.message || 'Failed to update preferences';
      set({ error: errorMessage, loading: false });
      throw error;
    }
  },

  deleteAccount: async () => {
    set({ loading: true, error: null });
    try {
      await apiService.deleteAccount();
      await SecureStore.deleteItemAsync('accessToken');
      await SecureStore.deleteItemAsync('refreshToken');
      set({
        user: null,
        accessToken: null,
        refreshToken: null,
        isAuthenticated: false,
        loading: false,
      });
    } catch (error: any) {
      const errorMessage = error.response?.data?.message || error.message || 'Failed to delete account';
      set({ error: errorMessage, loading: false });
      throw error;
    }
  },

  clearError: () => set({ error: null }),
}));
