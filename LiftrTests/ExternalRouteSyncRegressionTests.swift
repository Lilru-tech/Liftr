import CoreLocation
import Foundation
import Testing
@testable import Liftr

@Suite(.serialized)
struct ExternalRouteSyncRegressionTests {
    @Test func durationMatchesWithinRatioTolerance() {
        #expect(HealthKitWorkoutMatcher.durationMatches(workoutDuration: 3600, expectedSec: 3650))
        #expect(HealthKitWorkoutMatcher.durationMatches(workoutDuration: 600, expectedSec: 650))
        #expect(!HealthKitWorkoutMatcher.durationMatches(workoutDuration: 600, expectedSec: 900))
    }

    @Test func durationMatchesWithinAbsoluteTolerance() {
        #expect(HealthKitWorkoutMatcher.durationMatches(workoutDuration: 100, expectedSec: 150))
        #expect(!HealthKitWorkoutMatcher.durationMatches(workoutDuration: 100, expectedSec: 250))
    }

    @Test func startTimeDeltaIsAbsolute() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workoutStart = start.addingTimeInterval(120)
        #expect(HealthKitWorkoutMatcher.startTimeDelta(workoutStart, expectedStart: start) == 120)
    }

    @Test func activityMappingCoversOutdoorCardio() {
        #expect(ExternalRouteActivityMapping.hkWorkoutActivityType(for: "run") != nil)
        #expect(ExternalRouteActivityMapping.hkWorkoutActivityType(for: "bike") != nil)
        #expect(ExternalRouteActivityMapping.hkWorkoutActivityType(for: "swim_open_water") != nil)
        #expect(ExternalRouteActivityMapping.hkWorkoutActivityType(for: "unknown_sport") == nil)
    }

    @Test func preferredBundlesMapProviders() {
        #expect(ExternalRouteSourceBundles.preferredBundles(for: "garmin").contains("com.garmin.connect.mobile"))
        #expect(ExternalRouteSourceBundles.preferredBundles(for: "fitbit").contains("com.fitbit.FitbitMobile"))
    }

    @Test func routeMetadataContainsDedupKeys() {
        let metadata = ExternalRouteDedupPolicy.routeMetadata(provider: "garmin", providerActivityId: "abc-123")
        #expect(metadata[ExternalRouteDedupPolicy.liftrHasCustomRouteKey] as? Bool == true)
        #expect(metadata[ExternalRouteDedupPolicy.liftrRouteProviderKey] as? String == "garmin")
        #expect(metadata[ExternalRouteDedupPolicy.liftrRouteIdKey] as? String == "abc-123")
    }

    @Test func geoJSONEncodingFromCoordinates() {
        let coords = [
            CLLocationCoordinate2D(latitude: 40.0, longitude: -3.0),
            CLLocationCoordinate2D(latitude: 40.01, longitude: -3.01),
        ]
        let encoded = RouteLineStringDecimation.encodeGeoJSONLineString(coords)
        #expect(encoded?.contains("LineString") == true)
        #expect(encoded?.contains("40.0") == true)
    }

    @Test func decimationCapsCoordinateCount() {
        var coords: [CLLocationCoordinate2D] = []
        for i in 0..<5000 {
            coords.append(CLLocationCoordinate2D(latitude: Double(i) * 0.0001, longitude: -3.0))
        }
        let decimated = RouteLineStringDecimation.decimate(coords)
        #expect(decimated.count == RouteLineStringDecimation.maxStoredCoordinates)
    }

    @Test func externalRouteSyncDisabledByDefault() {
        let key = "externalRouteSyncEnabled"
        let defaults = UserDefaults.standard
        let hadValue = defaults.object(forKey: key) != nil
        let previous = hadValue ? defaults.bool(forKey: key) : nil
        defaults.removeObject(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        #expect(ExternalRouteSyncService.shared.isSyncEnabled == false)
    }

    @Test func wearableCallbackDetection() {
        let url = URL(string: "com.davidgomez.Liftr://wearable-callback?provider=garmin&status=connected")!
        #expect(WearableRedirect.isWearableCallback(url))
        #expect(WearableRedirect.status(from: url) == "connected")
        #expect(WearableRedirect.provider(from: url) == "garmin")
    }
}
