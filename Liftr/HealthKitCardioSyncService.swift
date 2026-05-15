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
    private var observerQuery: HKObserverQuery?

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isSyncEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: syncEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: syncEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }

    var lastSyncAt: Date? {
        UserDefaults.standard.object(forKey: lastSyncAtKey) as? Date
    }

    func enableBackgroundSync() async throws {
        guard isHealthDataAvailable else { throw HealthKitCardioSyncError.healthDataNotAvailable }
        try await HealthKitCardioImportService.shared.requestReadAuthorization()
        #if targetEnvironment(simulator)
        await activateCardioSyncFromHealthKit()
        #else
        try await enableBackgroundDelivery()
        await activateCardioSyncFromHealthKit()
        #endif
    }

    func disableBackgroundSync() {
        isSyncEnabled = false
        if let observerQuery {
            store.stop(observerQuery)
            self.observerQuery = nil
        }
        store.disableBackgroundDelivery(for: HKObjectType.workoutType()) { _, _ in }
    }

    @discardableResult
    func syncRecentWorkouts() async -> HealthKitImportSummary {
        let from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return await syncWorkouts(from: from, to: Date())
    }

    @discardableResult
    func syncWorkouts(from fromDate: Date, to toDate: Date) async -> HealthKitImportSummary {
        guard isSyncEnabled else { return HealthKitImportSummary() }
        guard isWorkoutReadAuthorized else { return HealthKitImportSummary() }
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
        guard isWorkoutReadAuthorized else { return }
        startObserverIfNeeded()
        _ = await syncRecentWorkouts()
    }

    private var isWorkoutReadAuthorized: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    private func activateCardioSyncFromHealthKit() async {
        isSyncEnabled = true
        startObserverIfNeeded()
        let from = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        _ = await syncWorkouts(from: from, to: Date())
    }

    #if !targetEnvironment(simulator)
    private func enableBackgroundDelivery() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.enableBackgroundDelivery(
                for: HKObjectType.workoutType(),
                frequency: .immediate
            ) { ok, error in
                if let error {
                    cont.resume(throwing: Self.mapBackgroundDeliveryError(error))
                } else if !ok {
                    cont.resume(throwing: HealthKitCardioSyncError.backgroundDeliveryNotAuthorized)
                } else {
                    cont.resume()
                }
            }
        }
    }
    #endif

    private func startObserverIfNeeded() {
        guard observerQuery == nil else { return }
        let workoutType = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completion, error in
            defer { completion() }
            guard error == nil else { return }
            Task {
                _ = await self?.syncRecentWorkouts()
            }
        }
        observerQuery = query
        store.execute(query)
    }

    private static func mapBackgroundDeliveryError(_ error: Error) -> Error {
        if let hkError = error as? HKError, hkError.code == .errorAuthorizationDenied {
            return HealthKitCardioSyncError.backgroundDeliveryNotAuthorized
        }
        return error
    }
}
