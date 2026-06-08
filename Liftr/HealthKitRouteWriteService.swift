import CoreLocation
import Foundation
import HealthKit

enum HealthKitRouteWriteError: LocalizedError {
    case healthDataNotAvailable
    case insertFailed
    case finishFailed

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            return "Health data is not available on this device."
        case .insertFailed:
            return "Failed to insert route data into HealthKit."
        case .finishFailed:
            return "Failed to finish the workout route in HealthKit."
        }
    }
}

final class HealthKitRouteWriteService {
    static let shared = HealthKitRouteWriteService()

    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
    }

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
    }

    func requestRouteWriteAuthorization() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: shareTypes, read: readTypes) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    func attachRoute(
        locations: [CLLocation],
        to workout: HKWorkout,
        metadata: [String: Any]
    ) async throws -> HKWorkoutRoute {
        guard locations.count >= 2 else {
            throw HealthKitRouteWriteError.insertFailed
        }
        let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        try await insertRouteData(builder: builder, locations: locations)
        return try await finishRoute(builder: builder, workout: workout, metadata: metadata)
    }

    func fetchWorkouts(from: Date, to: Date) async throws -> [HKWorkout] {
        try await HealthKitCardioImportService.shared.fetchWorkoutsForRouteMatching(from: from, to: to)
    }

    private func insertRouteData(
        builder: HKWorkoutRouteBuilder,
        locations: [CLLocation]
    ) async throws {
        let chunkSize = 500
        var index = 0
        while index < locations.count {
            let end = min(index + chunkSize, locations.count)
            let chunk = Array(locations[index..<end])
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                builder.insertRouteData(chunk) { success, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if success {
                        cont.resume()
                    } else {
                        cont.resume(throwing: HealthKitRouteWriteError.insertFailed)
                    }
                }
            }
            index = end
        }
    }

    private func finishRoute(
        builder: HKWorkoutRouteBuilder,
        workout: HKWorkout,
        metadata: [String: Any]
    ) async throws -> HKWorkoutRoute {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HKWorkoutRoute, Error>) in
            builder.finishRoute(with: workout, metadata: metadata) { route, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let route {
                    cont.resume(returning: route)
                } else {
                    cont.resume(throwing: HealthKitRouteWriteError.finishFailed)
                }
            }
        }
    }
}
