package com.lilru.liftr.ui.nutrition

import com.lilru.liftr.nutrition.NutritionLabelParseResult
import com.lilru.liftr.nutrition.NutritionLabelScannedFormValues

data class NutritionIngredientFormState(
    val calories: String = "100",
    val protein: String = "0",
    val carbs: String = "0",
    val fat: String = "0",
    val saturatedFat: String = "0",
    val sugars: String = "0",
    val fiber: String = "0",
    val sodiumMg: String = "0"
) {
    fun toProfilePer100g(): NutritionProfilePer100g = NutritionProfilePer100g(
        calories = calories.replace(',', '.').toDoubleOrNull() ?: 0.0,
        protein = protein.replace(',', '.').toDoubleOrNull() ?: 0.0,
        carbs = carbs.replace(',', '.').toDoubleOrNull() ?: 0.0,
        fat = fat.replace(',', '.').toDoubleOrNull() ?: 0.0,
        saturatedFat = saturatedFat.replace(',', '.').toDoubleOrNull() ?: 0.0,
        sugars = sugars.replace(',', '.').toDoubleOrNull() ?: 0.0,
        fiber = fiber.replace(',', '.').toDoubleOrNull() ?: 0.0,
        sodiumMg = sodiumMg.replace(',', '.').toDoubleOrNull() ?: 0.0
    )

    companion object {
        fun clearedForScan(): NutritionIngredientFormState = NutritionIngredientFormState(
            calories = "0",
            protein = "0",
            carbs = "0",
            fat = "0",
            saturatedFat = "0",
            sugars = "0",
            fiber = "0",
            sodiumMg = "0"
        )

        fun fromScan(parsed: NutritionLabelParseResult): NutritionIngredientFormState {
            val values = NutritionLabelScannedFormValues.from(parsed)
            return NutritionIngredientFormState(
                calories = values.calories,
                protein = values.protein,
                carbs = values.carbs,
                fat = values.fat,
                saturatedFat = values.saturatedFat,
                sugars = values.sugars,
                fiber = values.fiber,
                sodiumMg = values.sodiumMg
            )
        }
    }
}

fun NutritionUiState.ingredientFormState(): NutritionIngredientFormState = NutritionIngredientFormState(
    calories = createCalories,
    protein = createProtein,
    carbs = createCarbs,
    fat = createFat,
    saturatedFat = createSaturatedFat,
    sugars = createSugars,
    fiber = createFiber,
    sodiumMg = createSodiumMg
)
