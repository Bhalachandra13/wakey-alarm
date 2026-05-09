import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet } from 'react-native';

export default function ClockScreen() {
  const [time, setTime] = useState<string>('');

  useEffect(() => {
    const timer = setInterval(() => {
      setTime(new Date().toLocaleTimeString());
    }, 1000);

    return () => clearInterval(timer);
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Clock</Text>
      <Text style={styles.time}>{time}</Text>
      <Text style={styles.text}>Timer & Stopwatch features coming soon</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#f8f8f8',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
  },
  time: {
    fontSize: 48,
    fontWeight: 'bold',
    color: '#007AFF',
    marginBottom: 20,
  },
  text: {
    fontSize: 16,
    color: '#666',
  },
});
