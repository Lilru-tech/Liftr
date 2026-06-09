import Foundation

extension Notification.Name {
    static let petStateDidChange = Notification.Name("liftr.petStateDidChange")
}

enum PetRefreshCenter {
    static func notifyPetStateDidChange() {
        NotificationCenter.default.post(name: .petStateDidChange, object: nil)
    }
}

enum PetHatchEventHandler {
    static let localNotificationIdentifier = "liftr.pet.hatch"

    @MainActor
    static func handleHatchEvent(navigateToProfile: Bool = true) {
        if navigateToProfile {
            AppState.shared.selectedTab = .profile
        }
        PetHatchLocalNotificationScheduler.cancel()
        PetRefreshCenter.notifyPetStateDidChange()
        Task {
            await CoinManager.shared.refreshBalanceAfterMutation(notifyIfEarned: true)
        }
    }
}
