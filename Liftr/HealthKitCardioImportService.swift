import Foundation
import HealthKit
import CoreLocation
import Supabase
import UIKit

struct HealthKitImportSummary: Sendable {
    var imported: Int = 0
    var skippedDuplicate: Int = 0
    var mergedDuplicate: Int = 0
    var failed: Int = 0
    var outdoorWorkoutsMissingRoute: Int = 0
    var routesBackfilled: Int = 0
    var errorMessages: [String] = []

    var suggestsWorkoutRoutePermissionIssue: Bool {
        outdoorWorkoutsMissingRoute > 0 && (imported + mergedDuplicate + routesBackfilled) > 0
    }
}

enum HealthKitCardioImportMode: Sendable {
    case manual
    case automatic
}

enum HealthKitCardioImportDuplicateDetection {
    static func isHealthKitUuidUniqueViolation(_ error: Error) -> Bool {
        if let pe = error as? PostgrestError {
            guard pe.code == "23505" else { return false }
            let message = (pe.message).lowercased()
            return message.contains("healthkit_uuid")
                || message.contains("workouts_healthkit_uuid_unique")
                || message.contains("workouts_user_healthkit_uuid_unique")
        }
        let text = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        guard text.contains("23505") || text.contains("duplicate key") else { return false }
        return text.contains("healthkit_uuid")
            || text.contains("workouts_healthkit_uuid_unique")
            || text.contains("workouts_user_healthkit_uuid_unique")
    }
}

enum HealthKitCardioImportNotificationPolicy {
    static let recentImportWindow: TimeInterval = 48 * 3600
    static let mergedWorkoutAgeThreshold: TimeInterval = 120

    static func shouldNotifyAutoImport(workoutEndedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(workoutEndedAt) <= recentImportWindow
    }

    static func wasExistingWorkoutBeforeImport(createdAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(createdAt) > mergedWorkoutAgeThreshold
    }
}

enum HealthKitCardioImportError: LocalizedError {
    case healthDataNotAvailable

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            return "Health data is not available on this device."
        }
    }
}

