import Foundation

@MainActor
final class PetDetailViewModel: ObservableObject {
    @Published var data: PetFullData?
    @Published var logs: [PetLog] = []
    @Published var hasMoreLogs = true
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSavingName = false
    @Published var isFeeding = false
    @Published var isEvolving = false
    @Published var isRerolling = false

    private var pollTask: Task<Void, Never>?
    private var logsOffset = 0
    private let logsPageSize = 5
    private var lastKnownStage: String?

    func load() async {
        isLoading = data == nil
        errorMessage = nil
        let previousStage = data?.pet?.evolutionStage ?? lastKnownStage
        do {
            data = try await PetService.shared.fetchMyPet()
            handleStageTransition(from: previousStage, to: data?.pet?.evolutionStage)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func handleStageTransition(from previousStage: String?, to newStage: String?) {
        guard let newStage else { return }
        defer { lastKnownStage = newStage }

        let wasEgg = previousStage?.lowercased() == "egg"
        let isBaby = newStage.lowercased() == "baby"
        guard wasEgg, isBaby else { return }

        PetHatchEventHandler.handleHatchEvent(navigateToProfile: false)
    }

    func reloadLogs() async {
        logsOffset = 0
        hasMoreLogs = true
        do {
            let page = try await PetService.shared.fetchPetLogs(offset: 0, limit: logsPageSize)
            logs = page
            logsOffset = page.count
            hasMoreLogs = page.count >= logsPageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreLogs() async {
        guard hasMoreLogs else { return }
        do {
            let page = try await PetService.shared.fetchPetLogs(offset: logsOffset, limit: logsPageSize)
            logs.append(contentsOf: page)
            logsOffset += page.count
            hasMoreLogs = page.count >= logsPageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAllLogs() async {
        do {
            try await PetService.shared.deleteAllPetLogs()
            logs = []
            logsOffset = 0
            hasMoreLogs = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                let pet = data?.pet
                let shouldPoll = pet?.isIncubatingEgg == true || pet?.isPendingHatch == true
                if shouldPoll {
                    await load()
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    let p = data?.pet
                    if p?.isIncubatingEgg == true || p?.isPendingHatch == true { continue }
                    break
                }
            }
            pollTask = nil
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func updateName(_ name: String) async {
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await PetService.shared.updateName(name)
            await load()
            PetRefreshCenter.notifyPetStateDidChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func feed(itemType: String) async {
        isFeeding = true
        defer { isFeeding = false }
        do {
            try await PetService.shared.feed(itemType: itemType)
            await load()
            PetRefreshCenter.notifyPetStateDidChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmEvolution() async {
        isEvolving = true
        defer { isEvolving = false }
        do {
            try await PetService.shared.confirmEvolution()
            await load()
            PetRefreshCenter.notifyPetStateDidChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rerollEgg() async {
        isRerolling = true
        defer { isRerolling = false }
        do {
            let hatchAt = try await PetService.shared.rerollEgg()
            await load()
            if let hatchAt, let petType = data?.pet?.petType {
                PetHatchLocalNotificationScheduler.schedule(hatchAt: hatchAt, petType: petType)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
