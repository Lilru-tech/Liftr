import CoreLocation
import Foundation

enum RouteLineStringDecimation {
    static let maxStoredCoordinates = 2000

    static func decimate(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coords.count > maxStoredCoordinates else { return coords }
        let maxPoints = maxStoredCoordinates
        let n = coords.count
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(maxPoints)
        let denom = maxPoints - 1
        for i in 0..<maxPoints {
            let idx = (i * (n - 1)) / denom
            out.append(coords[idx])
        }
        return out
    }

    static func encodeGeoJSONLineString(_ coords: [CLLocationCoordinate2D]) -> String? {
        guard coords.count >= 2 else { return nil }
        let parts = coords.map { "[\($0.longitude),\($0.latitude)]" }
        return "{\"type\":\"LineString\",\"coordinates\":[\(parts.joined(separator: ","))]}"
    }
}