final class HealthKitCardioImportService {
    static let shared = HealthKitCardioImportService()

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        if let d = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { s.insert(d) }
        if let d = HKQuantityType.quantityType(forIdentifier: .distanceCycling) { s.insert(d) }
        if let d = HKQuantityType.quantityType(forIdentifier: .distanceSwimming) { s.insert(d) }
        if let e = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(e) }
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { s.insert(hr) }
        return s
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestReadAuthorization() async throws {
        try await performAuthorizationRequest(readTypes: readTypes)
        let routeOnly: Set<HKObjectType> = [HKSeriesType.workoutRoute()]
        let shouldRequestRoutes = try await authorizationShouldBeRequested(for: routeOnly)
        if shouldRequestRoutes {
            try await performAuthorizationRequest(readTypes: readTypes)
        }
    }

    static func openAppleHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url)
    }

    private func performAuthorizationRequest(readTypes: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    private func authorizationShouldBeRequested(for types: Set<HKObjectType>) async throws -> Bool {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            store.getRequestStatusForAuthorization(toShare: [], read: types) { status, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: status == .shouldRequest)
                }
            }
        }
    }

    func importCardioWorkouts(
        from fromDate: Date,
        to toDate: Date,
        userId: UUID,
        mode: HealthKitCardioImportMode = .manual
    ) async -> HealthKitImportSummary {
        var summary = HealthKitImportSummary()
        guard isHealthDataAvailable else {
            summary.errorMessages.append(HealthKitCardioImportError.healthDataNotAvailable.localizedDescription)
            summary.failed += 1
            return summary
        }

        do {
            try await requestReadAuthorization()
        } catch {
            summary.errorMessages.append(error.localizedDescription)
            summary.failed += 1
            return summary
        }

        let workouts: [HKWorkout]
        do {
            workouts = try await fetchWorkouts(from: fromDate, to: toDate)
        } catch {
            summary.errorMessages.append(error.localizedDescription)
            summary.failed += 1
            return summary
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current

        for w in workouts {
            let partial = await processHealthKitWorkout(w, userId: userId, mode: mode, iso: iso)
            summary.absorb(partial)
        }

        let backfill = await backfillMissingHealthKitRoutes(userId: userId, mode: mode)
        summary.absorb(backfill)

        return summary
    }

    func backfillMissingHealthKitRoutes(
        userId: UUID,
        mode: HealthKitCardioImportMode = .automatic
    ) async -> HealthKitImportSummary {
        var summary = HealthKitImportSummary()
        guard isHealthDataAvailable else { return summary }

        do {
            try await requestReadAuthorization()
        } catch {
            summary.errorMessages.append(error.localizedDescription)
            summary.failed += 1
            return summary
        }

        let candidates: [RouteBackfillCandidate]
        do {
            candidates = try await fetchRouteBackfillCandidates(userId: userId)
        } catch {
            summary.errorMessages.append(error.localizedDescription)
            summary.failed += 1
            return summary
        }

        guard !candidates.isEmpty else { return summary }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current

        for candidate in candidates {
            guard let hkUUID = UUID(uuidString: candidate.healthkit_uuid) else { continue }
            guard let workout = try? await fetchWorkout(byHealthKitUUID: hkUUID) else { continue }

            let partial = await processHealthKitWorkout(workout, userId: userId, mode: mode, iso: iso)
            summary.absorb(partial)
        }

        return summary
    }

    private struct RouteBackfillCandidate {
        let workoutId: Int
        let healthkit_uuid: String
        let activity_code: String?
    }

    private struct BackfillWorkoutRow: Decodable {
        let id: Int
        let healthkit_uuid: String?
        let created_at: Date
        let cardio_sessions: [BackfillSessionRow]?
    }

    private struct BackfillSessionRow: Decodable {
        let route_geojson: String?
        let activity_code: String?
    }

    private func fetchRouteBackfillCandidates(userId: UUID) async throws -> [RouteBackfillCandidate] {
        let since = Calendar.current.date(
            byAdding: .day,
            value: -HealthKitRouteImportPolicy.backfillLookbackDays,
            to: Date()
        ) ?? Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current

        let res = try await SupabaseManager.shared.client
            .from("workouts")
            .select("id, healthkit_uuid, created_at, cardio_sessions(route_geojson, activity_code)")
            .eq("user_id", value: userId)
            .eq("kind", value: "cardio")
            .gte("created_at", value: iso.string(from: since))
            .execute()

        let rows = try JSONDecoder.supabase().decode([BackfillWorkoutRow].self, from: res.data)
        return rows.compactMap { row in
            guard let hkUUID = row.healthkit_uuid?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !hkUUID.isEmpty,
                  let session = row.cardio_sessions?.first
            else { return nil }
            guard HealthKitRouteImportPolicy.isOutdoorActivityCode(session.activity_code) else { return nil }
            guard HealthKitRouteImportPolicy.routeGeojsonIsEmpty(session.route_geojson) else { return nil }
            return RouteBackfillCandidate(
                workoutId: row.id,
                healthkit_uuid: hkUUID.lowercased(),
                activity_code: session.activity_code
            )
        }
    }

    private func processHealthKitWorkout(
        _ w: HKWorkout,
        userId: UUID,
        mode: HealthKitCardioImportMode,
        iso: ISO8601DateFormatter
    ) async -> HealthKitImportSummary {
        var summary = HealthKitImportSummary()
        guard let mapped = mapActivityCode(workout: w) else { return summary }

        let hkUUID = w.uuid.uuidString.lowercased()
        let existingWorkoutId = try? await fetchWorkoutIdByHealthKitUUID(hkUUID, userId: userId)
        let isTreadmill = mapped.code == CardioActivityType.treadmill.rawValue

        let durationSec = max(1, Int(w.duration.rounded()))
        var distanceKm = w.totalDistance?.doubleValue(for: HKUnit.meter()) ?? 0
        if distanceKm > 0 { distanceKm /= 1000.0 }

        let (avgHR, maxHR) = await heartRateStats(for: w)
        let elevationM = elevationGainMeters(workout: w)
        let activeEnergyKcal = await activeEnergyKilocalories(for: w)

        var routeGeoJSON: String?
        var routeLocations: [CLLocation] = []
        if !isTreadmill {
            do {
                routeLocations = try await fetchRouteLocationsWithRetry(for: w)
                let coords = routeLocations.map(\.coordinate)
                if coords.count >= 2 {
                    let trimmed = RouteLineStringDecimation.decimate(coords)
                    routeGeoJSON = Self.geoJSONLineString(from: trimmed)
                    if distanceKm < 0.001 {
                        let m = Self.polylineLengthMeters(coords)
                        if m > 0 { distanceKm = m / 1000.0 }
                    }
                }
            } catch {
                routeGeoJSON = nil
                routeLocations = []
            }
            if routeGeoJSON == nil, distanceKm > 0.001 {
                summary.outdoorWorkoutsMissingRoute += 1
            }
        }

        if let existingWorkoutId {
            let missingRoute = await workoutMissingRoute(workoutId: existingWorkoutId)
            if HealthKitRouteImportPolicy.shouldSkipDuplicateImport(
                isTreadmill: isTreadmill,
                missingRouteInDb: missingRoute,
                hasFetchedRoute: routeGeoJSON != nil
            ) {
                summary.skippedDuplicate += 1
                return summary
            }
        }

        let paceSecPerKm: Int? = {
            guard distanceKm > 0.001 else { return nil }
            return Int(round(Double(durationSec) / distanceKm))
        }()

        let kmSplitsFromRoute = Self.kmSplitPaceSecFromRoute(
            locations: routeLocations,
            workout: w,
            polylineLengthMeters: routeLocations.count >= 2
                ? Self.polylineLengthMeters(routeLocations.map(\.coordinate))
                : 0
        )

        let title = "\(mapped.label) · Apple Health"
        let notes = "Imported from Apple Health."

        let statsJSON = Self.cardioImportStatsJSON(
            inclinePct: isTreadmill ? Self.inclinePercentFromWorkoutMetadata(w) : nil,
            kmSplitPaceSec: kmSplitsFromRoute
        )

        let params = RPCCardioV2Params(
            p_user_id: userId,
            p_activity_code: mapped.code,
            p_title: title,
            p_started_at: iso.string(from: w.startDate),
            p_ended_at: iso.string(from: w.endDate),
            p_notes: notes,
            p_distance_km: distanceKm > 0 ? distanceKm : nil,
            p_duration_sec: durationSec,
            p_avg_hr: avgHR,
            p_max_hr: maxHR,
            p_avg_pace_sec_per_km: paceSecPerKm,
            p_elevation_gain_m: isTreadmill ? nil : elevationM,
            p_perceived_intensity: WorkoutIntensity.moderate.rawValue,
            p_state: "published",
            p_stats: statsJSON,
            p_healthkit_uuid: hkUUID,
            p_route_geojson: isTreadmill ? nil : routeGeoJSON,
            p_calories_kcal: activeEnergyKcal,
            p_calories_method: activeEnergyKcal == nil ? nil : "healthkit_active_energy"
        )

        do {
            let res = try await SupabaseManager.shared.client
                .rpc("create_cardio_workout_v2", params: RPCCardioV2Wrapper(p: params))
                .execute()

            var wid = Self.decodeRPCWorkoutId(res.data)
            if wid == nil {
                wid = try? await fetchWorkoutIdByHealthKitUUID(hkUUID, userId: userId)
            }
            if let wid {
                let merged = await wasMergedIntoExistingWorkout(workoutId: wid)
                if merged {
                    summary.mergedDuplicate += 1
                    if routeGeoJSON != nil {
                        summary.routesBackfilled += 1
                    }
                } else {
                    summary.imported += 1
                }
                if !isTreadmill, routeGeoJSON != nil {
                    if let captureSummary = await TerritoryCaptureClient.applyCapture(workoutId: wid),
                       let message = TerritoryCapturePresentation.message(for: captureSummary) {
                        TerritoryCaptureClient.storeCaptureReferenceCoordinate(from: captureSummary)
                        await MainActor.run {
                            AppState.shared.territoryCaptureToast = message
                        }
                    }
                }
                await MainActor.run {
                    NotificationCenter.default.post(name: .workoutDidChange, object: wid)
                }
                if !merged,
                   mode == .automatic,
                   HealthKitCardioImportNotificationPolicy.shouldNotifyAutoImport(workoutEndedAt: w.endDate) {
                    await notifyAutoImportedWorkout(workoutId: wid, title: title)
                }
            } else {
                summary.imported += 1
            }
        } catch {
            if HealthKitCardioImportDuplicateDetection.isHealthKitUuidUniqueViolation(error) {
                summary.skippedDuplicate += 1
            } else {
                summary.failed += 1
                summary.errorMessages.append("\(mapped.label): \(error.localizedDescription)")
            }
        }

        return summary
    }

    private func fetchWorkout(byHealthKitUUID uuid: UUID) async throws -> HKWorkout? {
        let pred = HKQuery.predicateForObjects(with: Set([uuid]))
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HKWorkout?, Error>) in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: pred,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: (samples as? [HKWorkout])?.first)
            }
            store.execute(q)
        }
    }

    private static let supportedWorkoutActivityTypes: [HKWorkoutActivityType] = {
        [.running, .walking, .hiking, .cycling, .swimming, .rowing]
    }()

    private func fetchWorkouts(from: Date, to: Date) async throws -> [HKWorkout] {
        let datePred = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let activityPredicates = Self.supportedWorkoutActivityTypes.map {
            HKQuery.predicateForWorkouts(with: $0)
        }
        let activityPred = NSCompoundPredicate(orPredicateWithSubpredicates: activityPredicates)
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [activityPred, datePred])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKWorkout], Error>) in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let ws = (samples as? [HKWorkout]) ?? []
                cont.resume(returning: ws)
            }
            store.execute(q)
        }
    }

    private struct ActivityMap {
        let code: String
        let label: String
    }

    private static func isIndoorWorkout(_ workout: HKWorkout) -> Bool {
        let raw = workout.metadata?[HKMetadataKeyIndoorWorkout]
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        if let i = raw as? Int { return i != 0 }
        return false
    }

    private static func inclinePercentFromWorkoutMetadata(_ workout: HKWorkout) -> Double? {
        guard let meta = workout.metadata else { return nil }
        let keys = [
            "incline_pct", "Incline", "incline", "treadmill_incline_pct",
            "HKIndoorInclinePercentage", "GymKitInclinePercentage"
        ]
        for key in keys {
            guard let v = meta[key] else { continue }
            if let d = v as? Double, d >= 0, d <= 100 { return d }
            if let n = v as? NSNumber {
                let d = n.doubleValue
                if d >= 0, d <= 100 { return d }
            }
            if let s = v as? String,
               let d = Double(s.replacingOccurrences(of: ",", with: ".")), d >= 0, d <= 100 {
                return d
            }
            if let q = v as? HKQuantity {
                let d = q.doubleValue(for: HKUnit.percent())
                if d >= 0, d <= 100 { return d }
            }
        }
        return nil
    }

    private static func cardioImportStatsJSON(inclinePct: Double?, kmSplitPaceSec: [Int]?) -> AnyJSON {
        var out: [String: AnyJSON] = [:]
        if let inc = inclinePct, let j = try? AnyJSON(inc) {
            out["incline_pct"] = j
        }
        if let splits = kmSplitPaceSec, !splits.isEmpty,
           let arr = try? AnyJSON(splits.map { try AnyJSON($0) }) {
            out[CardioKmPaceSplits.jsonKey] = arr
        }
        return (try? AnyJSON(out)) ?? (try! AnyJSON([String: AnyJSON]()))
    }

    private static func kmSplitPaceSecFromRoute(locations: [CLLocation], workout: HKWorkout, polylineLengthMeters: Double) -> [Int]? {
        guard locations.count >= 2, polylineLengthMeters >= 400 else { return nil }

        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else { return nil }

        let tStart = first.timestamp
        var timesAtKm: [Date] = []
        timesAtKm.reserveCapacity(Int(floor(polylineLengthMeters / 1000.0)))

        var cum = 0.0
        var nextKm = 1000.0

        for i in 1..<sorted.count {
            let a = sorted[i - 1]
            let b = sorted[i]
            let segM = a.distance(from: b)
            guard segM > 0.01 else { continue }

            let segStartDist = cum
            let segEndDist = cum + segM

            while nextKm <= segEndDist + 0.5 {
                let frac = (nextKm - segStartDist) / segM
                guard frac >= -1e-6, frac <= 1.0 + 1e-6 else { break }
                let clamped = min(1.0, max(0.0, frac))
                let dt = b.timestamp.timeIntervalSince(a.timestamp)
                let t = a.timestamp.addingTimeInterval(clamped * dt)
                timesAtKm.append(t)
                nextKm += 1000.0
            }
            cum = segEndDist
        }

        guard !timesAtKm.isEmpty else { return nil }

        var lapsSec: [Int] = []
        var prevT = tStart
        for t in timesAtKm {
            let sec = max(1, Int(round(t.timeIntervalSince(prevT))))
            lapsSec.append(sec)
            prevT = t
        }

        let fullKmCount = timesAtKm.count
        let coveredM = Double(fullKmCount) * 1000.0
        let remainderM = polylineLengthMeters - coveredM
        if remainderM >= 80, let lastLoc = sorted.last {
            let endT = min(workout.endDate, lastLoc.timestamp)
            if endT > prevT {
                let segSec = max(1, Int(round(endT.timeIntervalSince(prevT))))
                let remKm = remainderM / 1000.0
                if remKm >= 0.05 {
                    let paceEq = Int(round(Double(segSec) / remKm))
                    if paceEq > 0, paceEq < 3600 {
                        lapsSec.append(paceEq)
                    }
                }
            }
        }

        return lapsSec.isEmpty ? nil : lapsSec
    }

    private func mapActivityCode(workout: HKWorkout) -> ActivityMap? {
        switch workout.workoutActivityType {
        case .running:
            if Self.isIndoorWorkout(workout) {
                return ActivityMap(code: CardioActivityType.treadmill.rawValue, label: "Treadmill Run")
            }
            return ActivityMap(code: CardioActivityType.run.rawValue, label: "Run")
        case .walking:
            if Self.isIndoorWorkout(workout) {
                return ActivityMap(code: CardioActivityType.treadmill.rawValue, label: "Treadmill Walk")
            }
            return ActivityMap(code: CardioActivityType.walk.rawValue, label: "Walk")
        case .hiking:
            return ActivityMap(code: CardioActivityType.hike.rawValue, label: "Hike")
        case .cycling:
            if Self.isIndoorWorkout(workout) {
                return ActivityMap(code: CardioActivityType.indoor_cycling.rawValue, label: "Indoor cycling")
            }
            return ActivityMap(code: CardioActivityType.bike.rawValue, label: "Bike")
        case .swimming:
            let indoor = (workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false
            if indoor {
                return ActivityMap(code: CardioActivityType.swim_pool.rawValue, label: "Swim")
            }
            return ActivityMap(code: CardioActivityType.swim_open_water.rawValue, label: "Swim")
        case .rowing:
            return ActivityMap(code: CardioActivityType.rowerg.rawValue, label: "Row")
        default:
            return nil
        }
    }

    private func elevationGainMeters(workout: HKWorkout) -> Int? {
        guard let q = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity else { return nil }
        let m = q.doubleValue(for: HKUnit.meter())
        guard m > 0, m < 50_000 else { return nil }
        return Int(m.rounded())
    }

    private func heartRateStats(for workout: HKWorkout) async -> (avg: Int?, max: Int?) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return (nil, nil) }
        let pred = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: []
        )
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: hrType,
                quantitySamplePredicate: pred,
                options: [.discreteAverage, .discreteMax]
            ) { _, result, _ in
                let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
                let avg = result?.averageQuantity()?.doubleValue(for: unit).rounded()
                let max = result?.maximumQuantity()?.doubleValue(for: unit).rounded()
                cont.resume(returning: (
                    avg.map { Int($0) },
                    max.map { Int($0) }
                ))
            }
            store.execute(q)
        }
    }

    private func activeEnergyKilocalories(for workout: HKWorkout) async -> Double? {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        let pred = HKQuery.predicateForObjects(from: workout)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: pred,
                options: .cumulativeSum
            ) { _, result, _ in
                cont.resume(returning: Self.validKilocalories(result?.sumQuantity()?.doubleValue(for: .kilocalorie())))
            }
            store.execute(q)
        }
    }

    private static func validKilocalories(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value < 100_000 else { return nil }
        return (value * 10).rounded() / 10
    }

    private func fetchRouteLocationsWithRetry(for workout: HKWorkout) async throws -> [CLLocation] {
        var locations = try await fetchRouteLocations(for: workout)
        guard HealthKitRouteImportPolicy.shouldRetryRouteFetch(
            workoutEndedAt: workout.endDate,
            locationCount: locations.count
        ) else {
            return locations
        }

        for delay in HealthKitRouteImportPolicy.routeRetryDelaysNs {
            try await Task.sleep(nanoseconds: delay)
            locations = try await fetchRouteLocations(for: workout)
            if locations.count >= 2 { break }
        }
        return locations
    }

    private func fetchRouteLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        let routes = try await fetchWorkoutRoutes(for: workout)
        var all: [CLLocation] = []
        for route in routes {
            let chunk = try await routeLocations(for: route)
            all.append(contentsOf: chunk)
        }
        return all.sorted { $0.timestamp < $1.timestamp }
    }

    private func fetchWorkoutRoutes(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        let routeType = HKSeriesType.workoutRoute()
        let pred = HKQuery.predicateForObjects(from: workout)
        let waitNs = HealthKitRouteImportPolicy.anchoredRouteWaitNanoseconds(workoutEndedAt: workout.endDate)
        let anchored = try await fetchWorkoutRoutesAnchored(
            routeType: routeType,
            predicate: pred,
            waitNanoseconds: waitNs
        )
        if !anchored.isEmpty { return anchored }
        return try await fetchWorkoutRoutesSample(routeType: routeType, predicate: pred)
    }

    private func fetchWorkoutRoutesAnchored(
        routeType: HKSampleType,
        predicate: NSPredicate,
        waitNanoseconds: UInt64
    ) async throws -> [HKWorkoutRoute] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKWorkoutRoute], Error>) in
            let finishGate = HealthKitQueryFinishGate()
            var queryRef: HKQuery?

            func complete(_ routes: [HKWorkoutRoute]) {
                guard finishGate.claim() else { return }
                if let queryRef { store.stop(queryRef) }
                cont.resume(returning: routes)
            }

            func fail(_ error: Error) {
                guard finishGate.claim() else { return }
                if let queryRef { store.stop(queryRef) }
                cont.resume(throwing: error)
            }

            let q = HKAnchoredObjectQuery(
                type: routeType,
                predicate: predicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, error in
                if let error {
                    fail(error)
                    return
                }
                let routes = (samples as? [HKWorkoutRoute]) ?? []
                if !routes.isEmpty {
                    complete(routes)
                }
            }

            q.updateHandler = { _, samples, _, _, error in
                if finishGate.isClaimed { return }
                if let error {
                    fail(error)
                    return
                }
                let routes = (samples as? [HKWorkoutRoute]) ?? []
                if !routes.isEmpty {
                    complete(routes)
                }
            }

            queryRef = q
            store.execute(q)

            Task {
                try? await Task.sleep(nanoseconds: waitNanoseconds)
                if !finishGate.isClaimed {
                    complete([])
                }
            }
        }
    }

    private func fetchWorkoutRoutesSample(routeType: HKSampleType, predicate: NSPredicate) async throws -> [HKWorkoutRoute] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKWorkoutRoute], Error>) in
            let q = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(q)
        }
    }

    private func routeLocations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CLLocation], Error>) in
            var collected: [CLLocation] = []
            let q = HKWorkoutRouteQuery(route: route) { _, locationsOrNil, done, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let locs = locationsOrNil {
                    collected.append(contentsOf: locs)
                }
                if done {
                    cont.resume(returning: collected)
                }
            }
            store.execute(q)
        }
    }

    private func notifyAutoImportedWorkout(workoutId: Int, title: String) async {
        struct Params: Encodable {
            let p_workout_id: Int
            let p_title: String?
        }
        do {
            _ = try await SupabaseManager.shared.client
                .rpc(
                    "notify_apple_health_cardio_imported",
                    params: Params(p_workout_id: workoutId, p_title: title)
                )
                .execute()
            await AppState.shared.refreshUnreadNotificationsCount()
        } catch {
            print("[HealthKitCardioImport] notify auto-import error:", error.localizedDescription)
        }
    }

    private func workoutMissingRoute(workoutId: Int) async -> Bool {
        struct Row: Decodable { let route_geojson: String? }
        guard let res = try? await SupabaseManager.shared.client
            .from("cardio_sessions")
            .select("route_geojson")
            .eq("workout_id", value: workoutId)
            .limit(1)
            .execute(),
              let row = try? JSONDecoder.supabase().decode([Row].self, from: res.data).first
        else { return true }
        guard let route = row.route_geojson?.trimmingCharacters(in: .whitespacesAndNewlines),
              !route.isEmpty
        else { return true }
        return false
    }

    private func wasMergedIntoExistingWorkout(workoutId: Int) async -> Bool {
        struct Row: Decodable {
            let created_at: Date
        }
        guard let res = try? await SupabaseManager.shared.client
            .from("workouts")
            .select("created_at")
            .eq("id", value: workoutId)
            .limit(1)
            .execute(),
              let row = try? JSONDecoder.supabase().decode([Row].self, from: res.data).first
        else { return false }
        return HealthKitCardioImportNotificationPolicy.wasExistingWorkoutBeforeImport(createdAt: row.created_at)
    }

    private func fetchWorkoutIdByHealthKitUUID(_ uuid: String, userId: UUID) async throws -> Int? {
        let res = try await SupabaseManager.shared.client
            .from("workouts")
            .select("id")
            .eq("user_id", value: userId)
            .eq("healthkit_uuid", value: uuid)
            .limit(1)
            .execute()
        struct Row: Decodable { let id: Int }
        let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
        return rows.first?.id
    }

    private static func geoJSONLineString(from coordinates: [CLLocationCoordinate2D]) -> String? {
        guard coordinates.count >= 2 else { return nil }
        let parts = coordinates.map { "[\($0.longitude),\($0.latitude)]" }
        return "{\"type\":\"LineString\",\"coordinates\":[\(parts.joined(separator: ","))]}"
    }

    private static func decodeRPCWorkoutId(_ data: Data) -> Int? {
        if let id = try? JSONDecoder().decode(Int.self, from: data) { return id }
        if let arr = try? JSONDecoder().decode([Int].self, from: data) { return arr.first }
        return nil
    }

    private static func polylineLengthMeters(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var d = 0.0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            d += a.distance(from: b)
        }
        return d
    }
}

private final class HealthKitQueryFinishGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }

    var isClaimed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return claimed
    }
}
