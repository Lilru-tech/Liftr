import CoreLocation

enum TerritoryMapGeometry {
    static func polygonContains(point: CLLocationCoordinate2D, ring: [CLLocationCoordinate2D]) -> Bool {
        guard ring.count >= 3 else { return false }
        let x = point.longitude
        let y = point.latitude
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let xi = ring[i].longitude
            let yi = ring[i].latitude
            let xj = ring[j].longitude
            let yj = ring[j].latitude
            let intersects = ((yi > y) != (yj > y))
                && (x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi)
            if intersects {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func polygonArea(ring: [CLLocationCoordinate2D]) -> Double {
        guard ring.count >= 3 else { return .greatestFiniteMagnitude }
        var area = 0.0
        var j = ring.count - 1
        for i in 0..<ring.count {
            area += (ring[j].longitude + ring[i].longitude) * (ring[j].latitude - ring[i].latitude)
            j = i
        }
        return abs(area) * 0.5
    }

    static func selectedCell(at coordinate: CLLocationCoordinate2D, in cells: [TerritoryMapCellRow]) -> TerritoryMapCellRow? {
        let matches = cells.filter { cell in
            let ring = cell.ring
            return ring.count >= 3 && polygonContains(point: coordinate, ring: ring)
        }
        guard !matches.isEmpty else { return nil }
        return matches.sorted { lhs, rhs in
            let lhsCaptured = lhs.captured_at ?? .distantPast
            let rhsCaptured = rhs.captured_at ?? .distantPast
            if lhsCaptured != rhsCaptured {
                return lhsCaptured > rhsCaptured
            }
            return polygonArea(ring: lhs.ring) < polygonArea(ring: rhs.ring)
        }.first
    }
}
