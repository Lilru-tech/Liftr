package com.lilru.liftr.ui.nutrition

import com.lilru.liftr.nutrition.NutritionLabelParseResult
import com.lilru.liftr.nutrition.NutritionLabelScannedFormValues
import kotlin.math.roundToInt

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

        fun fromIngredient(ingredient: NutritionIngredientWire): NutritionIngredientFormState =
            NutritionIngredientFormState(
                calories = formatField(ingredient.caloriesPer100g),
                protein = formatField(ingredient.proteinPer100g),
                carbs = formatField(ingredient.carbsPer100g),
                fat = formatField(ingredient.fatPer100g),
                saturatedFat = formatField(ingredient.saturatedFatPer100g),
                sugars = formatField(ingredient.sugarsPer100g),
                fiber = formatField(ingredient.fiberPer100g),
                sodiumMg = formatField(ingredient.sodiumMgPer100g)
            )

        private fun formatField(value: Double): String {
            val rounded = (value * 1000).roundToInt() / 1000.0
            return if (rounded == rounded.toLong().toDouble()) {
                rounded.toLong().toString()
            } else {
                rounded.toString()
            }
        }

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
