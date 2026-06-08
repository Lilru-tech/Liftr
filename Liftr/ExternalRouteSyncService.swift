import CoreLocation
import Foundation
import HealthKit
import Supabase

struct ExternalRoutePoint: Decodable, Sendable {
    let lat: Double
    let lon: Double
    let alt: Double?
    let ts: String?
}

struct ExternalRouteJob: Decodable, Sendable, Identifiable {
    let id: UUID
    let provider: String
    let provider_activity_id: String
    let started_at: Date
    let ended_at: Date?
    let duration_sec: Int?
    let activity_code: String?
    let route_points: [ExternalRoutePoint]
}

struct ExternalRouteSyncSummary: Sendable {
    var applied: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var errorMessages: [String] = []

    static let unavailable = ExternalRouteSyncSummary(
        failed: 1,
        errorMessages: [HealthKitRouteWriteError.healthDataNotAvailable.localizedDescription]
    )
}

enum WearableRedirect {
    static let host = "wearable-callback"

    static func isWearableCallback(_ url: URL) -> Bool {
        url.host == host
    }

    static func status(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "status" })?
            .value
    }

    static func provider(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "provider" })?
            .value
    }
}

final class ExternalRouteSyncService {
    static let shared = ExternalRouteSyncService()

    private let syncEnabledKey = "externalRouteSyncEnabled"
    private let lastSyncAtKey = "externalRouteLastSyncAt"
    private let routesAppliedKey = "externalRouteAppliedCount"

