import React, { useEffect, useState } from 'react';
import { StatusBar } from 'expo-status-bar';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { ActivityIndicator, View } from 'react-native';

import LoginScreen from './src/screens/LoginScreen';
import RegisterScreen from './src/screens/RegisterScreen';
import HomeScreen from './src/screens/HomeScreen';
import AlarmScreen from './src/screens/AlarmScreen';
import GeofenceScreen from './src/screens/GeofenceScreen';
import ClockScreen from './src/screens/ClockScreen';
import ProfileScreen from './src/screens/ProfileScreen';
import { useAuthStore } from './src/store/authStore';
import { initializeNotifications } from './src/services/notificationService';

const Stack = createNativeStackNavigator();
const Tab = createBottomTabNavigator();

function AuthStack() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: false,
        animationEnabled: true,
      }}
    >
      <Stack.Screen name="Login" component={LoginScreen} />
      <Stack.Screen name="Register" component={RegisterScreen} />
    </Stack.Navigator>
  );
}

function AppTabs() {
  return (
    <Tab.Navigator
      screenOptions={{
        tabBarActiveTintColor: '#007AFF',
        tabBarInactiveTintColor: '#999',
        headerStyle: {
          backgroundColor: '#f8f8f8',
        },
        headerTintColor: '#000',
        headerTitleStyle: {
          fontWeight: 'bold',
        },
      }}
    >
      <Tab.Screen
        name="Home"
        component={HomeScreen}
        options={{
          title: 'Dashboard',
          tabBarLabel: 'Dashboard',
          tabBarIcon: ({ color }) => <View style={{ width: 24, height: 24, backgroundColor: color }} />,
        }}
      />
      <Tab.Screen
        name="Clock"
        component={ClockScreen}
        options={{
          title: 'Clock',
          tabBarLabel: 'Clock',
          tabBarIcon: ({ color }) => <View style={{ width: 24, height: 24, backgroundColor: color }} />,
        }}
      />
      <Tab.Screen
        name="Alarm"
        component={AlarmScreen}
        options={{
          title: 'Alarms',
          tabBarLabel: 'Alarms',
          tabBarIcon: ({ color }) => <View style={{ width: 24, height: 24, backgroundColor: color }} />,
        }}
      />
      <Tab.Screen
        name="Geofence"
        component={GeofenceScreen}
        options={{
          title: 'Geofence',
          tabBarLabel: 'Geofence',
          tabBarIcon: ({ color }) => <View style={{ width: 24, height: 24, backgroundColor: color }} />,
        }}
      />
      <Tab.Screen
        name="Profile"
        component={ProfileScreen}
        options={{
          title: 'Profile',
          tabBarLabel: 'Profile',
          tabBarIcon: ({ color }) => <View style={{ width: 24, height: 24, backgroundColor: color }} />,
        }}
      />
    </Tab.Navigator>
  );
}

export default function App() {
  const { isAuthenticated, loading, initializeAuth } = useAuthStore();
  const [appReady, setAppReady] = useState(false);

  useEffect(() => {
    const initApp = async () => {
      try {
        await initializeAuth();
        await initializeNotifications();
        setAppReady(true);
      } catch (error) {
        console.error('Failed to initialize app:', error);
        setAppReady(true);
      }
    };

    initApp();
  }, []);

  if (loading || !appReady) {
    return (
      <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
        <ActivityIndicator size="large" color="#007AFF" />
      </View>
    );
  }

  return (
    <NavigationContainer>
      <StatusBar barStyle="dark-content" />
      {isAuthenticated ? <AppTabs /> : <AuthStack />}
    </NavigationContainer>
  );
}
