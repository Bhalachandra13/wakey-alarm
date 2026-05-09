import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import Constants from 'expo-constants';
import { Platform } from 'react-native';
import apiService from './apiService';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

export async function initializeNotifications(): Promise<string | null> {
  let token: string | null = null;

  try {
    if (Device.isDevice) {
      const { status: existingStatus } = await Notifications.getPermissionsAsync();
      let finalStatus = existingStatus;

      if (existingStatus !== 'granted') {
        const { status } = await Notifications.requestPermissionsAsync();
        finalStatus = status;
      }

      if (finalStatus !== 'granted') {
        console.warn('Failed to get notification permissions');
        return null;
      }

      if (Platform.OS === 'android') {
        await Notifications.setNotificationChannelAsync('default', {
          name: 'default',
          importance: Notifications.AndroidImportance.MAX,
          vibrationPattern: [0, 250, 250, 250],
          lightColor: '#FF231F7C',
        });
      }

      const expoToken = await Notifications.getExpoPushTokenAsync({
        projectId: Constants.expoConfig?.extra?.eas?.projectId,
      });

      token = expoToken.data;

      // Send token to backend
      if (token) {
        try {
          await apiService.updateFcmToken(token);
        } catch (error) {
          console.error('Failed to send FCM token to backend:', error);
        }
      }
    } else {
      console.warn('Push notifications only work on physical devices');
    }
  } catch (error) {
    console.error('Error initializing notifications:', error);
  }

  return token;
}

export async function schedulePushNotification(
  title: string,
  body: string,
  delay: number = 5
): Promise<void> {
  try {
    await Notifications.scheduleNotificationAsync({
      content: {
        title,
        body,
        sound: 'default',
        badge: 1,
      },
      trigger: { seconds: delay },
    });
  } catch (error) {
    console.error('Error scheduling notification:', error);
  }
}

export function addNotificationListener(
  callback: (notification: Notifications.Notification) => void
): Notifications.EventSubscription {
  return Notifications.addNotificationReceivedListener((notification) => {
    callback(notification);
  });
}

export function addNotificationResponseListener(
  callback: (response: Notifications.NotificationResponse) => void
): Notifications.EventSubscription {
  return Notifications.addNotificationResponseReceivedListener((response) => {
    callback(response);
  });
}

export async function dismissAllNotifications(): Promise<void> {
  try {
    await Notifications.dismissAllNotificationsAsync();
  } catch (error) {
    console.error('Error dismissing notifications:', error);
  }
}

export async function getLastNotificationResponseAsync(): Promise<Notifications.NotificationResponse | null> {
  try {
    return await Notifications.getLastNotificationResponseAsync();
  } catch (error) {
    console.error('Error getting last notification response:', error);
    return null;
  }
}
