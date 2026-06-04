import Foundation

enum NutritionMetabolism {
    static let fallbackKcalFemale = 1500
    static let fallbackKcalMale = 1900
    static let fallbackKcalNeutral = 1700
    static let minKcal = 800
    static let maxKcal = 6000
    static let imputedAgeYears = 30

    static func sexOffset(sex: String?) -> Double {
        let normalized = (sex ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "male", "m": return 5
        case "female", "f": return -161
        default: return -80
        }
    }

    static func workoutActivityMultiplier(workoutsPerWeek: Double) -> Double {
        let wpw = max(0, workoutsPerWeek)
        if wpw < 1.5 { return 1.2 }
        if wpw < 3.5 { return 1.375 }
        if wpw < 5.5 { return 1.55 }
        return 1.725
    }

    static func imputedHeightCm(sex: String?, heightCm: Double?) -> Double {
        if let heightCm, heightCm > 0 { return heightCm }
        let normalized = (sex ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "male" || normalized == "m" ? 175 : 162
    }

    static func imputedWeightKg(sex: String?, weightKg: Double?) -> Double {
        if let weightKg, weightKg > 0 { return weightKg }
        let normalized = (sex ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "male" || normalized == "m" ? 75 : 60
    }

    static func demographicFallbackKcal(sex: String?) -> Int {
        let normalized = (sex ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "female", "f": return fallbackKcalFemale
        case "male", "m": return fallbackKcalMale
        default: return fallbackKcalNeutral
        }
    }

    static func computeBmrKcal(
        sex: String?,
        birthDate: Date?,
        heightCm: Double?,
        weightKg: Double?,
        referenceDate: Date = Date()
    ) -> Int {
        let height = imputedHeightCm(sex: sex, heightCm: heightCm)
        let weight = imputedWeightKg(sex: sex, weightKg: weightKg)
        let ageYears: Int
        if let birthDate {
            ageYears = Calendar.current.dateComponents([.year], from: birthDate, to: referenceDate).year ?? imputedAgeYears
        } else {
            ageYears = imputedAgeYears
        }
        let bmr = (10 * weight) + (6.25 * height) - (5 * Double(ageYears)) + sexOffset(sex: sex)
        return Int(bmr.rounded()).clamped(to: minKcal...maxKcal)
    }

    static func computeMetabolicTargetKcal(
        sex: String?,
        birthDate: Date?,
        heightCm: Double?,
        weightKg: Double?,
        workoutsPerWeek: Double = 0,
        referenceDate: Date = Date()
    ) -> Int {
        let bmr = computeBmrKcal(
            sex: sex,
            birthDate: birthDate,
            heightCm: heightCm,
            weightKg: weightKg,
            referenceDate: referenceDate
        )
        let mult = workoutActivityMultiplier(workoutsPerWeek: workoutsPerWeek)
        return Int((Double(bmr) * mult).rounded()).clamped(to: minKcal...maxKcal)
    }

    static func resolveDisplayKcal(
        sex: String?,
        birthDate: Date?,
        heightCm: Double?,
        weightKg: Double?,
        storedTarget: Int?,
        isManual: Bool,
        workoutsPerWeek: Double = 0,
        referenceDate: Date = Date()
    ) -> Int {
        if isManual {
            let stored = storedTarget ?? demographicFallbackKcal(sex: sex)
            return stored.clamped(to: minKcal...maxKcal)
        }
        return computeMetabolicTargetKcal(
            sex: sex,
            birthDate: birthDate,
            heightCm: heightCm,
            weightKg: weightKg,
            workoutsPerWeek: workoutsPerWeek,
            referenceDate: referenceDate
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
