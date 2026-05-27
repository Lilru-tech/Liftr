package com.lilru.liftr.ui.nutrition

data class NutritionMonthDayBalance(
    val mealLogCount: Int,
    val remainingCalories: Double
)

data class NutritionProfilePer100g(
    val calories: Double = 0.0,
    val protein: Double = 0.0,
    val carbs: Double = 0.0,
    val fat: Double = 0.0,
    val saturatedFat: Double = 0.0,
    val sugars: Double = 0.0,
    val fiber: Double = 0.0,
    val sodiumMg: Double = 0.0
)

fun NutritionIngredientWire.toProfilePer100g(): NutritionProfilePer100g = NutritionProfilePer100g(
    calories = caloriesPer100g,
    protein = proteinPer100g,
    carbs = carbsPer100g,
    fat = fatPer100g,
    saturatedFat = saturatedFatPer100g,
    sugars = sugarsPer100g,
    fiber = fiberPer100g,
    sodiumMg = sodiumMgPer100g
)

fun rollupProfilePer100g(lines: List<NutritionRecipeLineDraft>): NutritionProfilePer100g {
    var totalWeight = 0.0
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var saturatedFat = 0.0
    var sugars = 0.0
    var fiber = 0.0
    var sodiumMg = 0.0
    for (line in lines) {
        val w = line.weightG
        if (w <= 0) continue
        val p = line.ingredient.toProfilePer100g()
        totalWeight += w
        calories += w * p.calories / 100.0
        protein += w * p.protein / 100.0
        carbs += w * p.carbs / 100.0
        fat += w * p.fat / 100.0
        saturatedFat += w * p.saturatedFat / 100.0
        sugars += w * p.sugars / 100.0
        fiber += w * p.fiber / 100.0
        sodiumMg += w * p.sodiumMg / 100.0
    }
    if (totalWeight <= 0) return NutritionProfilePer100g()
    val scale = 100.0 / totalWeight
    return NutritionProfilePer100g(
        calories = calories * scale,
        protein = protein * scale,
        carbs = carbs * scale,
        fat = fat * scale,
        saturatedFat = saturatedFat * scale,
        sugars = sugars * scale,
        fiber = fiber * scale,
        sodiumMg = sodiumMg * scale
    )
}

object NutritionIngredientSelect {
    const val COLUMNS =
        "id,user_id,name,calories_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g," +
            "saturated_fat_per_100g,sugars_per_100g,fiber_per_100g,sodium_mg_per_100g,is_public"
}
