import CoreLocation
import MapKit

enum TerritoryMapGeometry {
    struct GeographicBoundingBox {
        let minLatitude: Double
        let maxLatitude: Double
        let minLongitude: Double
        let maxLongitude: Double
    }

    static func geographicBoundingBox(ring: [CLLocationCoordinate2D]) -> GeographicBoundingBox? {
        guard let first = ring.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coordinate in ring.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        return GeographicBoundingBox(
            minLatitude: minLat,
            maxLatitude: maxLat,
            minLongitude: minLon,
            maxLongitude: maxLon
        )
    }

    static func intersects(region: MKCoordinateRegion, bbox: GeographicBoundingBox) -> Bool {
        let regionMinLat = region.center.latitude - region.span.latitudeDelta / 2
        let regionMaxLat = region.center.latitude + region.span.latitudeDelta / 2
        let regionMinLon = region.center.longitude - region.span.longitudeDelta / 2
        let regionMaxLon = region.center.longitude + region.span.longitudeDelta / 2
        if bbox.maxLatitude < regionMinLat || bbox.minLatitude > regionMaxLat { return false }
        if bbox.maxLongitude < regionMinLon || bbox.minLongitude > regionMaxLon { return false }
        return true
    }

    static func regionsApproximatelyEqual(_ lhs: MKCoordinateRegion, _ rhs: MKCoordinateRegion) -> Bool {
        abs(lhs.center.latitude - rhs.center.latitude) < 0.000001
            && abs(lhs.center.longitude - rhs.center.longitude) < 0.000001
            && abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) < 0.000001
            && abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) < 0.000001
    }

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

    static func ownerBalancedCells(
        _ cells: [TerritoryMapCellRow],
        maxCount: Int,
        otherTarget: Int
    ) -> [TerritoryMapCellRow] {
        guard maxCount > 0 else { return [] }
        guard cells.count > maxCount, otherTarget > 0 else {
            return Array(cells.sorted(by: recencyThenIdentifier).prefix(maxCount))
        }

        let mine = cells
            .filter { $0.is_mine == true }
            .sorted(by: recencyThenIdentifier)
        let others = cells
            .filter { !($0.is_mine == true) }
        let selectedOthers = routeBalancedOthers(others, limit: min(maxCount, otherTarget))
        let mineLimit = max(0, maxCount - selectedOthers.count)

        return Array(mine.prefix(mineLimit)) + selectedOthers
    }

    private static func recencyThenIdentifier(_ lhs: TerritoryMapCellRow, _ rhs: TerritoryMapCellRow) -> Bool {
        let lhsCaptured = lhs.captured_at ?? .distantPast
        let rhsCaptured = rhs.captured_at ?? .distantPast
        if lhsCaptured != rhsCaptured {
            return lhsCaptured > rhsCaptured
        }
        return lhs.cell_id < rhs.cell_id
    }

    private static func routeBalancedOthers(_ cells: [TerritoryMapCellRow], limit: Int) -> [TerritoryMapCellRow] {
        guard limit > 0 else { return [] }
        let grouped = Dictionary(grouping: cells) { cell in
            let ownerKey = cell.owner_user_id?.uuidString ?? "unknown"
            let routeKey = cell.last_workout_id.map(String.init) ?? cell.cell_id
            return "\(ownerKey)|\(routeKey)"
        }
        let routeGroups = grouped.values.map { cells in
            cells.sorted(by: recencyThenIdentifier)
        }
        let ownerGroups = Dictionary(grouping: routeGroups) { group in
            group.first?.owner_user_id?.uuidString ?? "unknown"
        }
        let ownerKeys = ownerGroups.keys.sorted()
        let groupsByOwner = ownerKeys.map { key in
            ownerGroups[key, default: []].sorted { lhs, rhs in
                guard let lhsFirst = lhs.first, let rhsFirst = rhs.first else {
                    return lhs.count > rhs.count
                }
                return recencyThenIdentifier(lhsFirst, rhsFirst)
            }
        }
        var balanced: [TerritoryMapCellRow] = []
        var index = 0
        while balanced.count < limit {
            var added = false
            for groupsForOwner in groupsByOwner {
                guard index < groupsForOwner.count else { continue }
                let group = groupsForOwner[index]
                guard balanced.count + group.count <= limit else { continue }
                balanced.append(contentsOf: group)
                added = true
                if balanced.count >= limit {
                    break
                }
            }
            guard added else { break }
            index += 1
        }
        if balanced.isEmpty {
            return Array(cells.sorted(by: recencyThenIdentifier).prefix(limit))
        }
        return balanced
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
