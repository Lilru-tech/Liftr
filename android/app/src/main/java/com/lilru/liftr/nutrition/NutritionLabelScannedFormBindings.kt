package com.lilru.liftr.nutrition

data class NutritionLabelScannedFormValues(
    val calories: String,
    val protein: String,
    val carbs: String,
    val fat: String,
    val saturatedFat: String,
    val sugars: String,
    val fiber: String,
    val sodiumMg: String
) {
    companion object {
        fun from(parsed: NutritionLabelParseResult): NutritionLabelScannedFormValues {
            return NutritionLabelScannedFormValues(
                calories = NutritionLabelParser.formatFieldValue(parsed.calories),
                protein = NutritionLabelParser.formatFieldValue(parsed.protein),
                carbs = NutritionLabelParser.formatFieldValue(parsed.carbs),
                fat = NutritionLabelParser.formatFieldValue(parsed.fat),
                saturatedFat = NutritionLabelParser.formatFieldValue(parsed.saturatedFat),
                sugars = NutritionLabelParser.formatFieldValue(parsed.sugars),
                fiber = NutritionLabelParser.formatFieldValue(parsed.fiber),
                sodiumMg = NutritionLabelParser.formatFieldValue(parsed.sodiumMg)
            )
        }
    }
}
