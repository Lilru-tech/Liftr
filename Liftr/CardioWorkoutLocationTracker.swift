import CoreLocation
import Foundation

enum CardioGPSProfile: String, CaseIterable {
    case balanced
    case batterySaving
    var desiredAccuracy: CLLocationAccuracy {
        switch self {
        case .balanced: return kCLLocationAccuracyNearestTenMeters
        case .batterySaving: return kCLLocationAccuracyHundredMeters
        }
    }

    var distanceFilter: CLLocationDistance {
        switch self {
        case .balanced: return 5
        case .batterySaving: return 22
        }
    }
}

final class CardioWorkoutLocationTracker: NSObject, ObservableObject {
    @Published private(set) var distanceKm: Double = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isReceivingUpdates = false
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var lastHorizontalAccuracyM: CLLocationDistance = -1

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastRouteSample: CLLocation?
    private var gpsProfile: CardioGPSProfile = .balanced

    private let minRouteSampleMeters: CLLocationDistance = 12
    private let maxRoutePoints = 2_000

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        applyProfile(.balanced)
        manager.pausesLocationUpdatesAutomatically = true
        authorizationStatus = manager.authorizationStatus
    }

    func applyProfile(_ profile: CardioGPSProfile) {
        gpsProfile = profile
        manager.desiredAccuracy = profile.desiredAccuracy
        manager.distanceFilter = profile.distanceFilter
    }

    func requestWhenInUseIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func startContinuousUpdates() {
        let s = manager.authorizationStatus
        guard s == .authorizedAlways || s == .authorizedWhenInUse else { return }
        lastLocation = nil
        isReceivingUpdates = true
        manager.startUpdatingLocation()
    }

    func pauseUpdates() {
        isReceivingUpdates = false
        lastLocation = nil
        manager.stopUpdatingLocation()
    }

    func resetMeasuredDistance() {
        distanceKm = 0
        lastLocation = nil
    }

    func clearRoute() {
        routeCoordinates = []
        lastRouteSample = nil
    }

    func fullReset() {
        pauseUpdates()
        resetMeasuredDistance()
        clearRoute()
        lastHorizontalAccuracyM = -1
    }

    func routeGeoJSONString() -> String? {
        guard routeCoordinates.count >= 2 else { return nil }
        let coords = RouteLineStringDecimation.decimate(routeCoordinates)
        var parts: [String] = []
        parts.reserveCapacity(coords.count)
        for c in coords {
            parts.append("[\(c.longitude),\(c.latitude)]")
        }
        return "{\"type\":\"LineString\",\"coordinates\":[\(parts.joined(separator: ","))]}"
    }

    private func appendRouteSample(_ loc: CLLocation) {
        if let anchor = lastRouteSample {
            if loc.distance(from: anchor) < minRouteSampleMeters { return }
        }
        var next = routeCoordinates
        next.append(loc.coordinate)
        if next.count > maxRoutePoints {
            next = next.enumerated().compactMap { i, c in i % 2 == 0 ? c : nil }
        }
        routeCoordinates = next
        lastRouteSample = loc
    }
}

extension CardioWorkoutLocationTracker: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isReceivingUpdates else { return }
        guard let loc = locations.last else { return }
        guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 80 else { return }

        DispatchQueue.main.async {
            self.lastHorizontalAccuracyM = loc.horizontalAccuracy

            let maxAcc: CLLocationAccuracy = self.gpsProfile == .balanced ? 55 : 72
            if loc.horizontalAccuracy <= maxAcc {
                self.appendRouteSample(loc)
            }

            if let last = self.lastLocation {
                let deltaM = loc.distance(from: last)
                if deltaM > 2, deltaM < 500 {
                    self.distanceKm += deltaM / 1_000.0
                }
            }
            self.lastLocation = loc
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isReceivingUpdates = false
        }
    }
}
