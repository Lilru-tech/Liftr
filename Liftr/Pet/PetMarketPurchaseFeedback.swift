import Foundation
import Combine

@MainActor
final class PetMarketPurchaseFeedback: ObservableObject {
    static let shared = PetMarketPurchaseFeedback()

    @Published private(set) var unseenMyItemsCount = 0
    @Published var toastMessage: String?

    private var toastDismissTask: Task<Void, Never>?

    private init() {}

    func recordPurchase(itemType: String) {
        guard itemType == "pet_egg" || itemType == "incubator" else { return }
        unseenMyItemsCount += 1
        toastMessage = itemType == "pet_egg"
            ? "Mysterious Egg added to My Items"
            : "Egg Incubator added to My Items"
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            toastMessage = nil
        }
    }

    func clearBadge() {
        unseenMyItemsCount = 0
    }
}
