import Foundation
import Network
import Supabase

enum WorkoutStartSyncStatus: Equatable {
    case idle
    case pending
    case syncing
    case synced
    case willRetry
}

extension Notification.Name {
    static let workoutStartSyncStatusChanged = Notification.Name("workoutStartSyncStatusChanged")
}

enum WorkoutStartSync {
    private struct PendingStart: Codable, Equatable {
        let workoutId: Int
        let startedAtIso: String
        let enqueuedAt: Date
    }

    private static let storageKey = "liftr.pendingWorkoutStarts.v1"
    private static let backoffNs: [UInt64] = [
        500_000_000,
        2_000_000_000,
        5_000_000_000
    ]

    private static var monitor: NWPathMonitor?
    private static var syncTask: Task<Void, Never>?
    private static var statusByWorkoutId: [Int: WorkoutStartSyncStatus] = [:]

    private struct StartWorkoutRPCParams: Encodable {
        let p_workout_id: Int64
        let p_started_at: String
    }

    static func startMonitoring() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        monitor = m
        m.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task {
                await syncPending()
                await WorkoutFinishSync.syncPending()
            }
        }
        m.start(queue: DispatchQueue(label: "liftr.workout-start-sync"))
        Task {
            await syncPending()
            await WorkoutFinishSync.syncPending()
        }
    }

    static func status(for workoutId: Int) -> WorkoutStartSyncStatus {
        statusByWorkoutId[workoutId] ?? .idle
    }

    static func isPending(_ workoutId: Int) -> Bool {
        let s = status(for: workoutId)
        return s == .pending || s == .syncing || s == .willRetry
    }

    @discardableResult
    static func enqueueStart(workoutId: Int, startedAt: Date = Date()) -> String {
        let iso = isoString(from: startedAt)
        var pending = loadPending()
        pending.removeAll { $0.workoutId == workoutId }
        pending.append(PendingStart(workoutId: workoutId, startedAtIso: iso, enqueuedAt: Date()))
        savePending(pending)
        setStatus(.pending, workoutId: workoutId)
        Task { await syncPending() }
        return iso
    }

    static func syncPending() async {
        if let running = syncTask, !running.isCancelled {
            await running.value
            return
        }
        let task = Task {
            let items = loadPending()
            guard !items.isEmpty else { return }
            for item in items {
                await setStatusAsync(.syncing, workoutId: item.workoutId)
                let ok = await performStartWithRetries(workoutId: item.workoutId, startedAtIso: item.startedAtIso)
                if ok {
                    removePending(workoutId: item.workoutId)
                    await setStatusAsync(.synced, workoutId: item.workoutId)
                } else {
                    await setStatusAsync(.willRetry, workoutId: item.workoutId)
                }
            }
        }
        syncTask = task
        await task.value
        syncTask = nil
    }

    static func withRetries<T>(
        maxAttempts: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        let attempts = max(1, maxAttempts)
        for attempt in 0..<attempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < attempts - 1, isRetriable(error) else { throw error }
                let delay = backoffNs[min(attempt, backoffNs.count - 1)]
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        throw lastError ?? NSError(domain: "WorkoutStartSync", code: -1)
    }

    static func isRetriable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("network") || text.contains("connection") || text.contains("timed out") {
            return true
        }
        if let pe = error as? PostgrestError {
            let code = pe.code?.lowercased() ?? ""
            if code.contains("timeout") || code.contains("5") { return true }
        }
        return false
    }

    static func userFacingMessage(for error: Error) -> String {
        if isRetriable(error) {
            return String(localized: "Connection issue. You can start offline; we'll sync when you're back online.")
        }
        return error.localizedDescription
    }

    private static func performStartWithRetries(workoutId: Int, startedAtIso: String) async -> Bool {
        do {
            try await withRetries {
                try await executeStartRPC(workoutId: workoutId, startedAtIso: startedAtIso)
            }
            return true
        } catch {
            if !isRetriable(error) {
                removePending(workoutId: workoutId)
            }
            return false
        }
    }

    private static func executeStartRPC(workoutId: Int, startedAtIso: String) async throws {
        let params = StartWorkoutRPCParams(
            p_workout_id: Int64(workoutId),
            p_started_at: startedAtIso
        )
        let res = try await SupabaseManager.shared.client
            .rpc("start_workout_v1", params: params)
            .execute()
        let body = String(data: res.data, encoding: .utf8) ?? ""
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" {
            throw NSError(
                domain: "StartWorkout",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No row was updated (RLS/policy or invalid workout id)."]
            )
        }
    }

    private static func isoString(from date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.string(from: date)
    }

    private static func loadPending() -> [PendingStart] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([PendingStart].self, from: data)) ?? []
    }

    private static func savePending(_ items: [PendingStart]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func removePending(workoutId: Int) {
        var pending = loadPending()
        pending.removeAll { $0.workoutId == workoutId }
        savePending(pending)
    }

    private static func statusToken(_ status: WorkoutStartSyncStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .pending: return "pending"
        case .syncing: return "syncing"
        case .synced: return "synced"
        case .willRetry: return "willRetry"
        }
    }

    private static func setStatus(_ status: WorkoutStartSyncStatus, workoutId: Int) {
        statusByWorkoutId[workoutId] = status
        NotificationCenter.default.post(
            name: .workoutStartSyncStatusChanged,
            object: nil,
            userInfo: ["workoutId": workoutId, "status": statusToken(status)]
        )
    }

    @MainActor
    private static func setStatusAsync(_ status: WorkoutStartSyncStatus, workoutId: Int) async {
        setStatus(status, workoutId: workoutId)
    }
}
