package com.lilru.liftr.ui.nutrition

import java.util.UUID
import kotlin.math.roundToInt

data class NutritionPlanAssigneeChip(
    val userId: String,
    val label: String
)

data class NutritionLogCartItem(
    val localId: String = UUID.randomUUID().toString(),
    val ingredientId: String? = null,
    val recipeId: String? = null,
    val displayName: String,
    val grams: Double,
    val loadingComposition: Boolean = false,
    val recipeLines: List<NutritionRecipeLineDraft> = emptyList(),
    val caloriesPer100g: Double = 0.0,
    val assignedUserIds: Set<String> = emptySet(),
    val perUserGrams: Map<String, Double> = emptyMap()
)

object NutritionLogCartLogic {
    const val MAX_ITEMS = 20

    fun clampGrams(grams: Double): Double = grams.coerceIn(5.0, 2000.0)

    fun cartContainsIngredient(cart: List<NutritionLogCartItem>, ingredientId: String): Boolean =
        cart.any { it.ingredientId == ingredientId }

    fun cartContainsRecipe(cart: List<NutritionLogCartItem>, recipeId: String): Boolean =
        cart.any { it.recipeId == recipeId }

    fun removeIngredient(cart: List<NutritionLogCartItem>, ingredientId: String): List<NutritionLogCartItem> =
        cart.filter { it.ingredientId != ingredientId }

    fun removeRecipe(cart: List<NutritionLogCartItem>, recipeId: String): List<NutritionLogCartItem> =
        cart.filter { it.recipeId != recipeId }

    fun removeByLocalId(cart: List<NutritionLogCartItem>, localId: String): List<NutritionLogCartItem> =
        cart.filter { it.localId != localId }

    fun updateGrams(cart: List<NutritionLogCartItem>, localId: String, grams: Double): List<NutritionLogCartItem> =
        cart.map { item ->
            if (item.localId == localId) item.copy(grams = clampGrams(grams)) else item
        }

    fun updatePerUserGrams(
        cart: List<NutritionLogCartItem>,
        localId: String,
        userId: String,
        grams: Double
    ): List<NutritionLogCartItem> =
        cart.map { item ->
            if (item.localId != localId) return@map item
            val next = item.perUserGrams.toMutableMap()
            next[userId] = clampGrams(grams)
            item.copy(perUserGrams = next)
        }

    fun gramsForUser(item: NutritionLogCartItem, userId: String): Double =
        item.perUserGrams[userId] ?: item.grams

    fun toggleAssignee(
        cart: List<NutritionLogCartItem>,
        localId: String,
        userId: String,
        fallbackUserId: String
    ): List<NutritionLogCartItem> =
        cart.map { item ->
            if (item.localId != localId) return@map item
            val next = item.assignedUserIds.toMutableSet()
            if (next.contains(userId)) {
                next.remove(userId)
                val nextGrams = item.perUserGrams.toMutableMap()
                nextGrams.remove(userId)
                val ensured = if (next.isEmpty()) setOf(fallbackUserId) else next
                item.copy(assignedUserIds = ensured, perUserGrams = nextGrams)
            } else {
                next.add(userId)
                item.copy(assignedUserIds = next)
            }
        }

    fun lineKcal(item: NutritionLogCartItem): Double? {
        if (item.loadingComposition) return null
        return when {
            item.ingredientId != null -> item.grams * item.caloriesPer100g / 100.0
            item.recipeLines.isNotEmpty() -> {
                val profile = rollupProfilePer100g(item.recipeLines)
                item.grams * profile.calories / 100.0
            }
            else -> null
        }
    }

    fun totalKcal(cart: List<NutritionLogCartItem>): Int =
        cart.mapNotNull { lineKcal(it) }.sumOf { it.roundToInt() }

    fun canSave(cart: List<NutritionLogCartItem>, saving: Boolean): Boolean =
        !saving && cart.isNotEmpty() && cart.none { it.loadingComposition }
}
