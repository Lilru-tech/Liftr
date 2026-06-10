import CoreGraphics
import Foundation

struct ProfilePetFabBounds {
    let minX: CGFloat
    let maxX: CGFloat
    let minY: CGFloat
    let maxY: CGFloat

    var width: CGFloat { maxX - minX }
    var height: CGFloat { maxY - minY }
    var perimeter: CGFloat { 2 * (width + height) }
}

enum ProfilePetFabPositionStore {
    private static let perimeterKey = "profilePetFabPerimeterT"
    private static let legacyCenterXKey = "profilePetFabCenterX"
    private static let legacyCenterYKey = "profilePetFabCenterY"

    static let defaultPerimeterT: CGFloat = -1

    static func savedPerimeterT() -> CGFloat? {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: perimeterKey) != nil {
            let t = defaults.double(forKey: perimeterKey)
            guard t >= 0, t <= 1 else { return nil }
            return CGFloat(t)
        }

        guard defaults.object(forKey: legacyCenterXKey) != nil,
              defaults.object(forKey: legacyCenterYKey) != nil else {
            return nil
        }

        let legacy = CGPoint(
            x: defaults.double(forKey: legacyCenterXKey),
            y: defaults.double(forKey: legacyCenterYKey)
        )
        guard legacy.x >= 0, legacy.x <= 1, legacy.y >= 0, legacy.y <= 1 else { return nil }
        return nil
    }

    static func savePerimeterT(_ t: CGFloat) {
        let clamped = min(1, max(0, t))
        let defaults = UserDefaults.standard
        defaults.set(Double(clamped), forKey: perimeterKey)
        defaults.removeObject(forKey: legacyCenterXKey)
        defaults.removeObject(forKey: legacyCenterYKey)
    }

    static func defaultPerimeterT(for bounds: ProfilePetFabBounds) -> CGFloat {
        perimeterParameter(for: CGPoint(x: bounds.maxX, y: bounds.maxY), in: bounds)
    }

    static func bounds(
        in size: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat,
        tabBarHeight: CGFloat,
        bannerInset: CGFloat,
        fabRadius: CGFloat,
        padding: CGFloat
    ) -> ProfilePetFabBounds {
        ProfilePetFabBounds(
            minX: fabRadius + padding,
            maxX: size.width - fabRadius - padding,
            minY: safeAreaTop + fabRadius + padding,
            maxY: size.height - safeAreaBottom - tabBarHeight - bannerInset - fabRadius - padding
        )
    }

    static func point(onPerimeter t: CGFloat, in bounds: ProfilePetFabBounds) -> CGPoint {
        let perimeter = max(bounds.perimeter, 1)
        var distance = t.truncatingRemainder(dividingBy: 1)
        if distance < 0 { distance += 1 }
        distance *= perimeter

        let w = bounds.width
        let h = bounds.height

        if distance <= w {
            return CGPoint(x: bounds.minX + distance, y: bounds.minY)
        }
        distance -= w
        if distance <= h {
            return CGPoint(x: bounds.maxX, y: bounds.minY + distance)
        }
        distance -= h
        if distance <= w {
            return CGPoint(x: bounds.maxX - distance, y: bounds.maxY)
        }
        distance -= w
        return CGPoint(x: bounds.minX, y: bounds.maxY - distance)
    }

    static func perimeterParameter(for point: CGPoint, in bounds: ProfilePetFabBounds) -> CGFloat {
        let snapped = nearestPointOnPerimeter(point, in: bounds)
        let w = bounds.width
        let h = bounds.height
        let perimeter = max(bounds.perimeter, 1)

        if snapped.y == bounds.minY {
            return (snapped.x - bounds.minX) / perimeter
        }
        if snapped.x == bounds.maxX {
            return (w + (snapped.y - bounds.minY)) / perimeter
        }
        if snapped.y == bounds.maxY {
            return (w + h + (bounds.maxX - snapped.x)) / perimeter
        }
        return (w + h + w + (bounds.maxY - snapped.y)) / perimeter
    }

    static func nearestPointOnPerimeter(_ point: CGPoint, in bounds: ProfilePetFabBounds) -> CGPoint {
        let candidates = [
            CGPoint(x: clamp(point.x, bounds.minX, bounds.maxX), y: bounds.minY),
            CGPoint(x: bounds.maxX, y: clamp(point.y, bounds.minY, bounds.maxY)),
            CGPoint(x: clamp(point.x, bounds.minX, bounds.maxX), y: bounds.maxY),
            CGPoint(x: bounds.minX, y: clamp(point.y, bounds.minY, bounds.maxY))
        ]

        return candidates.min {
            hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y)
        } ?? candidates[0]
    }

    static func resolvedPerimeterT(
        saved: CGFloat?,
        legacyNormalized: CGPoint?,
        in bounds: ProfilePetFabBounds
    ) -> CGFloat {
        if let saved {
            return saved
        }
        if let legacyNormalized {
            let legacyPoint = CGPoint(
                x: bounds.minX + legacyNormalized.x * max(bounds.width, 1),
                y: bounds.minY + legacyNormalized.y * max(bounds.height, 1)
            )
            return perimeterParameter(for: legacyPoint, in: bounds)
        }
        return defaultPerimeterT(for: bounds)
    }

    private static func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        min(maxValue, max(minValue, value))
    }
}
