import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

export default function AlarmScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Alarms</Text>
      <Text style={styles.text}>Your alarms will appear here</Text>
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
    marginBottom: 10,
  },
  text: {
    fontSize: 16,
    color: '#666',
  },
});
