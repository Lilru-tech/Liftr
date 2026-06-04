import Foundation

enum HealthKitRouteImportPolicy {
    static let recentWorkoutWindow: TimeInterval = 30 * 60
    static let backfillLookbackDays = 90
    static let routeRetryDelaysNs: [UInt64] = [5_000_000_000, 10_000_000_000, 20_000_000_000]
    static let anchoredWaitRecentNs: UInt64 = 30_000_000_000
    static let anchoredWaitOlderNs: UInt64 = 3_000_000_000

    static let indoorActivityCodes: Set<String> = [
        CardioActivityType.treadmill.rawValue,
        CardioActivityType.indoor_cycling.rawValue
    ]

    static func isOutdoorActivityCode(_ code: String?) -> Bool {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !code.isEmpty
        else { return false }
        return !indoorActivityCodes.contains(code)
    }

    static func shouldRetryRouteFetch(workoutEndedAt: Date, locationCount: Int, now: Date = Date()) -> Bool {
        locationCount < 2 && now.timeIntervalSince(workoutEndedAt) <= recentWorkoutWindow
    }

    static func anchoredRouteWaitNanoseconds(workoutEndedAt: Date, now: Date = Date()) -> UInt64 {
        now.timeIntervalSince(workoutEndedAt) <= recentWorkoutWindow
            ? anchoredWaitRecentNs
            : anchoredWaitOlderNs
    }

    static func shouldSkipDuplicateImport(isTreadmill: Bool, missingRouteInDb: Bool, hasFetchedRoute: Bool) -> Bool {
        if isTreadmill { return true }
        if !missingRouteInDb { return true }
        return !hasFetchedRoute
    }

    static func routeGeojsonIsEmpty(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return true
        }
        return false
    }
}

extension HealthKitImportSummary {
    mutating func absorb(_ other: HealthKitImportSummary) {
        imported += other.imported
        skippedDuplicate += other.skippedDuplicate
        mergedDuplicate += other.mergedDuplicate
        failed += other.failed
        outdoorWorkoutsMissingRoute += other.outdoorWorkoutsMissingRoute
        routesBackfilled += other.routesBackfilled
        errorMessages.append(contentsOf: other.errorMessages)
    }
}
