package com.lilru.liftr.ui.pets

object PetFoodItemType {
    val all = listOf("food_baby", "food_kid", "food_teen", "food_adult", "food_elder")

    fun displayName(itemType: String): String = when (itemType) {
        "food_baby" -> "Baby Snack"
        "food_kid" -> "Kid Cookies"
        "food_teen" -> "Teen Treat"
        "food_adult" -> "Adult Biscuit"
        "food_elder" -> "Elder Delight"
        else -> itemType.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }
}
