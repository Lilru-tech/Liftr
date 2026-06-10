import Foundation

actor SerialAsyncTaskRunner {
    private var inFlight: Task<Void, Never>?

    func run(_ body: @Sendable @escaping () async -> Void) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await body() }
        inFlight = task
        await task.value
        inFlight = nil
    }
}
