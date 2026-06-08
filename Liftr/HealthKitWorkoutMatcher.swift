import Foundation
import HealthKit

struct HealthKitWorkoutMatchCriteria: Sendable {
    let startedAt: Date
    let endedAt: Date?
    let durationSec: Int
    let activityType: HKWorkoutActivityType
    let preferredSourceBundleIds: [String]
}

enum ExternalRouteSourceBundles {
    static let garmin = "com.garmin.connect.mobile"
    static let fitbit = "com.fitbit.FitbitMobile"
    static let polar = "fi.polar.polarflow"

    static func preferredBundles(for provider: String) -> [String] {
        switch provider.lowercased() {
        case "garmin": return [garmin]
        case "fitbit": return [fitbit]
        case "polar": return [polar]
        default: return [garmin, fitbit, polar]
        }
    }
}

enum ExternalRouteActivityMapping {
    static func hkWorkoutActivityType(for activityCode: String) -> HKWorkoutActivityType? {
        switch activityCode.lowercased() {
        case "run", "treadmill": return .running
        case "walk", "hike": return activityCode.lowercased() == "hike" ? .hiking : .walking
        case "bike", "e_bike", "mtb", "indoor_cycling": return .cycling
        case "swim_pool", "swim_open_water": return .swimming
        case "rowerg": return .rowing
        default: return nil
        }
    }
}

enum HealthKitWorkoutMatcher {
    static let startTolerance: TimeInterval = 5 * 60
    static let durationToleranceRatio = 0.10
    static let durationToleranceSec: TimeInterval = 90

    static func durationMatches(workoutDuration: TimeInterval, expectedSec: Int) -> Bool {
        guard expectedSec > 0, workoutDuration > 0 else { return false }
        let delta = abs(workoutDuration - Double(expectedSec))
        let ratioThreshold = durationToleranceRatio * Double(max(expectedSec, Int(workoutDuration.rounded())))
        return delta <= max(durationToleranceSec, ratioThreshold)
    }

    static func startTimeDelta(_ workoutStart: Date, expectedStart: Date) -> TimeInterval {
        abs(workoutStart.timeIntervalSince(expectedStart))
    }

    static func sourceBundleId(for workout: HKWorkout) -> String? {
        workout.sourceRevision.source.bundleIdentifier
    }

    static func matchesBasicCriteria(
        workout: HKWorkout,
        criteria: HealthKitWorkoutMatchCriteria
    ) -> Bool {
        guard workout.workoutActivityType == criteria.activityType else { return false }
        guard startTimeDelta(workout.startDate, expectedStart: criteria.startedAt) <= startTolerance else {
            return false
        }
        return durationMatches(workoutDuration: workout.duration, expectedSec: criteria.durationSec)
    }

    static func matchScore(
        workout: HKWorkout,
        criteria: HealthKitWorkoutMatchCriteria,
        existingRouteCount: Int
    ) -> Int {
        var score = 0
        if existingRouteCount == 0 { score += 1000 }
        if let bundle = sourceBundleId(for: workout),
           criteria.preferredSourceBundleIds.contains(bundle) {
            score += 500
        }
        let delta = startTimeDelta(workout.startDate, expectedStart: criteria.startedAt)
        score += max(0, 300 - Int(delta))
        return score
    }

    static func findBestMatch(
        in workouts: [HKWorkout],
        criteria: HealthKitWorkoutMatchCriteria,
        existingRouteCounts: [UUID: Int]
    ) -> HKWorkout? {
        let candidates = workouts.filter { matchesBasicCriteria(workout: $0, criteria: criteria) }
        return candidates.max { lhs, rhs in
            let lhsScore = matchScore(
                workout: lhs,
                criteria: criteria,
                existingRouteCount: existingRouteCounts[lhs.uuid] ?? 0
            )
            let rhsScore = matchScore(
                workout: rhs,
                criteria: criteria,
                existingRouteCount: existingRouteCounts[rhs.uuid] ?? 0
            )
            return lhsScore < rhsScore
        }
    }
}
