import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';
import apiService from './apiService';

const LOCATION_TASK_NAME = 'WAKEY_LOCATION_TASK';
const LOCATION_UPDATE_INTERVAL = 60000; // 1 minute

export async function requestLocationPermissions(): Promise<boolean> {
  try {
    const { status: foregroundStatus } = await Location.requestForegroundPermissionsAsync();
    if (foregroundStatus !== 'granted') {
      console.warn('Foreground location permission denied');
      return false;
    }

    const { status: backgroundStatus } = await Location.requestBackgroundPermissionsAsync();
    if (backgroundStatus !== 'granted') {
      console.warn('Background location permission denied');
    }

    return true;
  } catch (error) {
    console.error('Error requesting location permissions:', error);
    return false;
  }
}

export async function getCurrentLocation(): Promise<Location.LocationObject | null> {
  try {
    const location = await Location.getCurrentPositionAsync({
      accuracy: Location.Accuracy.Balanced,
    });
    return location;
  } catch (error) {
    console.error('Error getting current location:', error);
    return null;
  }
}

export async function watchLocation(
  callback: (location: Location.LocationObject) => void
): Promise<string | null> {
  try {
    const subscription = await Location.watchPositionAsync(
      {
        accuracy: Location.Accuracy.Balanced,
        timeInterval: LOCATION_UPDATE_INTERVAL,
        distanceInterval: 50, // Update if moved 50 meters
      },
      (location) => {
        callback(location);
      }
    );

    return subscription.remove.toString();
  } catch (error) {
    console.error('Error watching location:', error);
    return null;
  }
}

export async function startBackgroundLocationTracking(): Promise<boolean> {
  try {
    const hasPermission = await requestLocationPermissions();
    if (!hasPermission) {
      console.warn('Location permissions not granted');
      return false;
    }

    // Define the background task
    TaskManager.defineTask(LOCATION_TASK_NAME, async ({ data, error }) => {
      if (error) {
        console.error('Background location error:', error);
        return;
      }

      if (data) {
        const { locations } = data as { locations: Location.LocationObject[] };
        const lastLocation = locations[locations.length - 1];

        try {
          await apiService.updateLocation({
            latitude: lastLocation.coords.latitude,
            longitude: lastLocation.coords.longitude,
            accuracy: lastLocation.coords.accuracy || 0,
          });
        } catch (apiError) {
          console.error('Error updating location via API:', apiError);
        }
      }
    });

    // Start location tracking
    await Location.startLocationUpdatesAsync(LOCATION_TASK_NAME, {
      accuracy: Location.Accuracy.Balanced,
      timeInterval: LOCATION_UPDATE_INTERVAL,
      distanceInterval: 50,
      showsBackgroundLocationIndicator: true,
    });

    return true;
  } catch (error) {
    console.error('Error starting background location tracking:', error);
    return false;
  }
}

export async function stopBackgroundLocationTracking(): Promise<void> {
  try {
    const isTaskDefined = TaskManager.isTaskDefined(LOCATION_TASK_NAME);
    if (isTaskDefined) {
      await Location.stopLocationUpdatesAsync(LOCATION_TASK_NAME);
    }
  } catch (error) {
    console.error('Error stopping background location tracking:', error);
  }
}

export async function hasLocationPermission(): Promise<boolean> {
  try {
    const { status } = await Location.getForegroundPermissionsAsync();
    return status === 'granted';
  } catch (error) {
    console.error('Error checking location permission:', error);
    return false;
  }
}

export async function reverseGeocodeLocation(
  latitude: number,
  longitude: number
): Promise<Location.Address[] | null> {
  try {
    const addresses = await Location.reverseGeocodeAsync({
      latitude,
      longitude,
    });
    return addresses;
  } catch (error) {
    console.error('Error reverse geocoding:', error);
    return null;
  }
}

export async function geocodeAddress(address: string): Promise<Location.LocationGeocodedLocation[] | null> {
  try {
    const locations = await Location.geocodeAsync(address);
    return locations;
  } catch (error) {
    console.error('Error geocoding address:', error);
    return null;
  }
}

export function calculateDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371000; // Earth's radius in meters
  const φ1 = (lat1 * Math.PI) / 180;
  const φ2 = (lat2 * Math.PI) / 180;
  const Δφ = ((lat2 - lat1) * Math.PI) / 180;
  const Δλ = ((lon2 - lon1) * Math.PI) / 180;

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}
