package com.lilru.liftr.ui.nutrition

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NutritionLogCartTest {

    private fun ingredient(id: String, name: String = "Chicken", kcal: Double = 200.0) =
        NutritionLogCartItem(
            ingredientId = id,
            displayName = name,
            grams = 100.0,
            caloriesPer100g = kcal
        )

    @Test
    fun cartContainsIngredient_detectsMembership() {
        val cart = listOf(ingredient("a"), ingredient("b"))
        assertTrue(NutritionLogCartLogic.cartContainsIngredient(cart, "a"))
        assertFalse(NutritionLogCartLogic.cartContainsIngredient(cart, "z"))
    }

    @Test
    fun removeIngredient_dropsMatchingRow() {
        val cart = listOf(ingredient("a"), ingredient("b"))
        val next = NutritionLogCartLogic.removeIngredient(cart, "a")
        assertEquals(1, next.size)
        assertEquals("b", next.first().ingredientId)
    }

    @Test
    fun updateGrams_clampsToValidRange() {
        val item = ingredient("a")
        val updated = NutritionLogCartLogic.updateGrams(listOf(item), item.localId, 9999.0)
        assertEquals(2000.0, updated.first().grams, 0.001)
        val low = NutritionLogCartLogic.updateGrams(listOf(item), item.localId, 1.0)
        assertEquals(5.0, low.first().grams, 0.001)
    }

    @Test
    fun lineKcal_ingredientUsesPer100g() {
        val item = ingredient("a", kcal = 150.0)
        assertEquals(150.0, NutritionLogCartLogic.lineKcal(item)!!, 0.001)
    }

    @Test
    fun canSave_requiresNonEmptyAndNotLoading() {
        val loading = NutritionLogCartItem(
            recipeId = "r1",
            displayName = "Meal",
            grams = 100.0,
            loadingComposition = true
        )
        assertFalse(NutritionLogCartLogic.canSave(listOf(loading), saving = false))
        assertTrue(NutritionLogCartLogic.canSave(listOf(ingredient("a")), saving = false))
        assertFalse(NutritionLogCartLogic.canSave(listOf(ingredient("a")), saving = true))
    }

    @Test
    fun gramsForUser_usesOverrideWhenPresent() {
        val item = ingredient("a").copy(
            grams = 100.0,
            perUserGrams = mapOf("user-b" to 150.0)
        )
        assertEquals(100.0, NutritionLogCartLogic.gramsForUser(item, "user-a"), 0.001)
        assertEquals(150.0, NutritionLogCartLogic.gramsForUser(item, "user-b"), 0.001)
    }

    @Test
    fun updatePerUserGrams_storesPerAssignee() {
        val item = ingredient("a")
        val updated = NutritionLogCartLogic.updatePerUserGrams(listOf(item), item.localId, "partner", 120.0)
        assertEquals(120.0, NutritionLogCartLogic.gramsForUser(updated.first(), "partner"), 0.001)
    }

    @Test
    fun toggleAssignee_keepsAtLeastSelfWhenEmpty() {
        val item = ingredient("a").copy(assignedUserIds = setOf("self", "partner"))
        val next = NutritionLogCartLogic.toggleAssignee(listOf(item), item.localId, "partner", "self")
        assertFalse(next.first().assignedUserIds.contains("partner"))
        assertTrue(next.first().assignedUserIds.contains("self"))
    }

    @Test
    fun totalKcal_sumsLinePreviews() {
        val cart = listOf(
            ingredient("a", kcal = 100.0),
            ingredient("b", kcal = 200.0)
        )
        assertEquals(300, NutritionLogCartLogic.totalKcal(cart))
    }
}
