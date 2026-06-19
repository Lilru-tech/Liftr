package com.lilru.liftr.externalroute

import androidx.health.connect.client.records.ExerciseSessionRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ExternalRouteSyncRegressionTest {

    @Test
    fun durationMatchesWithinRatioTolerance() {
        assertTrue(HealthConnectWorkoutMatcher.durationMatches(3600, 3650))
        assertTrue(HealthConnectWorkoutMatcher.durationMatches(600, 650))
        assertFalse(HealthConnectWorkoutMatcher.durationMatches(600, 900))
    }

    @Test
    fun durationMatchesWithinAbsoluteTolerance() {
        assertTrue(HealthConnectWorkoutMatcher.durationMatches(100, 150))
        assertFalse(HealthConnectWorkoutMatcher.durationMatches(100, 250))
    }

    @Test
    fun startTimeDeltaIsAbsolute() {
        val start = Instant.ofEpochSecond(1_700_000_000)
        val sessionStart = start.plusSeconds(120)
        assertEquals(120, HealthConnectWorkoutMatcher.startTimeDeltaSec(sessionStart, start))
    }

    @Test
    fun activityMappingCoversOutdoorCardio() {
        assertNotNull(ExternalRouteActivityMapping.healthConnectExerciseType("run"))
        assertNotNull(ExternalRouteActivityMapping.healthConnectExerciseType("bike"))
        assertNotNull(ExternalRouteActivityMapping.healthConnectExerciseType("swim_open_water"))
        assertNull(ExternalRouteActivityMapping.healthConnectExerciseType("unknown_sport"))
    }

    @Test
    fun preferredBundlesMapProviders() {
        assertTrue(ExternalRouteSourceBundles.preferredBundles("garmin").contains(ExternalRouteSourceBundles.GARMIN))
        assertTrue(ExternalRouteSourceBundles.preferredBundles("fitbit").contains(ExternalRouteSourceBundles.FITBIT))
    }

    @Test
    fun routeMetadataContainsDedupKeys() {
        val metadata = ExternalRouteDedupPolicy.routeMetadata("garmin", "abc-123")
        assertEquals("true", metadata[ExternalRouteDedupPolicy.LIFTR_HAS_CUSTOM_ROUTE_KEY])
        assertEquals("garmin", metadata[ExternalRouteDedupPolicy.LIFTR_ROUTE_PROVIDER_KEY])
        assertEquals("abc-123", metadata[ExternalRouteDedupPolicy.LIFTR_ROUTE_ID_KEY])
    }

    @Test
    fun geoJsonEncodingFromCoordinates() {
        val coords = listOf(
            LatLng(40.0, -3.0),
            LatLng(40.01, -3.01)
        )
        val encoded = RouteLineStringDecimation.encodeGeoJsonLineString(coords)
        assertNotNull(encoded)
        assertTrue(encoded!!.contains("LineString"))
        assertTrue(encoded.contains("40.0"))
    }

    @Test
    fun decimationCapsCoordinateCount() {
        val coords = List(5000) { i -> LatLng(i * 0.0001, -3.0) }
        val decimated = RouteLineStringDecimation.decimate(coords)
        assertEquals(RouteLineStringDecimation.MAX_STORED_COORDINATES, decimated.size)
    }

    @Test
    fun wearableRedirectHostMatchesManifest() {
        assertEquals("wearable-callback", WearableRedirect.HOST)
    }
}
