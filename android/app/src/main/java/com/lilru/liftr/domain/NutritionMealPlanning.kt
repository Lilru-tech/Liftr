package com.lilru.liftr.domain

data class NutritionMealPlanInviteUi(
    val targetId: String,
    val planId: String,
    val planDate: String,
    val mealSlot: String,
    val foodName: String,
    val quantityG: Double,
    val caloriesKcal: Double,
    val creatorUsername: String?
)

data class NutritionMealPlanItemUi(
    val targetId: String,
    val planId: String,
    val targetUserId: String,
    val mealSlot: String,
    val foodName: String,
    val quantityG: Double,
    val caloriesKcal: Double,
    val status: String,
    val isCreator: Boolean,
    val partnerLabel: String?,
    val partnerStatusLabel: String?
) {
    fun canMarkEaten(viewingUserId: String): Boolean =
        targetUserId == viewingUserId && status == "accepted"

    fun canDecline(viewingUserId: String): Boolean =
        targetUserId == viewingUserId && (status == "pending" || status == "accepted")
}
