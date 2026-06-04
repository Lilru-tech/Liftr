import Foundation

enum CardioSwimDisplay {
    static func isSwimActivity(code: String?) -> Bool {
        guard let raw = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return false
        }
        return raw == CardioActivityType.swim_pool.rawValue
            || raw == CardioActivityType.swim_open_water.rawValue
            || raw == "pool_swim" || raw == "pool_swimming"
            || raw == "open_water_swim" || raw == "open_water"
    }

    static func usesSwimUnits(activity: CardioActivityType) -> Bool {
        activity.usesSwimDistanceAndPace
    }

    static func usesSwimUnits(code: String?) -> Bool {
        isSwimActivity(code: code)
    }

    static func distanceKm(fromMetersText text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let meters = Double(t), meters > 0 else { return nil }
        return meters / 1000.0
    }

    static func metersText(fromKm km: Double?) -> String {
        guard let km, km > 0 else { return "" }
        let meters = km * 1000.0
        if abs(meters.rounded() - meters) < 0.001 {
            return String(format: "%.0f", meters.rounded())
        }
        return String(format: "%.1f", meters)
    }

    static func metersText(fromKmDecimal km: Decimal?) -> String {
        guard let km else { return "" }
        let d = NSDecimalNumber(decimal: km).doubleValue
        return metersText(fromKm: d)
    }

    static func secPer100m(fromSecPerKm secPerKm: Int) -> Int {
        max(0, Int((Double(secPerKm) / 10.0).rounded()))
    }

    static func formatSwimDistance(km: Double) -> String {
        let meters = km * 1000.0
        if abs(meters.rounded() - meters) < 0.001 {
            return String(format: "%.0f m", meters.rounded())
        }
        return String(format: "%.1f m", meters)
    }

    static func formatSwimPace(secPerKm: Int) -> String {
        let s = max(0, secPer100m(fromSecPerKm: secPerKm))
        return String(format: "%d:%02d /100m", s / 60, s % 60)
    }

    static func formatSwimPace(secPerKm: Double) -> String {
        formatSwimPace(secPerKm: Int(secPerKm.rounded()))
    }

    static func autoPaceSecPerKm(distanceMetersText: String, durationSec: Int) -> Int? {
        guard let km = distanceKm(fromMetersText: distanceMetersText), durationSec > 0 else { return nil }
        return Int((Double(durationSec) / km).rounded())
    }

    static func autoPaceSecPerKm(distanceMetersText: String, durH: String, durM: String, durS: String) -> Int? {
        guard let dur = hmsToSeconds(durH, durM, durS) else { return nil }
        return autoPaceSecPerKm(distanceMetersText: distanceMetersText, durationSec: dur)
    }

    static func swimPaceLabel(fromSecPerKm secPerKm: Int?) -> String {
        guard let secPerKm, secPerKm > 0 else { return "—" }
        return formatSwimPace(secPerKm: secPerKm)
    }

    static func poolDistanceMeters(lapsText: String, poolLengthMText: String) -> Int? {
        let laps = Int(lapsText.trimmingCharacters(in: .whitespacesAndNewlines))
        let pool = Int(poolLengthMText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let laps, let pool, laps > 0, pool > 0 else { return nil }
        return laps * pool
    }

    private static func hmsToSeconds(_ h: String, _ m: String, _ s: String) -> Int? {
        let hi = Int(h.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let mi = Int(m.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let si = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let total = hi * 3600 + mi * 60 + si
        return total > 0 ? total : nil
    }
}