    var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: syncEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }

    var lastSyncAt: Date? {
        UserDefaults.standard.object(forKey: lastSyncAtKey) as? Date
    }

    var routesAppliedCount: Int {
        UserDefaults.standard.integer(forKey: routesAppliedKey)
    }

    @discardableResult
    func processPendingJobs(userId: UUID) async -> ExternalRouteSyncSummary {
        guard isSyncEnabled else { return ExternalRouteSyncSummary() }
        guard HealthKitRouteWriteService.shared.isHealthDataAvailable else {
            return .unavailable
        }

        var summary = ExternalRouteSyncSummary()
        do {
            try await HealthKitRouteWriteService.shared.requestRouteWriteAuthorization()
        } catch {
            summary.failed += 1
            summary.errorMessages.append(error.localizedDescription)
            return summary
        }

        let jobs: [ExternalRouteJob]
        do {
            jobs = try await fetchPendingJobs()
        } catch {
            summary.failed += 1
            summary.errorMessages.append(error.localizedDescription)
            return summary
        }

        for job in jobs {
            let partial = await processJob(job, userId: userId)
            summary.applied += partial.applied
            summary.skipped += partial.skipped
            summary.failed += partial.failed
            summary.errorMessages.append(contentsOf: partial.errorMessages)
        }

        if summary.applied > 0 {
            let total = routesAppliedCount + summary.applied
            UserDefaults.standard.set(total, forKey: routesAppliedKey)
        }
        UserDefaults.standard.set(Date(), forKey: lastSyncAtKey)
        return summary
    }

    func handleWearableCallbackURL(_ url: URL) async {
        guard WearableRedirect.isWearableCallback(url) else { return }
        guard WearableRedirect.status(from: url) == "connected" else { return }
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
        isSyncEnabled = true
        _ = await processPendingJobs(userId: userId)
    }

    private func processJob(_ job: ExternalRouteJob, userId: UUID) async -> ExternalRouteSyncSummary {
        var summary = ExternalRouteSyncSummary()
        guard let activityCode = job.activity_code,
              let hkActivity = ExternalRouteActivityMapping.hkWorkoutActivityType(for: activityCode)
        else {
            await updateJobStatus(job.id, status: "failed", reason: "unsupported_activity", hkUUID: nil)
            summary.failed += 1
            return summary
        }

        let durationSec = job.duration_sec ?? max(1, Int(job.ended_at?.timeIntervalSince(job.started_at) ?? 60))
        let criteria = HealthKitWorkoutMatchCriteria(
            startedAt: job.started_at,
            endedAt: job.ended_at,
            durationSec: durationSec,
            activityType: hkActivity,
            preferredSourceBundleIds: ExternalRouteSourceBundles.preferredBundles(for: job.provider)
        )

        let windowStart = job.started_at.addingTimeInterval(-HealthKitWorkoutMatcher.startTolerance)
        let windowEnd = (job.ended_at ?? job.started_at).addingTimeInterval(HealthKitWorkoutMatcher.startTolerance)

        let workouts: [HKWorkout]
        do {
            workouts = try await HealthKitRouteWriteService.shared.fetchWorkouts(from: windowStart, to: windowEnd)
        } catch {
            await updateJobStatus(job.id, status: "failed", reason: "healthkit_query_failed", hkUUID: nil)
            summary.failed += 1
            summary.errorMessages.append(error.localizedDescription)
            return summary
        }

        var routeCounts: [UUID: Int] = [:]
        for workout in workouts {
            let routes = (try? await HealthKitCardioImportService.shared.workoutRoutes(for: workout)) ?? []
            routeCounts[workout.uuid] = routes.count
        }

        guard let workout = HealthKitWorkoutMatcher.findBestMatch(
            in: workouts,
            criteria: criteria,
            existingRouteCounts: routeCounts
        ) else {
            await updateJobStatus(job.id, status: "failed", reason: "no_matching_hk_workout", hkUUID: nil)
            summary.failed += 1
            return summary
        }

        let existingRoutes = (try? await HealthKitCardioImportService.shared.workoutRoutes(for: workout)) ?? []
        if ExternalRouteDedupPolicy.shouldSkip(
            workout: workout,
            existingRoutes: existingRoutes,
            provider: job.provider,
            providerActivityId: job.provider_activity_id
        ) {
            await updateJobStatus(job.id, status: "skipped", reason: "route_already_present", hkUUID: workout.uuid.uuidString.lowercased())
            summary.skipped += 1
            return summary
        }

        let locations = locations(from: job.route_points)
        guard locations.count >= 2 else {
            await updateJobStatus(job.id, status: "failed", reason: "insufficient_route_points", hkUUID: nil)
            summary.failed += 1
            return summary
        }

        let metadata = ExternalRouteDedupPolicy.routeMetadata(
            provider: job.provider,
            providerActivityId: job.provider_activity_id
        )

        do {
            _ = try await HealthKitRouteWriteService.shared.attachRoute(
                locations: locations,
                to: workout,
                metadata: metadata
            )
        } catch {
            await updateJobStatus(job.id, status: "failed", reason: "healthkit_write_failed", hkUUID: nil)
            summary.failed += 1
            summary.errorMessages.append(error.localizedDescription)
            return summary
        }

        let coords = RouteLineStringDecimation.decimate(locations.map(\.coordinate))
        if let geojson = RouteLineStringDecimation.encodeGeoJSONLineString(coords) {
            await applyRouteToLiftr(
                healthkitUUID: workout.uuid.uuidString.lowercased(),
                geojson: geojson,
                job: job,
                durationSec: durationSec
            )
        }

        await updateJobStatus(
            job.id,
            status: "applied_healthkit",
            reason: nil,
            hkUUID: workout.uuid.uuidString.lowercased()
        )
        summary.applied += 1

        _ = await HealthKitCardioImportService.shared.backfillMissingHealthKitRoutes(
            userId: userId,
            mode: .automatic
        )
        return summary
    }

    private func locations(from points: [ExternalRoutePoint]) -> [CLLocation] {
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFraction = ISO8601DateFormatter()
        isoNoFraction.formatOptions = [.withInternetDateTime]

        return points.compactMap { point in
            guard point.lat.isFinite, point.lon.isFinite else { return nil }
            let altitude = point.alt ?? 0
            let timestamp: Date = {
                guard let ts = point.ts?.trimmingCharacters(in: .whitespacesAndNewlines), !ts.isEmpty else {
                    return Date()
                }
                return isoWithFraction.date(from: ts)
                    ?? isoNoFraction.date(from: ts)
                    ?? Date()
            }()
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon),
                altitude: altitude,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: timestamp
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }

    private func fetchPendingJobs() async throws -> [ExternalRouteJob] {
        let res = try await SupabaseManager.shared.client
            .from("external_workout_route_jobs")
            .select("id, provider, provider_activity_id, started_at, ended_at, duration_sec, activity_code, route_points")
            .eq("status", value: "pending")
            .order("started_at", ascending: false)
            .limit(50)
            .execute()
        return try JSONDecoder.supabaseCustom().decode([ExternalRouteJob].self, from: res.data)
    }

    private func applyRouteToLiftr(
        healthkitUUID: String,
        geojson: String,
        job: ExternalRouteJob,
        durationSec: Int
    ) async {
        struct Params: Encodable {
            let p_healthkit_uuid: String
            let p_route_geojson: String
            let p_provider: String
            let p_provider_activity_id: String
            let p_started_at: String
            let p_ended_at: String?
            let p_duration_sec: Int
            let p_activity_code: String?
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        let params = Params(
            p_healthkit_uuid: healthkitUUID,
            p_route_geojson: geojson,
            p_provider: job.provider,
            p_provider_activity_id: job.provider_activity_id,
            p_started_at: iso.string(from: job.started_at),
            p_ended_at: job.ended_at.map { iso.string(from: $0) },
            p_duration_sec: durationSec,
            p_activity_code: job.activity_code
        )
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("apply_external_route_to_cardio_workout", params: params)
                .execute()
        } catch {
            print("[ExternalRouteSync] apply route RPC error:", error.localizedDescription)
        }
    }

    private func updateJobStatus(
        _ jobId: UUID,
        status: String,
        reason: String?,
        hkUUID: String?
    ) async {
        struct Params: Encodable {
            let p_job_id: UUID
            let p_status: String
            let p_skip_reason: String?
            let p_healthkit_workout_uuid: String?
        }
        do {
            _ = try await SupabaseManager.shared.client
                .rpc(
                    "update_external_route_job_status",
                    params: Params(
                        p_job_id: jobId,
                        p_status: status,
                        p_skip_reason: reason,
                        p_healthkit_workout_uuid: hkUUID
                    )
                )
                .execute()
        } catch {
            print("[ExternalRouteSync] update job status error:", error.localizedDescription)
        }
    }
}
