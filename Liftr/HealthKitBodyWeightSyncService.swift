import Foundation
import HealthKit

struct BodyWeightImportSummary: Sendable {
    var imported: Int = 0
    var skippedDuplicate: Int = 0
    var failed: Int = 0
    var errorMessages: [String] = []
}

enum HealthKitBodyWeightSyncError: LocalizedError {
    case healthDataNotAvailable
    case bodyMassTypeUnavailable
    case backgroundDeliveryNotAuthorized

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            return "Health data is not available on this device."
        case .bodyMassTypeUnavailable:
            return "Body weight data is not available from HealthKit on this device."
        case .backgroundDeliveryNotAuthorized:
            return "Health background updates are not authorized. Allow Liftr to read body weight in Apple Health and try again."
        }
    }
}

final class HealthKitBodyWeightSyncService {
    static let shared = HealthKitBodyWeightSyncService()

    private let store = HKHealthStore()
    private let syncEnabledKey = "bodyWeightHealthSyncEnabled"
    private let lastAnchorDataKey = "bodyWeightHealthAnchorData"
    private let lastSyncAtKey = "bodyWeightHealthLastSyncAt"
    private var observerQuery: HKObserverQuery?

    private var bodyMassType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .bodyMass)
    }

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

    func requestReadAuthorization() async throws {
        guard let bodyMassType else { throw HealthKitBodyWeightSyncError.bodyMassTypeUnavailable }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: [bodyMassType]) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    func enableBackgroundSync() async throws {
        guard isHealthDataAvailable else { throw HealthKitBodyWeightSyncError.healthDataNotAvailable }
        guard let bodyMassType else { throw HealthKitBodyWeightSyncError.bodyMassTypeUnavailable }
        try await requestReadAuthorization()
        #if targetEnvironment(simulator)
        await activateWeightSyncFromHealthKit()
        #else
        try await enableBackgroundDelivery(for: bodyMassType)
        await activateWeightSyncFromHealthKit()
        #endif
    }

    func disableBackgroundSync() {
        isSyncEnabled = false
        if let observerQuery {
            store.stop(observerQuery)
            self.observerQuery = nil
        }
        if let bodyMassType {
            store.disableBackgroundDelivery(for: bodyMassType) { _, _ in }
        }
    }

    func syncRecentSamples() async -> BodyWeightImportSummary {
        let from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return await syncSamples(from: from, to: Date())
    }

    func syncSamples(from fromDate: Date, to toDate: Date) async -> BodyWeightImportSummary {
        var summary = BodyWeightImportSummary()
        guard isHealthDataAvailable else {
            summary.errorMessages.append(HealthKitBodyWeightSyncError.healthDataNotAvailable.localizedDescription)
            summary.failed += 1
            return summary
        }
        guard let bodyMassType else {
            summary.errorMessages.append(HealthKitBodyWeightSyncError.bodyMassTypeUnavailable.localizedDescription)
            summary.failed += 1
            return summary
        }

        let predicate = HKQuery.predicateForSamples(withStart: fromDate, end: toDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample]
        do {
            samples = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKQuantitySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: bodyMassType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sort]
                ) { _, results, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
                    }
                }
                store.execute(query)
            }
        } catch {
            summary.errorMessages.append(error.localizedDescription)
            summary.failed += 1
            return summary
        }

        for sample in samples {
            let kg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
            guard kg > 0 else {
                summary.failed += 1
                continue
            }
            do {
                let result = try await BodyWeightClient.upsertEntry(
                    measuredAt: sample.startDate,
                    weightKg: kg,
                    source: .appleHealth,
                    externalSampleId: sample.uuid.uuidString.lowercased()
                )
                if result.duplicate == true {
                    summary.skippedDuplicate += 1
                } else if result.inserted == true {
                    summary.imported += 1
                } else {
                    summary.skippedDuplicate += 1
                }
            } catch {
                summary.failed += 1
                summary.errorMessages.append(error.localizedDescription)
            }
        }

        UserDefaults.standard.set(Date(), forKey: lastSyncAtKey)
        return summary
    }

    func handleAppForegroundIfNeeded() async {
        guard isSyncEnabled else { return }
        startObserverIfNeeded()
        _ = await syncRecentSamples()
    }

    private func activateWeightSyncFromHealthKit() async {
        isSyncEnabled = true
        startObserverIfNeeded()
        let from = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        _ = await syncSamples(from: from, to: Date())
    }

    #if !targetEnvironment(simulator)
    private func enableBackgroundDelivery(for bodyMassType: HKQuantityType) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.enableBackgroundDelivery(for: bodyMassType, frequency: .daily) { ok, error in
                if let error {
                    cont.resume(throwing: Self.mapBackgroundDeliveryError(error))
                } else if !ok {
                    cont.resume(throwing: HealthKitBodyWeightSyncError.backgroundDeliveryNotAuthorized)
                } else {
                    cont.resume()
                }
            }
        }
    }
    #endif

    private func startObserverIfNeeded() {
        guard observerQuery == nil, let bodyMassType else { return }
        let query = HKObserverQuery(sampleType: bodyMassType, predicate: nil) { [weak self] _, completion, error in
            defer { completion() }
            guard error == nil else { return }
            Task {
                _ = await self?.syncRecentSamples()
            }
        }
        observerQuery = query
        store.execute(query)
    }

    private static func mapBackgroundDeliveryError(_ error: Error) -> Error {
        if let hkError = error as? HKError, hkError.code == .errorAuthorizationDenied {
            return HealthKitBodyWeightSyncError.backgroundDeliveryNotAuthorized
        }
        return error
    }
}
