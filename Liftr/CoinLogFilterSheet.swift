import SwiftUI

enum CoinLogFilterCategory: String, CaseIterable, Identifiable {
    case workouts
    case petWorkoutBonus = "pet_workout_bonus"
    case petCoins = "pet_coins"
    case social
    case nutrition
    case achievements
    case goalsStreaks = "goals_streaks"
    case competition
    case petCombat = "pet_combat"
    case other

    var id: String { rawValue }

    var label: String {
        CoinManager.sourceCategoryLabel(for: rawValue)
    }

    static func isVisible(actionType: String, disabledKeys: Set<String>) -> Bool {
        let key = CoinManager.sourceKey(for: actionType)
        return !disabledKeys.contains(key)
    }
}

struct CoinLogFilterSheet: View {
    @Binding var disabledCategories: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(CoinLogFilterCategory.allCases) { category in
                        Toggle(isOn: binding(for: category.rawValue)) {
                            Text(category.label)
                        }
                    }
                } footer: {
                    Text("Filters apply to loaded transactions only.")
                }
            }
            .navigationTitle("Transaction filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Show all") {
                        disabledCategories = []
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hide all") {
                        disabledCategories = Set(CoinLogFilterCategory.allCases.map(\.rawValue))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { !disabledCategories.contains(key) },
            set: { enabled in
                if enabled {
                    disabledCategories.remove(key)
                } else {
                    disabledCategories.insert(key)
                }
            }
        )
    }
}
