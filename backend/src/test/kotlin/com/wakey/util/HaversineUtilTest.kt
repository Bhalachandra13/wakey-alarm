package com.wakey.util

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.DisplayName
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@DisplayName("HaversineUtil Test Suite")
class HaversineUtilTest {

    @Test
    @DisplayName("distanceMetres: same point returns 0.0")
    fun testSamePoint() {
        val distance = HaversineUtil.distanceMetres(51.5074, -0.1278, 51.5074, -0.1278)
        assertEquals(0.0, distance, 0.1)
    }

    @Test
    @DisplayName("distanceMetres: London to Paris ~341km")
    fun testLondonToParis() {
        val londondLat = 51.5074
        val londonLng = -0.1278
        val parisLat = 48.8566
        val parisLng = 2.3522

        val distance = HaversineUtil.distanceMetres(londondLat, londonLng, parisLat, parisLng)
        val expectedDistance = 341000.0
        val tolerance = expectedDistance * 0.01 // 1% tolerance

        assertTrue(distance > expectedDistance - tolerance && distance < expectedDistance + tolerance,
            "Distance $distance should be within 1% of $expectedDistance")
    }

    @Test
    @DisplayName("distanceMetres: 10 metres apart coordinates")
    fun test10MetresApart() {
        val lat1 = 37.7749
        val lng1 = -122.4194
        val lat2 = 37.774900 + (10 / 111300.0) // Roughly 10 meters north
        val lng2 = -122.4194

        val distance = HaversineUtil.distanceMetres(lat1, lng1, lat2, lng2)
        assertTrue(distance in 9.0..11.0, "Distance $distance should be around 10 meters")
    }

    @Test
    @DisplayName("distanceMetres: antipodal points ~20,015km")
    fun testAntipodal() {
        val distance = HaversineUtil.distanceMetres(0.0, 0.0, 0.0, 180.0)
        val expectedDistance = 20015000.0
        val tolerance = expectedDistance * 0.01 // 1% tolerance

        assertTrue(distance > expectedDistance - tolerance && distance < expectedDistance + tolerance,
            "Distance $distance should be within 1% of $expectedDistance")
    }

    @Test
    @DisplayName("distanceMetres: negative latitudes and longitudes (southern hemisphere)")
    fun testSouthernHemisphere() {
        val sydneyLat = -33.8688
        val sydneyLng = 151.2093
        val melbourneLat = -37.8136
        val melbourneLng = 144.9631

        val distance = HaversineUtil.distanceMetres(sydneyLat, sydneyLng, melbourneLat, melbourneLng)
        val expectedDistance = 714000.0
        val tolerance = expectedDistance * 0.05 // 5% tolerance

        assertTrue(distance > expectedDistance - tolerance && distance < expectedDistance + tolerance,
            "Distance $distance should be within 5% of $expectedDistance meters (Sydney to Melbourne)")
    }
}
