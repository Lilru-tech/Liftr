import Foundation
import HealthKit

enum HealthKitCardioSyncError: LocalizedError {
    case healthDataNotAvailable
    case backgroundDeliveryNotAuthorized

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            return "Health data is not available on this device."
        case .backgroundDeliveryNotAuthorized:
            return "Health background updates are not authorized. Allow Liftr to read workouts in Apple Health and try again."
        }
    }
}

final class HealthKitCardioSyncService {
    static let shared = HealthKitCardioSyncService()

    private let store = HKHealthStore()
    private let syncEnabledKey = "cardioHealthSyncEnabled"
    private let lastSyncAtKey = "cardioHealthLastSyncAt"
    private var workoutObserverQuery: HKObserverQuery?
    private var routeObserverQuery: HKObserverQuery?

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: syncEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }

    var lastSyncAt: Date? {
        UserDefaults.standard.object(forKey: lastSyncAtKey) as? Date
    }

    @discardableResult
    func enableBackgroundSync() async throws -> HealthKitImportSummary {
        guard isHealthDataAvailable else { throw HealthKitCardioSyncError.healthDataNotAvailable }
        try await HealthKitCardioImportService.shared.requestReadAuthorization()
        #if targetEnvironment(simulator)
        return await activateCardioSyncFromHealthKit()
        #else
        try await enableBackgroundDelivery()
        return await activateCardioSyncFromHealthKit()
        #endif
    }

    func disableBackgroundSync() {
        isSyncEnabled = false
        if let workoutObserverQuery {
            store.stop(workoutObserverQuery)
            self.workoutObserverQuery = nil
        }
        if let routeObserverQuery {
            store.stop(routeObserverQuery)
            self.routeObserverQuery = nil
        }
        store.disableBackgroundDelivery(for: HKObjectType.workoutType()) { _, _ in }
        store.disableBackgroundDelivery(for: HKSeriesType.workoutRoute()) { _, _ in }
    }

    @discardableResult
    func syncRecentWorkouts() async -> HealthKitImportSummary {
        let from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return await syncWorkouts(from: from, to: Date())
    }

    @discardableResult
    func syncWorkouts(from fromDate: Date, to toDate: Date) async -> HealthKitImportSummary {
        guard isSyncEnabled else { return HealthKitImportSummary() }
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else {
            return HealthKitImportSummary()
        }

        let summary = await HealthKitCardioImportService.shared.importCardioWorkouts(
            from: fromDate,
            to: toDate,
            userId: userId,
            mode: .automatic
        )
        UserDefaults.standard.set(Date(), forKey: lastSyncAtKey)
        return summary
    }

    func handleAppForegroundIfNeeded() async {
        guard isSyncEnabled else { return }
        startObserversIfNeeded()
        _ = await syncRecentWorkouts()
    }

    private func activateCardioSyncFromHealthKit() async -> HealthKitImportSummary {
        isSyncEnabled = true
        startObserversIfNeeded()
        let from = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        return await syncWorkouts(from: from, to: Date())
    }

    #if !targetEnvironment(simulator)
    private func enableBackgroundDelivery() async throws {
        try await Self.enableBackgroundDelivery(for: store)
    }

    private static func enableBackgroundDelivery(for healthStore: HKHealthStore) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            healthStore.enableBackgroundDelivery(
                for: HKObjectType.workoutType(),
                frequency: .immediate
            ) { ok, deliveryError in
                if let deliveryError {
                    cont.resume(throwing: mapBackgroundDeliveryError(deliveryError))
                    return
                }
                if !ok {
                    cont.resume(throwing: HealthKitCardioSyncError.backgroundDeliveryNotAuthorized)
                    return
                }
                healthStore.enableBackgroundDelivery(
                    for: HKSeriesType.workoutRoute(),
                    frequency: .immediate
                ) { _, _ in
                    cont.resume()
                }
            }
        }
    }
    #endif

    private func startObserversIfNeeded() {
        startWorkoutObserverIfNeeded()
        startRouteObserverIfNeeded()
    }

    private func startWorkoutObserverIfNeeded() {
        guard workoutObserverQuery == nil else { return }
        let workoutType = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completion, error in
            defer { completion() }
            guard error == nil else { return }
            Task {
                _ = await self?.syncRecentWorkouts()
            }
        }
        workoutObserverQuery = query
        store.execute(query)
    }

    private func startRouteObserverIfNeeded() {
        guard routeObserverQuery == nil else { return }
        let routeType = HKSeriesType.workoutRoute()
        let query = HKObserverQuery(sampleType: routeType, predicate: nil) { [weak self] _, completion, error in
            defer { completion() }
            guard error == nil else { return }
            Task {
                await self?.backfillRoutesIfNeeded()
            }
        }
        routeObserverQuery = query
        store.execute(query)
    }

    private func backfillRoutesIfNeeded() async {
        guard isSyncEnabled else { return }
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
        _ = await HealthKitCardioImportService.shared.backfillMissingHealthKitRoutes(
            userId: userId,
            mode: .automatic
        )
    }

    private static func mapBackgroundDeliveryError(_ error: Error) -> Error {
        if let hkError = error as? HKError, hkError.code == .errorAuthorizationDenied {
            return HealthKitCardioSyncError.backgroundDeliveryNotAuthorized
        }
        return error
    }
}
