import Foundation

enum NutritionMetabolism {
    static let fallbackKcal = 2000
    static let minKcal = 800
    static let maxKcal = 6000

    static func computeBmrKcal(
        sex: String?,
        birthDate: Date?,
        heightCm: Double?,
        weightKg: Double?,
        referenceDate: Date = Date()
    ) -> Int? {
        guard let birthDate,
              let heightCm, heightCm > 0,
              let weightKg, weightKg > 0 else { return nil }

        let normalized = (sex ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sexOffset: Double
        switch normalized {
        case "male", "m": sexOffset = 5
        case "female", "f": sexOffset = -161
        default: return nil
        }

        let ageYears = Calendar.current.dateComponents([.year], from: birthDate, to: referenceDate).year ?? 0
        let bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(ageYears)) + sexOffset
        return Int(bmr.rounded()).clamped(to: minKcal...maxKcal)
    }

    static func resolveDisplayKcal(
        sex: String?,
        birthDate: Date?,
        heightCm: Double?,
        weightKg: Double?,
        storedTarget: Int?,
        isManual: Bool
    ) -> Int {
        if isManual {
            let stored = storedTarget ?? fallbackKcal
            return stored.clamped(to: minKcal...maxKcal)
        }
        return computeBmrKcal(sex: sex, birthDate: birthDate, heightCm: heightCm, weightKg: weightKg)
            ?? fallbackKcal
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
