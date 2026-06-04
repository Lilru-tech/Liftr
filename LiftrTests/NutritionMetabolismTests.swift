import Foundation
import Testing
@testable import Liftr

struct NutritionMetabolismTests {

  @Test func female28yo160cm57kg_metabolicTargetIs1523() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let birth = cal.date(from: DateComponents(year: 1998, month: 1, day: 1))!
    let ref = cal.date(from: DateComponents(year: 2026, month: 5, day: 27))!

    let result = NutritionMetabolism.computeMetabolicTargetKcal(
      sex: "female",
      birthDate: birth,
      heightCm: 160,
      weightKg: 57,
      referenceDate: ref
    )

    #expect(result == 1523)
  }

  @Test func missingMetrics_femaleUsesImputedBiometrics() {
    let result = NutritionMetabolism.resolveDisplayKcal(
      sex: "female",
      birthDate: nil,
      heightCm: nil,
      weightKg: nil,
      storedTarget: nil,
      isManual: false
    )
    #expect(result == 1562)
  }

  @Test func missingMetrics_maleUsesImputedBiometrics() {
    let result = NutritionMetabolism.resolveDisplayKcal(
      sex: "male",
      birthDate: nil,
      heightCm: nil,
      weightKg: nil,
      storedTarget: nil,
      isManual: false
    )
    #expect(result == 2039)
  }

  @Test func unknownSex_usesUnisexOffset() {
    let bmr = NutritionMetabolism.computeBmrKcal(
      sex: "prefer_not_to_say",
      birthDate: nil,
      heightCm: 162,
      weightKg: 60
    )
    #expect(bmr == 1302)
  }

  @Test func workoutMultiplier_tierModerate() {
    #expect(NutritionMetabolism.workoutActivityMultiplier(workoutsPerWeek: 2) == 1.375)
  }

  @Test func manualOverride_usesStoredNotComputed() {
    let result = NutritionMetabolism.resolveDisplayKcal(
      sex: "female",
      birthDate: Calendar.current.date(byAdding: .year, value: -28, to: Date()),
      heightCm: 160,
      weightKg: 57,
      storedTarget: 1800,
      isManual: true
    )
    #expect(result == 1800)
  }
}
