import Foundation

struct NutritionLabelScannedFormValues: Equatable {
    let calories: String
    let protein: String
    let carbs: String
    let fat: String
    let saturatedFat: String
    let sugars: String
    let fiber: String
    let sodiumMg: String

    static func from(parsed: NutritionLabelParseResult) -> NutritionLabelScannedFormValues {
        NutritionLabelScannedFormValues(
            calories: NutritionLabelParser.formatFieldValue(parsed.calories),
            protein: NutritionLabelParser.formatFieldValue(parsed.protein),
            carbs: NutritionLabelParser.formatFieldValue(parsed.carbs),
            fat: NutritionLabelParser.formatFieldValue(parsed.fat),
            saturatedFat: NutritionLabelParser.formatFieldValue(parsed.saturatedFat),
            sugars: NutritionLabelParser.formatFieldValue(parsed.sugars),
            fiber: NutritionLabelParser.formatFieldValue(parsed.fiber),
            sodiumMg: NutritionLabelParser.formatFieldValue(parsed.sodiumMg)
        )
    }
}

struct NutritionIngredientFormState: Equatable {
    var revision: UUID = UUID()
    var calories: String = "100"
    var protein: String = "0"
    var carbs: String = "0"
    var fat: String = "0"
    var saturatedFat: String = "0"
    var sugars: String = "0"
    var fiber: String = "0"
    var sodiumMg: String = "0"

    static func clearedForScan() -> NutritionIngredientFormState {
        NutritionIngredientFormState(
            revision: UUID(),
            calories: "0",
            protein: "0",
            carbs: "0",
            fat: "0",
            saturatedFat: "0",
            sugars: "0",
            fiber: "0",
            sodiumMg: "0"
        )
    }

    static func from(ingredient: NutritionIngredientRow) -> NutritionIngredientFormState {
        NutritionIngredientFormState(
            revision: UUID(),
            calories: NutritionLabelParser.formatFieldValue(ingredient.calories_per_100g),
            protein: NutritionLabelParser.formatFieldValue(ingredient.protein_per_100g),
            carbs: NutritionLabelParser.formatFieldValue(ingredient.carbs_per_100g),
            fat: NutritionLabelParser.formatFieldValue(ingredient.fat_per_100g),
            saturatedFat: NutritionLabelParser.formatFieldValue(ingredient.saturated_fat_per_100g),
            sugars: NutritionLabelParser.formatFieldValue(ingredient.sugars_per_100g),
            fiber: NutritionLabelParser.formatFieldValue(ingredient.fiber_per_100g),
            sodiumMg: NutritionLabelParser.formatFieldValue(ingredient.sodium_mg_per_100g)
        )
    }

    static func applyingScan(_ parsed: NutritionLabelParseResult) -> NutritionIngredientFormState {
        let values = NutritionLabelScannedFormValues.from(parsed: parsed)
        return NutritionIngredientFormState(
            revision: UUID(),
            calories: values.calories,
            protein: values.protein,
            carbs: values.carbs,
            fat: values.fat,
            saturatedFat: values.saturatedFat,
            sugars: values.sugars,
            fiber: values.fiber,
            sodiumMg: values.sodiumMg
        )
    }

    func updating(_ keyPath: WritableKeyPath<NutritionIngredientFormState, String>, to value: String) -> NutritionIngredientFormState {
        var copy = self
        copy[keyPath: keyPath] = value
        copy.revision = UUID()
        return copy
    }

    func profilePer100g() -> NutritionProfilePer100g {
        NutritionProfilePer100g(
            calories: Double(calories.replacingOccurrences(of: ",", with: ".")) ?? 0,
            protein: Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0,
            carbs: Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0,
            fat: Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0,
            saturatedFat: Double(saturatedFat.replacingOccurrences(of: ",", with: ".")) ?? 0,
            sugars: Double(sugars.replacingOccurrences(of: ",", with: ".")) ?? 0,
            fiber: Double(fiber.replacingOccurrences(of: ",", with: ".")) ?? 0,
            sodiumMg: Double(sodiumMg.replacingOccurrences(of: ",", with: ".")) ?? 0
        )
    }
}
