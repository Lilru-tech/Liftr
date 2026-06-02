package com.lilru.liftr.ui.nutrition

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.SupabaseResponseDecoding
import com.lilru.liftr.domain.NutritionMealPlanInviteUi
import com.lilru.liftr.domain.NutritionMealPlanItemUi
import com.lilru.liftr.nutrition.NutritionLabelParseResult
import com.lilru.liftr.nutrition.NutritionLabelParser
import com.lilru.liftr.nutrition.NutritionLabelScannedFormValues
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.temporal.ChronoUnit
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

data class NutritionDiaryItemUi(
    val id: String,
    val mealSlot: String,
    val name: String,
    val quantityG: Double,
    val caloriesKcal: Double,
    val isRecipe: Boolean
)

data class NutritionRecommendationUi(
    val baseCaloriesTarget: Double,
    val consumed: Double,
    val burned: Double,
    val remaining: Double,
    val net: Double,
    val proteinG: Double,
    val carbsG: Double,
    val fatG: Double,
    val saturatedFatG: Double,
    val sugarsG: Double,
    val fiberG: Double,
    val sodiumMg: Double,
    val recommendationText: String
)

data class SmartNutritionRecommendationUi(
    val recommendationText: String,
    val alerts: List<String>,
    val avgDailyConsumedKcal: Double,
    val avgDailyBurnedKcal: Double,
    val baseCaloriesTarget: Double,
    val avgDailyEnergyOut: Double,
    val avgDailyRemainingBudget: Double
)

enum class NutritionInsightsQuickPreset {
    ONE_DAY,
    ONE_WEEK,
    ONE_MONTH
}

data class NutritionRecipeLineDraft(
    val ingredient: NutritionIngredientWire,
    val weightG: Double
)

sealed class NutritionOverlay {
    data object None : NutritionOverlay()
    data object AddFood : NutritionOverlay()
    data object CreateIngredient : NutritionOverlay()
    data object CreateRecipe : NutritionOverlay()
    data class EditLog(val item: NutritionDiaryItemUi) : NutritionOverlay()
    data class EditPlannedMeal(val item: NutritionMealPlanItemUi) : NutritionOverlay()
}

enum class NutritionListScope {
    ALL,
    MINE,
    FAVORITES
}

sealed class NutritionLogNestedOverlay {
    data object None : NutritionLogNestedOverlay()
    data object CreateIngredient : NutritionLogNestedOverlay()
    data object CreateRecipe : NutritionLogNestedOverlay()
    data object EditRecipe : NutritionLogNestedOverlay()
    data object EditIngredient : NutritionLogNestedOverlay()
}

data class NutritionUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val selectedDate: LocalDate = LocalDate.now(),
    val month: YearMonth = YearMonth.now(),
    val monthDayBalance: Map<LocalDate, NutritionMonthDayBalance> = emptyMap(),
    val recommendation: NutritionRecommendationUi? = null,
    val diaryByMeal: Map<String, List<NutritionDiaryItemUi>> = emptyMap(),
    val overlay: NutritionOverlay = NutritionOverlay.None,
    val addSearchQuery: String = "",
    val addModeIngredient: Boolean = true,
    val addListScope: NutritionListScope = NutritionListScope.ALL,
    val favoriteIngredientIds: Set<String> = emptySet(),
    val favoriteRecipeIds: Set<String> = emptySet(),
    val searchLoading: Boolean = false,
    val ingredientResults: List<NutritionIngredientWire> = emptyList(),
    val ingredientCanLoadMore: Boolean = false,
    val ingredientLoadingMore: Boolean = false,
    val ingredientCatalogPage: Int = 0,
    val recipeResults: List<NutritionRecipeWire> = emptyList(),
    val logCart: List<NutritionLogCartItem> = emptyList(),
    val logCartFocusedLocalId: String? = null,
    val addMealSlot: String = BackendContracts.NutritionMealSlots.LUNCH,
    val saving: Boolean = false,
    val createName: String = "",
    val recipeName: String = "",
    val recipeDescription: String = "",
    val logFoodNestedOverlay: NutritionLogNestedOverlay = NutritionLogNestedOverlay.None,
    val createCalories: String = "100",
    val createProtein: String = "0",
    val createCarbs: String = "0",
    val createFat: String = "0",
    val createSaturatedFat: String = "0",
    val createSugars: String = "0",
    val createFiber: String = "0",
    val createSodiumMg: String = "0",
    val microExpanded: Boolean = false,
    val recipeLines: List<NutritionRecipeLineDraft> = emptyList(),
    val recipePickQuery: String = "",
    val recipePickResults: List<NutritionIngredientWire> = emptyList(),
    val recipePickIngredientId: String? = null,
    val recipePickGrams: Double = 100.0,
    val editingRecipeId: String? = null,
    val editingIngredientId: String? = null,
    val recipeEditorLoading: Boolean = false,
    val editGrams: Double = 100.0,
    val editMealSlot: String = BackendContracts.NutritionMealSlots.LUNCH,
    val insightsFromDate: LocalDate = LocalDate.now().minusDays(6),
    val insightsToDate: LocalDate = LocalDate.now(),
    val insightsQuickPreset: NutritionInsightsQuickPreset? = NutritionInsightsQuickPreset.ONE_WEEK,
    val smartInsightsLoading: Boolean = false,
    val smartInsights: SmartNutritionRecommendationUi? = null,
    val smartInsightsError: String? = null,
    val addFoodIsPlan: Boolean = false,
    val planDate: LocalDate = LocalDate.now().plusDays(1),
    val followingForPlan: List<FollowingProfileWire> = emptyList(),
    val selectedPlanPartners: List<FollowingProfileWire> = emptyList(),
    val showPlanParticipantsPicker: Boolean = false,
    val pendingInvites: List<NutritionMealPlanInviteUi> = emptyList(),
    val plannedItems: List<NutritionMealPlanItemUi> = emptyList()
)

@Serializable
private data class NutritionDiaryLogWire(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("log_date") val logDate: String,
    @SerialName("meal_slot") val mealSlot: String,
    @SerialName("ingredient_id") val ingredientId: String? = null,
    @SerialName("recipe_id") val recipeId: String? = null,
    @SerialName("quantity_g") val quantityG: Double
)

@Serializable
data class NutritionIngredientWire(
    val id: String,
    @SerialName("user_id") val userId: String? = null,
    val name: String,
    @SerialName("calories_per_100g") val caloriesPer100g: Double,
    @SerialName("protein_per_100g") val proteinPer100g: Double = 0.0,
    @SerialName("carbs_per_100g") val carbsPer100g: Double = 0.0,
    @SerialName("fat_per_100g") val fatPer100g: Double = 0.0,
    @SerialName("saturated_fat_per_100g") val saturatedFatPer100g: Double = 0.0,
    @SerialName("sugars_per_100g") val sugarsPer100g: Double = 0.0,
    @SerialName("fiber_per_100g") val fiberPer100g: Double = 0.0,
    @SerialName("sodium_mg_per_100g") val sodiumMgPer100g: Double = 0.0,
    @SerialName("is_public") val isPublic: Boolean = false
)

@Serializable
data class NutritionRecipeWire(
    val id: String,
    @SerialName("user_id") val userId: String? = null,
    val name: String,
    val description: String? = null
)

@Serializable
private data class FavoriteIngredientWire(
    @SerialName("ingredient_id") val ingredientId: String
)

@Serializable
data class FollowingProfileWire(
    @SerialName("user_id") val userId: String,
    val username: String? = null
)

@Serializable
private data class MealPlanWire(
    val id: String,
    @SerialName("creator_id") val creatorId: String,
    @SerialName("plan_date") val planDate: String,
    @SerialName("meal_slot") val mealSlot: String,
    @SerialName("recipe_id") val recipeId: String? = null,
    @SerialName("ingredient_id") val ingredientId: String? = null
)

@Serializable
private data class MealPlanTargetWire(
    val id: String,
    @SerialName("plan_id") val planId: String,
    @SerialName("target_user_id") val targetUserId: String,
    @SerialName("quantity_g") val quantityG: Double,
    val status: String,
    @SerialName("ingredient_id") val ingredientId: String? = null,
    @SerialName("recipe_id") val recipeId: String? = null
)

private const val MEAL_PLAN_TARGET_SELECT =
    "id,plan_id,target_user_id,quantity_g,status,ingredient_id,recipe_id"

@Serializable
private data class FollowRowWire(
    @SerialName("followee_id") val followeeId: String
)

@Serializable
private data class IdNameRow(val id: String, val name: String)

@Serializable
private data class IngredientCaloriesRow(
    val id: String,
    @SerialName("calories_per_100g") val caloriesPer100g: Double
)

@Serializable
private data class FavoriteRecipeWire(
    @SerialName("recipe_id") val recipeId: String
)

@Serializable
private data class NutritionRecipeIngredientWire(
    val id: String,
    @SerialName("recipe_id") val recipeId: String,
    @SerialName("ingredient_id") val ingredientId: String,
    @SerialName("weight_g") val weightG: Double
)

@Serializable
private data class DailyNutritionRecommendationWire(
    @SerialName("base_calories_target") val baseCaloriesTarget: Double = BackendContracts.NutritionDisplayTargets.CALORIES_KCAL,
    @SerialName("total_calories_consumed") val totalCaloriesConsumed: Double,
    @SerialName("total_calories_burned_active") val totalCaloriesBurnedActive: Double,
    @SerialName("remaining_calories") val remainingCalories: Double? = null,
    @SerialName("net_calories_balance") val netCaloriesBalance: Double? = null,
    @SerialName("total_protein_g_consumed") val totalProteinGConsumed: Double = 0.0,
    @SerialName("total_carbs_g_consumed") val totalCarbsGConsumed: Double = 0.0,
    @SerialName("total_fat_g_consumed") val totalFatGConsumed: Double = 0.0,
    @SerialName("total_saturated_fat_g_consumed") val totalSaturatedFatGConsumed: Double = 0.0,
    @SerialName("total_sugars_g_consumed") val totalSugarsGConsumed: Double = 0.0,
    @SerialName("total_fiber_g_consumed") val totalFiberGConsumed: Double = 0.0,
    @SerialName("total_sodium_mg_consumed") val totalSodiumMgConsumed: Double = 0.0,
    @SerialName("recommendation_text") val recommendationText: String
)

@Serializable
private data class SmartNutritionRecommendationWire(
    @SerialName(BackendContracts.NutritionRpcKeys.RECOMMENDATION_TEXT) val recommendationText: String,
    @SerialName(BackendContracts.NutritionRpcKeys.ALERTS) val alerts: List<String> = emptyList(),
    @SerialName(BackendContracts.NutritionRpcKeys.AVG_DAILY_CONSUMED_KCAL) val avgDailyConsumedKcal: Double,
    @SerialName(BackendContracts.NutritionRpcKeys.AVG_DAILY_BURNED_KCAL) val avgDailyBurnedKcal: Double,
    @SerialName(BackendContracts.NutritionRpcKeys.BASE_CALORIES_TARGET) val baseCaloriesTarget: Double? = null,
    @SerialName(BackendContracts.NutritionRpcKeys.AVG_DAILY_ENERGY_OUT) val avgDailyEnergyOut: Double? = null,
    @SerialName(BackendContracts.NutritionRpcKeys.AVG_DAILY_REMAINING_BUDGET) val avgDailyRemainingBudget: Double? = null
)

@Serializable
private data class NutritionMonthBalanceWire(
    @SerialName("log_date") val logDate: String,
    @SerialName("meal_log_count") val mealLogCount: Int,
    @SerialName("remaining_calories") val remainingCalories: Double
)

class NutritionViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    companion object {
        const val MAX_INSIGHTS_SPAN_DAYS = 70
        private const val ingredientPageSize = 50
    }

    private val dateFormatter = DateTimeFormatter.ISO_LOCAL_DATE
    private val _uiState = MutableStateFlow(NutritionUiState())
    val uiState: StateFlow<NutritionUiState> = _uiState.asStateFlow()

    val mealSlotOrder: List<String> = listOf(
        BackendContracts.NutritionMealSlots.BREAKFAST,
        BackendContracts.NutritionMealSlots.LUNCH,
        BackendContracts.NutritionMealSlots.DINNER,
        BackendContracts.NutritionMealSlots.SNACK
    )

    init { refresh() }

    fun setSelectedDate(date: LocalDate) {
        _uiState.update { it.copy(selectedDate = date) }
        refresh()
    }

    fun shiftMonth(delta: Int) {
        _uiState.update { it.copy(month = it.month.plusMonths(delta.toLong())) }
        refresh()
    }

    fun goToday() {
        val today = LocalDate.now()
        _uiState.update { it.copy(selectedDate = today, month = YearMonth.from(today)) }
        refresh()
    }

    fun openAddFood(mealSlot: String = BackendContracts.NutritionMealSlots.LUNCH, plan: Boolean = false) {
        _uiState.update {
            it.copy(
                overlay = NutritionOverlay.AddFood,
                error = null,
                addSearchQuery = "",
                logCart = emptyList(),
                logCartFocusedLocalId = null,
                addMealSlot = mealSlot,
                addFoodIsPlan = plan,
                planDate = LocalDate.now().plusDays(1),
                selectedPlanPartners = emptyList(),
                showPlanParticipantsPicker = false,
                logFoodNestedOverlay = NutritionLogNestedOverlay.None
            )
        }
        onAddFoodOpened()
    }

    fun setPlanDate(date: LocalDate) {
        _uiState.update { it.copy(planDate = date) }
    }

    fun setShowPlanParticipantsPicker(show: Boolean) {
        _uiState.update { it.copy(showPlanParticipantsPicker = show) }
    }

    fun addPlanPartners(profiles: List<FollowingProfileWire>) {
        _uiState.update { state ->
            val merged = state.selectedPlanPartners.toMutableList()
            for (profile in profiles) {
                if (merged.none { it.userId == profile.userId }) merged.add(profile)
            }
            state.copy(selectedPlanPartners = merged, showPlanParticipantsPicker = false)
        }
    }

    fun removePlanPartner(userId: String) {
        _uiState.update { state ->
            state.copy(selectedPlanPartners = state.selectedPlanPartners.filter { it.userId != userId })
        }
    }

    fun acceptMealPlanInvite(targetId: String) {
        viewModelScope.launch {
            runCatching {
                supabase.postgrest.rpc(
                    BackendContracts.Rpc.ACCEPT_MEAL_PLAN,
                    buildJsonObject { put("p_target_id", targetId) }
                )
                refresh()
            }.onFailure { e -> setErr(mealPlanErrorMessage(e)) }
        }
    }

    fun rejectMealPlanInvite(targetId: String) {
        viewModelScope.launch {
            runCatching {
                supabase.postgrest.rpc(
                    BackendContracts.Rpc.REJECT_MEAL_PLAN,
                    buildJsonObject { put("p_target_id", targetId) }
                )
                refresh()
            }.onFailure { e -> setErr(mealPlanErrorMessage(e)) }
        }
    }

    fun completePlannedMeal(targetId: String) {
        viewModelScope.launch {
            runCatching {
                supabase.postgrest.rpc(
                    BackendContracts.Rpc.COMPLETE_MEAL_PLAN_AS_EATEN,
                    buildJsonObject { put("p_target_id", targetId) }
                )
                refresh()
            }.onFailure { e -> setErr(mealPlanErrorMessage(e)) }
        }
    }

    fun savePlannedMeal(targetId: String) {
        viewModelScope.launch {
            val s = _uiState.value
            _uiState.update { it.copy(saving = true, error = null) }
            runCatching {
                supabase.postgrest.rpc(
                    BackendContracts.Rpc.UPDATE_MEAL_PLAN_TARGET,
                    buildJsonObject {
                        put("p_target_id", targetId)
                        put("p_quantity_g", NutritionLogCartLogic.clampGrams(s.editGrams))
                        put("p_meal_slot", s.editMealSlot)
                    }
                )
                dismissOverlay()
            }.onFailure { e ->
                _uiState.update { it.copy(saving = false, error = mealPlanErrorMessage(e)) }
            }
        }
    }

    fun toggleCartAssignee(localId: String, userId: String) {
        val selfId = supabase.auth.currentUserOrNull()?.id ?: return
        _uiState.update {
            it.copy(
                logCart = NutritionLogCartLogic.toggleAssignee(it.logCart, localId, userId, selfId)
            )
        }
    }

    private fun planDefaultAssigneeIds(userId: String, state: NutritionUiState): Set<String> {
        val ids = state.selectedPlanPartners.map { it.userId }.toMutableSet()
        ids.add(userId)
        return ids
    }

    private fun mealPlanErrorMessage(e: Throwable): String {
        val text = e.message.orEmpty()
        return when {
            text.contains("INVITEE_MAY_ONLY_UPDATE", ignoreCase = true) ->
                "Could not save your planned meal. Please try again."
            text.contains("FORBIDDEN", ignoreCase = true) || text.contains("42501") ->
                "You can only update your own planned meal."
            text.contains("INVALID_STATUS", ignoreCase = true) ->
                "This meal plan can no longer be changed."
            else -> text.take(300).ifBlank { "Something went wrong." }
        }
    }

    fun setOverlay(overlay: NutritionOverlay) {
        if (overlay is NutritionOverlay.AddFood) {
            openAddFood(_uiState.value.addMealSlot)
            return
        }
        val preserveAddFood = _uiState.value.overlay is NutritionOverlay.AddFood &&
            (overlay is NutritionOverlay.CreateIngredient || overlay is NutritionOverlay.CreateRecipe)
        _uiState.update {
            val base = if (preserveAddFood) {
                it.copy(overlay = overlay, error = null, logFoodNestedOverlay = when (overlay) {
                    NutritionOverlay.CreateIngredient -> NutritionLogNestedOverlay.CreateIngredient
                    NutritionOverlay.CreateRecipe -> NutritionLogNestedOverlay.CreateRecipe
                    else -> it.logFoodNestedOverlay
                })
            } else {
                it.copy(
                    overlay = overlay,
                    error = null,
                    addSearchQuery = "",
                    logCart = emptyList(),
                    logCartFocusedLocalId = null,
                    logFoodNestedOverlay = NutritionLogNestedOverlay.None
                )
            }
            base
        }
        if (overlay is NutritionOverlay.CreateRecipe) {
            searchAddCatalog()
            _uiState.update {
                it.copy(
                    recipeName = "",
                    recipeLines = emptyList(),
                    recipePickQuery = "",
                    recipePickIngredientId = null,
                    recipePickGrams = 100.0
                )
            }
            searchRecipePick()
        }
        if (overlay is NutritionOverlay.EditLog) {
            val item = overlay.item
            _uiState.update {
                it.copy(editGrams = item.quantityG, editMealSlot = item.mealSlot)
            }
        }
        if (overlay is NutritionOverlay.EditPlannedMeal) {
            val item = overlay.item
            _uiState.update {
                it.copy(editGrams = item.quantityG, editMealSlot = item.mealSlot)
            }
        }
    }

    fun dismissOverlay() {
        _uiState.update {
            it.copy(
                overlay = NutritionOverlay.None,
                logFoodNestedOverlay = NutritionLogNestedOverlay.None,
                logCart = emptyList(),
                logCartFocusedLocalId = null
            )
        }
        refresh()
    }

    fun dismissLogFoodNestedOverlay() {
        _uiState.update {
            it.copy(
                logFoodNestedOverlay = NutritionLogNestedOverlay.None,
                overlay = NutritionOverlay.AddFood,
                editingRecipeId = null,
                editingIngredientId = null,
                recipeEditorLoading = false
            )
        }
        searchAddCatalog()
    }

    fun setLogFoodNestedOverlay(nested: NutritionLogNestedOverlay) {
        _uiState.update { it.copy(logFoodNestedOverlay = nested) }
        when (nested) {
            NutritionLogNestedOverlay.CreateRecipe -> {
                _uiState.update {
                    it.copy(
                        editingRecipeId = null,
                        recipeEditorLoading = false,
                        recipeName = "",
                        recipeDescription = "",
                        recipeLines = emptyList(),
                        recipePickQuery = "",
                        recipePickIngredientId = null,
                        recipePickGrams = 100.0
                    )
                }
                searchRecipePick()
            }
            NutritionLogNestedOverlay.CreateIngredient -> {
                _uiState.update { it.copy(editingIngredientId = null) }
            }
            NutritionLogNestedOverlay.EditRecipe -> Unit
            NutritionLogNestedOverlay.EditIngredient -> Unit
            NutritionLogNestedOverlay.None -> Unit
        }
    }

    fun openEditIngredient(ingredientId: String) {
        val ingredient = _uiState.value.ingredientResults.find { it.id == ingredientId } ?: return
        val form = NutritionIngredientFormState.fromIngredient(ingredient)
        _uiState.update {
            it.copy(
                logFoodNestedOverlay = NutritionLogNestedOverlay.EditIngredient,
                editingIngredientId = ingredientId,
                createName = ingredient.name,
                createCalories = form.calories,
                createProtein = form.protein,
                createCarbs = form.carbs,
                createFat = form.fat,
                createSaturatedFat = form.saturatedFat,
                createSugars = form.sugars,
                createFiber = form.fiber,
                createSodiumMg = form.sodiumMg
            )
        }
    }

    fun openEditRecipe(recipeId: String) {
        val recipe = _uiState.value.recipeResults.find { it.id == recipeId } ?: return
        _uiState.update {
            it.copy(
                logFoodNestedOverlay = NutritionLogNestedOverlay.EditRecipe,
                editingRecipeId = recipeId,
                recipeName = recipe.name,
                recipeDescription = recipe.description.orEmpty(),
                recipeLines = emptyList(),
                recipeEditorLoading = true,
                recipePickQuery = "",
                recipePickIngredientId = null,
                recipePickGrams = 100.0
            )
        }
        viewModelScope.launch {
            runCatching {
                val lines = fetchRecipeLines(recipeId)
                _uiState.update { state ->
                    if (state.editingRecipeId != recipeId) state
                    else state.copy(recipeLines = lines, recipeEditorLoading = false)
                }
            }.onFailure {
                _uiState.update { state ->
                    if (state.editingRecipeId == recipeId) {
                        state.copy(recipeLines = emptyList(), recipeEditorLoading = false)
                    } else state
                }
            }
            searchRecipePick()
        }
    }

    fun onAddFoodOpened() {
        viewModelScope.launch {
            runCatching { loadNutritionFavoriteIds() }
            if (_uiState.value.addFoodIsPlan) {
                runCatching { loadFollowingForPlan() }
            }
            searchAddCatalog()
        }
    }

    fun setAddListScope(scope: NutritionListScope) {
        _uiState.update { it.copy(addListScope = scope) }
        searchAddCatalog()
    }

    fun toggleFavoriteIngredient(ingredientId: String) {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return
        val had = _uiState.value.favoriteIngredientIds.contains(ingredientId)
        _uiState.update {
            it.copy(
                favoriteIngredientIds = if (had) {
                    it.favoriteIngredientIds - ingredientId
                } else {
                    it.favoriteIngredientIds + ingredientId
                },
                ingredientResults = if (had && it.addListScope == NutritionListScope.FAVORITES) {
                    it.ingredientResults.filter { row -> row.id != ingredientId }
                } else {
                    it.ingredientResults
                }
            )
        }
        viewModelScope.launch {
            runCatching {
                if (had) {
                    supabase.from(BackendContracts.Tables.USER_FAVORITE_NUTRITION_INGREDIENTS).delete {
                        filter {
                            eq("user_id", userId)
                            eq("ingredient_id", ingredientId)
                        }
                    }
                } else {
                    val row = buildJsonObject {
                        put("user_id", userId)
                        put("ingredient_id", ingredientId)
                    }
                    supabase.from(BackendContracts.Tables.USER_FAVORITE_NUTRITION_INGREDIENTS).insert(row) { }
                }
            }.onFailure { e ->
                _uiState.update {
                    it.copy(
                        favoriteIngredientIds = if (had) {
                            it.favoriteIngredientIds + ingredientId
                        } else {
                            it.favoriteIngredientIds - ingredientId
                        },
                        error = e.message?.take(300) ?: e::class.java.simpleName
                    )
                }
            }
        }
    }

    fun toggleFavoriteRecipe(recipeId: String) {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return
        val had = _uiState.value.favoriteRecipeIds.contains(recipeId)
        _uiState.update {
            it.copy(
                favoriteRecipeIds = if (had) {
                    it.favoriteRecipeIds - recipeId
                } else {
                    it.favoriteRecipeIds + recipeId
                },
                recipeResults = if (had && it.addListScope == NutritionListScope.FAVORITES) {
                    it.recipeResults.filter { row -> row.id != recipeId }
                } else {
                    it.recipeResults
                }
            )
        }
        viewModelScope.launch {
            runCatching {
                if (had) {
                    supabase.from(BackendContracts.Tables.USER_FAVORITE_NUTRITION_RECIPES).delete {
                        filter {
                            eq("user_id", userId)
                            eq("recipe_id", recipeId)
                        }
                    }
                } else {
                    val row = buildJsonObject {
                        put("user_id", userId)
                        put("recipe_id", recipeId)
                    }
                    supabase.from(BackendContracts.Tables.USER_FAVORITE_NUTRITION_RECIPES).insert(row) { }
                }
            }.onFailure { e ->
                _uiState.update {
                    it.copy(
                        favoriteRecipeIds = if (had) {
                            it.favoriteRecipeIds + recipeId
                        } else {
                            it.favoriteRecipeIds - recipeId
                        },
                        error = e.message?.take(300) ?: e::class.java.simpleName
                    )
                }
            }
        }
    }

    private suspend fun loadNutritionFavoriteIds() {
        val ingRes = supabase.from(BackendContracts.Tables.USER_FAVORITE_NUTRITION_INGREDIENTS)
            .select(columns = Columns.raw("ingredient_id")) { }
        val recRes = supabase.from(BackendContracts.Tables.USER_FAVORITE_NUTRITION_RECIPES)
            .select(columns = Columns.raw("recipe_id")) { }
        val ingIds = SupabaseResponseDecoding.decodeListOrObject<FavoriteIngredientWire>(ingRes.data)
            .map { it.ingredientId }
            .toSet()
        val recIds = SupabaseResponseDecoding.decodeListOrObject<FavoriteRecipeWire>(recRes.data)
            .map { it.recipeId }
            .toSet()
        _uiState.update { it.copy(favoriteIngredientIds = ingIds, favoriteRecipeIds = recIds) }
    }

    fun setAddModeIngredient(ingredient: Boolean) {
        _uiState.update { it.copy(addModeIngredient = ingredient) }
        searchAddCatalog()
    }

    fun setAddSearchQuery(query: String) {
        _uiState.update { it.copy(addSearchQuery = query) }
        searchAddCatalog()
    }

    fun toggleCartIngredient(id: String) {
        val state = _uiState.value
        val ing = state.ingredientResults.find { it.id == id } ?: return
        if (NutritionLogCartLogic.cartContainsIngredient(state.logCart, id)) {
            _uiState.update {
                it.copy(
                    logCart = NutritionLogCartLogic.removeIngredient(it.logCart, id),
                    logCartFocusedLocalId = null
                )
            }
            return
        }
        if (state.logCart.size >= NutritionLogCartLogic.MAX_ITEMS) {
            setErr("You can add up to ${NutritionLogCartLogic.MAX_ITEMS} items at once.")
            return
        }
        val userId = supabase.auth.currentUserOrNull()?.id
        val assignees = userId?.let { planDefaultAssigneeIds(it, state) } ?: emptySet()
        val item = NutritionLogCartItem(
            ingredientId = id,
            displayName = ing.name,
            grams = 100.0,
            caloriesPer100g = ing.caloriesPer100g,
            assignedUserIds = assignees
        )
        _uiState.update { it.copy(logCart = it.logCart + item, logCartFocusedLocalId = item.localId) }
    }

    fun toggleCartRecipe(id: String) {
        val state = _uiState.value
        if (NutritionLogCartLogic.cartContainsRecipe(state.logCart, id)) {
            _uiState.update {
                it.copy(
                    logCart = NutritionLogCartLogic.removeRecipe(it.logCart, id),
                    logCartFocusedLocalId = null
                )
            }
            return
        }
        if (state.logCart.size >= NutritionLogCartLogic.MAX_ITEMS) {
            setErr("You can add up to ${NutritionLogCartLogic.MAX_ITEMS} items at once.")
            return
        }
        val recipe = state.recipeResults.find { it.id == id } ?: return
        val localId = java.util.UUID.randomUUID().toString()
        val userId = supabase.auth.currentUserOrNull()?.id
        val assignees = userId?.let { planDefaultAssigneeIds(it, state) } ?: emptySet()
        val placeholder = NutritionLogCartItem(
            localId = localId,
            recipeId = id,
            displayName = recipe.name,
            grams = 100.0,
            loadingComposition = true,
            assignedUserIds = assignees
        )
        _uiState.update { it.copy(logCart = it.logCart + placeholder, logCartFocusedLocalId = localId) }
        viewModelScope.launch {
            runCatching {
                val lines = fetchRecipeLines(id)
                val total = lines.sumOf { it.weightG }
                _uiState.update { s ->
                    if (!s.logCart.any { it.localId == localId }) return@update s
                    s.copy(
                        logCart = s.logCart.map { item ->
                            if (item.localId == localId) {
                                item.copy(
                                    loadingComposition = false,
                                    recipeLines = lines,
                                    grams = if (total > 0) total else 100.0
                                )
                            } else item
                        }
                    )
                }
            }.onFailure { e ->
                _uiState.update { s ->
                    s.copy(
                        logCart = s.logCart.filter { it.localId != localId },
                        error = e.message?.take(300) ?: e::class.java.simpleName
                    )
                }
            }
        }
    }

    fun updateCartItemGrams(localId: String, grams: Double) {
        _uiState.update {
            it.copy(logCart = NutritionLogCartLogic.updateGrams(it.logCart, localId, grams))
        }
    }

    fun updateCartPerUserGrams(localId: String, userId: String, grams: Double) {
        _uiState.update {
            it.copy(logCart = NutritionLogCartLogic.updatePerUserGrams(it.logCart, localId, userId, grams))
        }
    }

    fun removeCartItem(localId: String) {
        _uiState.update {
            it.copy(
                logCart = NutritionLogCartLogic.removeByLocalId(it.logCart, localId),
                logCartFocusedLocalId = if (it.logCartFocusedLocalId == localId) null else it.logCartFocusedLocalId
            )
        }
    }

    fun setRecipePickGrams(value: Double) {
        _uiState.update { it.copy(recipePickGrams = value.coerceAtMost(2000.0)) }
    }

    fun setAddMealSlot(slot: String) {
        _uiState.update { it.copy(addMealSlot = slot) }
    }

    fun setRecipeName(name: String) {
        _uiState.update { it.copy(recipeName = name) }
    }

    fun setRecipeDescription(description: String) {
        _uiState.update { it.copy(recipeDescription = description) }
    }

    fun clearLogCart() {
        _uiState.update { it.copy(logCart = emptyList(), logCartFocusedLocalId = null) }
    }

    private fun removeCatalogItemFromCart(ingredientId: String? = null, recipeId: String? = null) {
        _uiState.update { state ->
            var cart = state.logCart
            ingredientId?.let { cart = NutritionLogCartLogic.removeIngredient(cart, it) }
            recipeId?.let { cart = NutritionLogCartLogic.removeRecipe(cart, it) }
            state.copy(logCart = cart, logCartFocusedLocalId = null)
        }
    }

    fun addRecipeLineFromIngredient(ingredientId: String) {
        val state = _uiState.value
        val ing = state.recipePickResults.find { it.id == ingredientId } ?: return
        val weight = state.recipePickIngredientId?.let { state.recipePickGrams } ?: 100.0
        _uiState.update {
            it.copy(
                recipeLines = it.recipeLines + NutritionRecipeLineDraft(ing, weight.coerceIn(5.0, 2000.0)),
                recipePickIngredientId = null,
                recipePickGrams = 100.0
            )
        }
    }

    fun setCreateField(
        name: String? = null,
        calories: String? = null,
        protein: String? = null,
        carbs: String? = null,
        fat: String? = null,
        saturatedFat: String? = null,
        sugars: String? = null,
        fiber: String? = null,
        sodiumMg: String? = null
    ) {
        _uiState.update {
            it.copy(
                createName = name ?: it.createName,
                createCalories = calories ?: it.createCalories,
                createProtein = protein ?: it.createProtein,
                createCarbs = carbs ?: it.createCarbs,
                createFat = fat ?: it.createFat,
                createSaturatedFat = saturatedFat ?: it.createSaturatedFat,
                createSugars = sugars ?: it.createSugars,
                createFiber = fiber ?: it.createFiber,
                createSodiumMg = sodiumMg ?: it.createSodiumMg
            )
        }
    }

    fun applyScannedNutritionProfile(result: NutritionLabelParseResult) {
        val form = NutritionIngredientFormState.fromScan(result)
        _uiState.update {
            it.copy(
                createCalories = form.calories,
                createProtein = form.protein,
                createCarbs = form.carbs,
                createFat = form.fat,
                createSaturatedFat = form.saturatedFat,
                createSugars = form.sugars,
                createFiber = form.fiber,
                createSodiumMg = form.sodiumMg
            )
        }
    }

    fun toggleMicroExpanded() {
        _uiState.update { it.copy(microExpanded = !it.microExpanded) }
    }

    fun clampInsightsDates() {
        _uiState.update { s ->
            val today = LocalDate.now()
            var to = s.insightsToDate.coerceAtMost(today)
            var from = s.insightsFromDate
            if (from.isAfter(to)) from = to
            val span = ChronoUnit.DAYS.between(from, to) + 1
            if (span > MAX_INSIGHTS_SPAN_DAYS) {
                from = to.minusDays((MAX_INSIGHTS_SPAN_DAYS - 1).toLong())
            }
            s.copy(insightsFromDate = from, insightsToDate = to)
        }
    }

    fun setInsightsFromDate(date: LocalDate) {
        _uiState.update { s ->
            val preset = s.insightsQuickPreset
            val cleared = preset?.let { !matchesInsightsPresetDates(s.insightsToDate, date, it) } ?: false
            s.copy(
                insightsFromDate = date,
                insightsQuickPreset = if (cleared) null else s.insightsQuickPreset
            )
        }
        clampInsightsDates()
    }

    fun setInsightsToDate(date: LocalDate) {
        _uiState.update { s ->
            val preset = s.insightsQuickPreset
            val cleared = preset?.let { !matchesInsightsPresetDates(date, s.insightsFromDate, it) } ?: false
            s.copy(
                insightsToDate = date,
                insightsQuickPreset = if (cleared) null else s.insightsQuickPreset
            )
        }
        clampInsightsDates()
    }

    fun applyInsightsQuickPreset(preset: NutritionInsightsQuickPreset) {
        val today = LocalDate.now()
        val (from, to) = when (preset) {
            NutritionInsightsQuickPreset.ONE_DAY -> today to today
            NutritionInsightsQuickPreset.ONE_WEEK -> today.minusDays(6) to today
            NutritionInsightsQuickPreset.ONE_MONTH -> today.minusDays(29) to today
        }
        _uiState.update {
            it.copy(
                insightsFromDate = from,
                insightsToDate = to,
                insightsQuickPreset = preset
            )
        }
        clampInsightsDates()
    }

    private fun matchesInsightsPresetDates(
        to: LocalDate,
        from: LocalDate,
        preset: NutritionInsightsQuickPreset
    ): Boolean {
        val today = LocalDate.now()
        return when (preset) {
            NutritionInsightsQuickPreset.ONE_DAY -> from == today && to == today
            NutritionInsightsQuickPreset.ONE_WEEK -> from == today.minusDays(6) && to == today
            NutritionInsightsQuickPreset.ONE_MONTH -> from == today.minusDays(29) && to == today
        }
    }

    fun resetSmartInsights() {
        _uiState.update {
            it.copy(
                smartInsightsLoading = false,
                smartInsights = null,
                smartInsightsError = null
            )
        }
    }

    fun analyzeSmartInsights() {
        clampInsightsDates()
        _uiState.update {
            it.copy(
                smartInsightsLoading = true,
                smartInsights = null,
                smartInsightsError = null
            )
        }
        viewModelScope.launch {
            val s = _uiState.value
            runCatching {
                coroutineScope {
                    val fetch = async { fetchSmartRecommendation(s.insightsFromDate, s.insightsToDate) }
                    val minDelay = async { delay(1000) }
                    fetch.await().also { minDelay.await() }
                }
            }.onSuccess { result ->
                _uiState.update {
                    it.copy(smartInsightsLoading = false, smartInsights = result)
                }
            }.onFailure { e ->
                _uiState.update {
                    it.copy(
                        smartInsightsLoading = false,
                        smartInsightsError = e.message?.take(300) ?: "Analysis failed"
                    )
                }
            }
        }
    }

    fun createDraftProfile(): NutritionProfilePer100g {
        val s = _uiState.value
        return NutritionProfilePer100g(
            calories = s.createCalories.replace(',', '.').toDoubleOrNull() ?: 0.0,
            protein = s.createProtein.replace(',', '.').toDoubleOrNull() ?: 0.0,
            carbs = s.createCarbs.replace(',', '.').toDoubleOrNull() ?: 0.0,
            fat = s.createFat.replace(',', '.').toDoubleOrNull() ?: 0.0,
            saturatedFat = s.createSaturatedFat.replace(',', '.').toDoubleOrNull() ?: 0.0,
            sugars = s.createSugars.replace(',', '.').toDoubleOrNull() ?: 0.0,
            fiber = s.createFiber.replace(',', '.').toDoubleOrNull() ?: 0.0,
            sodiumMg = s.createSodiumMg.replace(',', '.').toDoubleOrNull() ?: 0.0
        )
    }

    fun setRecipePickQuery(q: String) {
        _uiState.update { it.copy(recipePickQuery = q) }
        searchRecipePick()
    }

    fun selectRecipePick(id: String) {
        _uiState.update { it.copy(recipePickIngredientId = id) }
    }

    fun addRecipeLine() {
        val state = _uiState.value
        val ing = state.recipePickResults.find { it.id == state.recipePickIngredientId } ?: return
        _uiState.update {
            it.copy(
                recipeLines = it.recipeLines + NutritionRecipeLineDraft(ing, it.recipePickGrams),
                recipePickIngredientId = null,
                recipePickGrams = 100.0
            )
        }
    }

    fun removeRecipeLine(index: Int) {
        _uiState.update { s ->
            s.copy(recipeLines = s.recipeLines.filterIndexed { i, _ -> i != index })
        }
    }

    fun updateRecipeLineWeight(index: Int, grams: Double) {
        _uiState.update { s ->
            if (index !in s.recipeLines.indices) return@update s
            s.copy(
                recipeLines = s.recipeLines.mapIndexed { i, line ->
                    if (i == index) line.copy(weightG = grams.coerceAtMost(2000.0)) else line
                }
            )
        }
    }

    fun clearLogSelection() {
        clearLogCart()
    }

    fun setEditGrams(g: Double) {
        _uiState.update { it.copy(editGrams = g.coerceAtMost(2000.0)) }
    }

    fun setEditMealSlot(slot: String) {
        _uiState.update { it.copy(editMealSlot = slot) }
    }

    fun refresh() {
        viewModelScope.launch {
            val userId = supabase.auth.currentUserOrNull()?.id
            if (userId == null) {
                _uiState.update {
                    it.copy(loading = false, error = "Sign in to track nutrition.", recommendation = null, diaryByMeal = emptyMap())
                }
                return@launch
            }
            _uiState.update { it.copy(loading = true, error = null) }
            runCatching {
                val state = _uiState.value
                val dateStr = state.selectedDate.format(dateFormatter)
                val monthStart = state.month.atDay(1)
                val rec = fetchRecommendation(dateStr)
                val diary = fetchDiaryItems(userId, dateStr)
                val monthBalance = mergeMonthBalanceWithPlanned(
                    fetchMonthBalance(monthStart),
                    fetchMonthPlannedMealCounts(userId, state.month)
                )
                val grouped = mealSlotOrder.associateWith { slot -> diary.filter { it.mealSlot == slot } }
                val planned = fetchPlannedItems(userId, dateStr)
                val invites = fetchPendingInvites(userId)
                _uiState.update {
                    it.copy(
                        loading = false,
                        recommendation = rec,
                        diaryByMeal = grouped,
                        monthDayBalance = monthBalance,
                        plannedItems = planned,
                        pendingInvites = invites,
                        error = null
                    )
                }
            }.onFailure { e ->
                _uiState.update { it.copy(loading = false, error = e.message?.take(300) ?: e::class.java.simpleName) }
            }
        }
    }

    fun searchAddCatalog() {
        viewModelScope.launch {
            val userId = supabase.auth.currentUserOrNull()?.id ?: return@launch
            _uiState.update {
                it.copy(
                    searchLoading = true,
                    ingredientCanLoadMore = false,
                    ingredientLoadingMore = false
                )
            }
            runCatching {
                val q = _uiState.value.addSearchQuery.trim().lowercase()
                val scope = _uiState.value.addListScope
                val favIng = _uiState.value.favoriteIngredientIds
                val favRec = _uiState.value.favoriteRecipeIds
                if (_uiState.value.addModeIngredient) {
                    val page = fetchIngredientsPage(userId, q, page = 0, scope = scope, favoriteIds = favIng)
                    _uiState.update {
                        it.copy(
                            ingredientResults = page.rows,
                            ingredientCanLoadMore = page.hasMore,
                            ingredientCatalogPage = 0,
                            recipeResults = emptyList()
                        )
                    }
                } else {
                    val rows = fetchRecipes(userId, q, scope = scope, favoriteIds = favRec).take(40)
                    _uiState.update { it.copy(recipeResults = rows, ingredientResults = emptyList()) }
                }
            }
            _uiState.update { it.copy(searchLoading = false) }
        }
    }

    fun loadMoreAddCatalogIngredients() {
        val state = _uiState.value
        if (!state.addModeIngredient || state.searchLoading || state.ingredientLoadingMore || !state.ingredientCanLoadMore) {
            return
        }
        viewModelScope.launch {
            val userId = supabase.auth.currentUserOrNull()?.id ?: return@launch
            _uiState.update { it.copy(ingredientLoadingMore = true) }
            runCatching {
                val q = state.addSearchQuery.trim().lowercase()
                val nextPage = state.ingredientCatalogPage + 1
                val page = fetchIngredientsPage(
                    userId,
                    q,
                    page = nextPage,
                    scope = state.addListScope,
                    favoriteIds = state.favoriteIngredientIds
                )
                val existing = state.ingredientResults.map { it.id }.toSet()
                val fresh = page.rows.filter { it.id !in existing }
                _uiState.update {
                    it.copy(
                        ingredientResults = it.ingredientResults + fresh,
                        ingredientCatalogPage = nextPage,
                        ingredientCanLoadMore = page.hasMore,
                        ingredientLoadingMore = false
                    )
                }
            }.onFailure {
                _uiState.update { it.copy(ingredientCanLoadMore = false, ingredientLoadingMore = false) }
            }
        }
    }

    fun searchRecipePick() {
        viewModelScope.launch {
            val userId = supabase.auth.currentUserOrNull()?.id ?: return@launch
            val q = _uiState.value.recipePickQuery.trim().lowercase()
            val rows = fetchIngredientsMerged(userId, q).take(30)
            _uiState.update { it.copy(recipePickResults = rows) }
        }
    }

    suspend fun fetchRecipeLinesForShare(recipeId: String): List<NutritionRecipeLineDraft> =
        fetchRecipeLines(recipeId)

    fun saveDiaryCart() {
        viewModelScope.launch {
            val userId = supabase.auth.currentUserOrNull()?.id ?: return@launch
            val state = _uiState.value
            if (state.logCart.isEmpty()) return@launch setErr("Add at least one item.")
            if (state.logCart.any { it.loadingComposition }) return@launch
            _uiState.update { it.copy(saving = true, error = null) }
            runCatching {
                if (state.addFoodIsPlan) {
                    saveMealPlansFromCart(userId, state)
                    _uiState.update { it.copy(saving = false) }
                    dismissOverlay()
                    return@runCatching
                }
                val dateStr = state.selectedDate.format(dateFormatter)
                for (item in state.logCart) {
                    val grams = NutritionLogCartLogic.clampGrams(item.grams)
                    val payload = buildJsonObject {
                        put(BackendContracts.NutritionColumns.USER_ID, userId)
                        put(BackendContracts.NutritionColumns.LOG_DATE, dateStr)
                        put(BackendContracts.NutritionColumns.MEAL_SLOT, state.addMealSlot)
                        put(BackendContracts.NutritionColumns.QUANTITY_G, grams)
                        when {
                            item.ingredientId != null ->
                                put(BackendContracts.NutritionColumns.INGREDIENT_ID, item.ingredientId)
                            item.recipeId != null ->
                                put(BackendContracts.NutritionColumns.RECIPE_ID, item.recipeId)
                            else -> error("Invalid cart item")
                        }
                    }
                    supabase.from(BackendContracts.Tables.NUTRITION_DIARY_LOGS).insert(payload)
                }
                dismissOverlay()
            }.onFailure { e ->
                _uiState.update { it.copy(saving = false, error = e.message?.take(300)) }
            }
        }
    }

    fun saveIngredient(onNestedClose: (() -> Unit)? = null) {
        viewModelScope.launch {
            val userId = supabase.auth.currentUserOrNull()?.id ?: return@launch
            val s = _uiState.value
            val cals = s.createCalories.replace(',', '.').toDoubleOrNull() ?: return@launch setErr("Invalid calories")
            _uiState.update { it.copy(saving = true, error = null) }
            runCatching {
                val payload = buildJsonObject {
                    put(BackendContracts.NutritionColumns.NAME, s.createName.trim())
                    put(BackendContracts.NutritionColumns.CALORIES_PER_100G, cals)
                    put(BackendContracts.NutritionColumns.PROTEIN_PER_100G, s.createProtein.replace(',', '.').toDoubleOrNull() ?: 0.0)
                    put(BackendContracts.NutritionColumns.CARBS_PER_100G, s.createCarbs.replace(',', '.').toDoubleOrNull() ?: 0.0)
                    put(BackendContracts.NutritionColumns.FAT_PER_100G, s.createFat.replace(',', '.').toDoubleOrNull() ?: 0.0)
                    put(BackendContracts.NutritionColumns.SATURATED_FAT_PER_100G, s.createSaturatedFat.replace(',', '.').toDoubleOrNull() ?: 0.0)
                    put(BackendContracts.NutritionColumns.SUGARS_PER_100G, s.createSugars.replace(',', '.').toDoubleOrNull() ?: 0.0)
                    put(BackendContracts.NutritionColumns.FIBER_PER_100G, s.createFiber.replace(',', '.').toDoubleOrNull() ?: 0.0)
                    put(BackendContracts.NutritionColumns.SODIUM_MG_PER_100G, s.createSodiumMg.replace(',', '.').toDoubleOrNull() ?: 0.0)
                }
                val editingId = s.editingIngredientId
                if (editingId != null) {
                    supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS).update(payload) {
                        filter { eq(BackendContracts.NutritionColumns.ID, editingId) }
                    }
                    val fromLogFood = _uiState.value.overlay == NutritionOverlay.AddFood
                    if (fromLogFood) {
                        dismissLogFoodNestedOverlay()
                        _uiState.update { state ->
                            val base = state.copy(saving = false, editingIngredientId = null)
                            base.copy(
                                ingredientResults = state.ingredientResults.map { row ->
                                    if (row.id == editingId) {
                                        row.copy(
                                            name = s.createName.trim(),
                                            caloriesPer100g = cals,
                                            proteinPer100g = s.createProtein.replace(',', '.').toDoubleOrNull() ?: 0.0,
                                            carbsPer100g = s.createCarbs.replace(',', '.').toDoubleOrNull() ?: 0.0,
                                            fatPer100g = s.createFat.replace(',', '.').toDoubleOrNull() ?: 0.0,
                                            saturatedFatPer100g = s.createSaturatedFat.replace(',', '.').toDoubleOrNull() ?: 0.0,
                                            sugarsPer100g = s.createSugars.replace(',', '.').toDoubleOrNull() ?: 0.0,
                                            fiberPer100g = s.createFiber.replace(',', '.').toDoubleOrNull() ?: 0.0,
                                            sodiumMgPer100g = s.createSodiumMg.replace(',', '.').toDoubleOrNull() ?: 0.0
                                        )
                                    } else row
                                },
                                logCart = state.logCart.map { item ->
                                    if (item.ingredientId == editingId) {
                                        item.copy(
                                            displayName = s.createName.trim(),
                                            caloriesPer100g = cals
                                        )
                                    } else item
                                }
                            )
                        }
                        searchAddCatalog()
                    } else {
                        dismissOverlay()
                    }
                } else {
                    supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS).insert(
                        buildJsonObject {
                            put(BackendContracts.NutritionColumns.USER_ID, userId)
                            put(BackendContracts.NutritionColumns.NAME, s.createName.trim())
                            put(BackendContracts.NutritionColumns.CALORIES_PER_100G, cals)
                            put(BackendContracts.NutritionColumns.PROTEIN_PER_100G, s.createProtein.replace(',', '.').toDoubleOrNull() ?: 0.0)
                            put(BackendContracts.NutritionColumns.CARBS_PER_100G, s.createCarbs.replace(',', '.').toDoubleOrNull() ?: 0.0)
                            put(BackendContracts.NutritionColumns.FAT_PER_100G, s.createFat.replace(',', '.').toDoubleOrNull() ?: 0.0)
                            put(BackendContracts.NutritionColumns.SATURATED_FAT_PER_100G, s.createSaturatedFat.replace(',', '.').toDoubleOrNull() ?: 0.0)
                            put(BackendContracts.NutritionColumns.SUGARS_PER_100G, s.createSugars.replace(',', '.').toDoubleOrNull() ?: 0.0)
                            put(BackendContracts.NutritionColumns.FIBER_PER_100G, s.createFiber.replace(',', '.').toDoubleOrNull() ?: 0.0)
                            put(BackendContracts.NutritionColumns.SODIUM_MG_PER_100G, s.createSodiumMg.replace(',', '.').toDoubleOrNull() ?: 0.0)
                            put(BackendContracts.NutritionColumns.IS_PUBLIC, false)
                        }
                    )
                    if (onNestedClose != null) {
                        dismissLogFoodNestedOverlay()
                        _uiState.update { it.copy(saving = false) }
                        onNestedClose()
                    } else {
                        dismissOverlay()
                    }
                }
            }.onFailure { e -> _uiState.update { it.copy(saving = false, error = e.message?.take(300)) } }
        }
    }

    fun deleteIngredient() {
        viewModelScope.launch {
            val ingredientId = _uiState.value.editingIngredientId ?: return@launch
            deleteIngredientById(ingredientId)
        }
    }

    fun deleteSelectedIngredient(ingredientId: String) {
        viewModelScope.launch { deleteIngredientById(ingredientId) }
    }

    fun deleteSelectedRecipe(recipeId: String) {
        viewModelScope.launch { deleteRecipeById(recipeId) }
    }

    private suspend fun deleteIngredientById(ingredientId: String) {
        _uiState.update { it.copy(saving = true, error = null) }
        runCatching {
            supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS).delete {
                filter { eq(BackendContracts.NutritionColumns.ID, ingredientId) }
            }
            val fromLogFood = _uiState.value.overlay == NutritionOverlay.AddFood
            if (fromLogFood) {
                removeCatalogItemFromCart(ingredientId = ingredientId)
                dismissLogFoodNestedOverlay()
                _uiState.update { it.copy(saving = false) }
                searchAddCatalog()
            } else {
                dismissOverlay()
            }
        }.onFailure { e -> _uiState.update { it.copy(saving = false, error = e.message?.take(300)) } }
    }

    private suspend fun deleteRecipeById(recipeId: String) {
        _uiState.update { it.copy(saving = true, error = null) }
        runCatching {
            supabase.from(BackendContracts.Tables.NUTRITION_RECIPES).delete {
                filter { eq(BackendContracts.NutritionColumns.ID, recipeId) }
            }
            val fromLogFood = _uiState.value.overlay == NutritionOverlay.AddFood
            if (fromLogFood) {
                removeCatalogItemFromCart(recipeId = recipeId)
                dismissLogFoodNestedOverlay()
                _uiState.update { it.copy(saving = false) }
                searchAddCatalog()
            } else {
                dismissOverlay()
            }
        }.onFailure { e -> _uiState.update { it.copy(saving = false, error = e.message?.take(300)) } }
    }

    fun saveRecipe() {
        viewModelScope.launch {
            val userId = supabase.auth.currentUserOrNull()?.id ?: return@launch
            val s = _uiState.value
            if (s.recipeLines.isEmpty()) return@launch setErr("Add at least one ingredient")
            _uiState.update { it.copy(saving = true, error = null) }
            runCatching {
                val desc = s.recipeDescription.trim().takeIf { it.isNotEmpty() }
                val editingId = s.editingRecipeId
                if (editingId != null) {
                    supabase.from(BackendContracts.Tables.NUTRITION_RECIPES).update(
                        buildJsonObject {
                            put(BackendContracts.NutritionColumns.NAME, s.recipeName.trim())
                            put(BackendContracts.NutritionColumns.DESCRIPTION, desc)
                        }
                    ) {
                        filter { eq(BackendContracts.NutritionColumns.ID, editingId) }
                    }
                    supabase.from(BackendContracts.Tables.NUTRITION_RECIPE_INGREDIENTS).delete {
                        filter { eq("recipe_id", editingId) }
                    }
                    s.recipeLines.forEach { line ->
                        supabase.from(BackendContracts.Tables.NUTRITION_RECIPE_INGREDIENTS).insert(
                            buildJsonObject {
                                put("recipe_id", editingId)
                                put(BackendContracts.NutritionColumns.INGREDIENT_ID, line.ingredient.id)
                                put(BackendContracts.NutritionColumns.WEIGHT_G, line.weightG.coerceIn(5.0, 2000.0))
                            }
                        )
                    }
                    val fromLogFood = _uiState.value.overlay == NutritionOverlay.AddFood
                    if (fromLogFood) {
                        dismissLogFoodNestedOverlay()
                        _uiState.update { state ->
                            val updated = state.copy(saving = false, editingRecipeId = null)
                            updated.copy(
                                recipeResults = state.recipeResults.map {
                                    if (it.id == editingId) {
                                        it.copy(
                                            name = s.recipeName.trim(),
                                            description = desc
                                        )
                                    } else it
                                },
                                logCart = state.logCart.map { item ->
                                    if (item.recipeId == editingId) {
                                        item.copy(
                                            displayName = s.recipeName.trim(),
                                            recipeLines = s.recipeLines,
                                            loadingComposition = false
                                        )
                                    } else item
                                }
                            )
                        }
                        searchAddCatalog()
                    } else {
                        dismissOverlay()
                    }
                } else {
                    val recRes = supabase.from(BackendContracts.Tables.NUTRITION_RECIPES).insert(
                        buildJsonObject {
                            put(BackendContracts.NutritionColumns.USER_ID, userId)
                            put(BackendContracts.NutritionColumns.NAME, s.recipeName.trim())
                            if (desc != null) put(BackendContracts.NutritionColumns.DESCRIPTION, desc)
                        }
                    ) {
                        select(Columns.raw("id,user_id,name,description"))
                    }
                    val recipe = SupabaseResponseDecoding.decodeListOrObject<NutritionRecipeWire>(recRes.data).first()
                    s.recipeLines.forEach { line ->
                        supabase.from(BackendContracts.Tables.NUTRITION_RECIPE_INGREDIENTS).insert(
                            buildJsonObject {
                                put("recipe_id", recipe.id)
                                put(BackendContracts.NutritionColumns.INGREDIENT_ID, line.ingredient.id)
                                put(BackendContracts.NutritionColumns.WEIGHT_G, line.weightG.coerceIn(5.0, 2000.0))
                            }
                        )
                    }
                    if (_uiState.value.overlay == NutritionOverlay.AddFood) {
                        dismissLogFoodNestedOverlay()
                        _uiState.update { it.copy(saving = false) }
                    } else {
                        dismissOverlay()
                    }
                }
            }.onFailure { e -> _uiState.update { it.copy(saving = false, error = e.message?.take(300)) } }
        }
    }

    fun deleteRecipe() {
        viewModelScope.launch {
            val recipeId = _uiState.value.editingRecipeId ?: return@launch
            deleteRecipeById(recipeId)
        }
    }

    fun saveEditLog(itemId: String) {
        viewModelScope.launch {
            val s = _uiState.value
            _uiState.update { it.copy(saving = true, error = null) }
            runCatching {
                supabase.from(BackendContracts.Tables.NUTRITION_DIARY_LOGS).update(
                    buildJsonObject {
                        put(BackendContracts.NutritionColumns.MEAL_SLOT, s.editMealSlot)
                        put(BackendContracts.NutritionColumns.QUANTITY_G, s.editGrams.coerceIn(5.0, 2000.0))
                    }
                ) {
                    filter { eq(BackendContracts.NutritionColumns.ID, itemId) }
                }
                dismissOverlay()
            }.onFailure { e -> _uiState.update { it.copy(saving = false, error = e.message?.take(300)) } }
        }
    }

    fun deleteEditLog(itemId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(saving = true, error = null) }
            runCatching {
                supabase.from(BackendContracts.Tables.NUTRITION_DIARY_LOGS).delete {
                    filter { eq(BackendContracts.NutritionColumns.ID, itemId) }
                }
                dismissOverlay()
            }.onFailure { e -> _uiState.update { it.copy(saving = false, error = e.message?.take(300)) } }
        }
    }

    private fun setErr(msg: String) {
        _uiState.update { it.copy(error = msg) }
    }

    private suspend fun fetchSmartRecommendation(
        from: LocalDate,
        to: LocalDate
    ): SmartNutritionRecommendationUi {
        val res = supabase.postgrest.rpc(
            BackendContracts.Rpc.GET_SMART_NUTRITION_RECOMMENDATION_V1,
            buildJsonObject {
                put("p_start_date", dateFormatter.format(from))
                put("p_end_date", dateFormatter.format(to))
            }
        ) { }
        val trimmed = res.data.trim()
        val wire = if (trimmed.startsWith("[")) {
            SupabaseResponseDecoding.decodeListOrObject<SmartNutritionRecommendationWire>(trimmed).first()
        } else {
            SupabaseResponseDecoding.json.decodeFromString<SmartNutritionRecommendationWire>(trimmed)
        }
        val base = (wire.baseCaloriesTarget ?: BackendContracts.NutritionDisplayTargets.CALORIES_KCAL)
            .coerceAtLeast(1.0)
        val energyOut = wire.avgDailyEnergyOut ?: (base + wire.avgDailyBurnedKcal)
        val remaining = wire.avgDailyRemainingBudget ?: (energyOut - wire.avgDailyConsumedKcal)
        return SmartNutritionRecommendationUi(
            recommendationText = wire.recommendationText,
            alerts = wire.alerts,
            avgDailyConsumedKcal = wire.avgDailyConsumedKcal,
            avgDailyBurnedKcal = wire.avgDailyBurnedKcal,
            baseCaloriesTarget = base,
            avgDailyEnergyOut = energyOut,
            avgDailyRemainingBudget = remaining
        )
    }

    private suspend fun fetchRecommendation(dateStr: String): NutritionRecommendationUi {
        val res = supabase.postgrest.rpc(
            BackendContracts.Rpc.GET_DAILY_NUTRITION_RECOMMENDATION_V1,
            buildJsonObject { put("p_date", dateStr) }
        ) { }
        val trimmed = res.data.trim()
        val wire = if (trimmed.startsWith("[")) {
            SupabaseResponseDecoding.decodeListOrObject<DailyNutritionRecommendationWire>(trimmed).first()
        } else {
            SupabaseResponseDecoding.json.decodeFromString<DailyNutritionRecommendationWire>(trimmed)
        }
        val base = wire.baseCaloriesTarget.coerceAtLeast(1.0)
        val metabolic = base + wire.totalCaloriesBurnedActive - wire.totalCaloriesConsumed
        val remaining = wire.remainingCalories ?: metabolic
        val net = wire.netCaloriesBalance ?: remaining
        var ui = NutritionRecommendationUi(
            baseCaloriesTarget = base,
            consumed = wire.totalCaloriesConsumed,
            burned = wire.totalCaloriesBurnedActive,
            remaining = remaining,
            net = net,
            proteinG = wire.totalProteinGConsumed,
            carbsG = wire.totalCarbsGConsumed,
            fatG = wire.totalFatGConsumed,
            saturatedFatG = wire.totalSaturatedFatGConsumed,
            sugarsG = wire.totalSugarsGConsumed,
            fiberG = wire.totalFiberGConsumed,
            sodiumMg = wire.totalSodiumMgConsumed,
            recommendationText = wire.recommendationText
        )
        if (ui.consumed > 0 && ui.proteinG < 0.01 && ui.carbsG < 0.01 && ui.fatG < 0.01) {
            ui = enrichRecommendationFromDiary(ui, dateStr)
        }
        return ui
    }

    private suspend fun enrichRecommendationFromDiary(
        rec: NutritionRecommendationUi,
        dateStr: String
    ): NutritionRecommendationUi {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return rec
        val items = fetchDiaryItems(userId, dateStr)
        if (items.isEmpty()) return rec
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        var saturatedFat = 0.0
        var sugars = 0.0
        var fiber = 0.0
        var sodiumMg = 0.0
        val logRes = supabase.from(BackendContracts.Tables.NUTRITION_DIARY_LOGS)
            .select(columns = Columns.raw("id,ingredient_id,recipe_id,quantity_g")) {
                filter {
                    eq(BackendContracts.NutritionColumns.USER_ID, userId)
                    eq(BackendContracts.NutritionColumns.LOG_DATE, dateStr)
                }
            }
        val logs = SupabaseResponseDecoding.decodeListOrObject<NutritionDiaryLogWire>(logRes.data)
        val ingredientIds = logs.mapNotNull { it.ingredientId }.distinct()
        val recipeIds = logs.mapNotNull { it.recipeId }.distinct()
        val ingredientsById = mutableMapOf<String, NutritionIngredientWire>()
        if (ingredientIds.isNotEmpty()) {
            val ingRes = supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS)
                .select(columns = Columns.raw(NutritionIngredientSelect.COLUMNS)) {
                    filter { isIn(BackendContracts.NutritionColumns.ID, ingredientIds) }
                }
            SupabaseResponseDecoding.decodeListOrObject<NutritionIngredientWire>(ingRes.data)
                .forEach { ingredientsById[it.id] = it }
        }
        val recipeDensity = mutableMapOf<String, NutritionProfilePer100g>()
        for (recipeId in recipeIds) {
            val lines = fetchRecipeLines(recipeId)
            recipeDensity[recipeId] = rollupProfilePer100g(lines)
        }
        for (log in logs) {
            val q = log.quantityG
            log.ingredientId?.let { id ->
                ingredientsById[id]?.let { ing ->
                    protein += q * ing.proteinPer100g / 100.0
                    carbs += q * ing.carbsPer100g / 100.0
                    fat += q * ing.fatPer100g / 100.0
                    saturatedFat += q * ing.saturatedFatPer100g / 100.0
                    sugars += q * ing.sugarsPer100g / 100.0
                    fiber += q * ing.fiberPer100g / 100.0
                    sodiumMg += q * ing.sodiumMgPer100g / 100.0
                }
            } ?: log.recipeId?.let { id ->
                recipeDensity[id]?.let { profile ->
                    protein += q * profile.protein / 100.0
                    carbs += q * profile.carbs / 100.0
                    fat += q * profile.fat / 100.0
                    saturatedFat += q * profile.saturatedFat / 100.0
                    sugars += q * profile.sugars / 100.0
                    fiber += q * profile.fiber / 100.0
                    sodiumMg += q * profile.sodiumMg / 100.0
                }
            }
        }
        return rec.copy(
            proteinG = protein,
            carbsG = carbs,
            fatG = fat,
            saturatedFatG = saturatedFat,
            sugarsG = sugars,
            fiberG = fiber,
            sodiumMg = sodiumMg
        )
    }

    private suspend fun fetchMonthBalance(monthStart: LocalDate): Map<LocalDate, NutritionMonthDayBalance> {
        val res = supabase.postgrest.rpc(
            BackendContracts.Rpc.GET_NUTRITION_MONTH_BALANCE_V1,
            buildJsonObject { put("p_month", monthStart.format(dateFormatter)) }
        ) { }
        val rows = SupabaseResponseDecoding.decodeListOrObject<NutritionMonthBalanceWire>(res.data)
        return rows.associate { row ->
            LocalDate.parse(row.logDate) to NutritionMonthDayBalance(
                mealLogCount = row.mealLogCount,
                remainingCalories = row.remainingCalories,
                plannedMealCount = 0
            )
        }
    }

    private suspend fun fetchMonthPlannedMealCounts(userId: String, month: YearMonth): Map<LocalDate, Int> {
        val res = supabase.from(BackendContracts.Tables.NUTRITION_MEAL_PLAN_TARGETS)
            .select(Columns.raw(MEAL_PLAN_TARGET_SELECT)) {
                filter {
                    eq("target_user_id", userId)
                    eq("status", "accepted")
                }
            }
        val targets = SupabaseResponseDecoding.decodeListOrObject<MealPlanTargetWire>(res.data)
        if (targets.isEmpty()) return emptyMap()
        val plans = fetchMealPlansByIds(targets.map { it.planId }.distinct())
        val plansById = plans.associateBy { it.id }
        val counts = mutableMapOf<LocalDate, Int>()
        for (target in targets) {
            val plan = plansById[target.planId] ?: continue
            val planDate = runCatching { LocalDate.parse(plan.planDate) }.getOrNull() ?: continue
            if (planDate.year != month.year || planDate.month != month.month) continue
            counts[planDate] = (counts[planDate] ?: 0) + 1
        }
        return counts
    }

    private fun mergeMonthBalanceWithPlanned(
        balance: Map<LocalDate, NutritionMonthDayBalance>,
        plannedCounts: Map<LocalDate, Int>
    ): Map<LocalDate, NutritionMonthDayBalance> {
        val result = balance.toMutableMap()
        for ((day, count) in plannedCounts) {
            if (count <= 0) continue
            val existing = result[day]
            result[day] = if (existing != null) {
                existing.copy(plannedMealCount = count)
            } else {
                NutritionMonthDayBalance(mealLogCount = 0, remainingCalories = 0.0, plannedMealCount = count)
            }
        }
        return result
    }

    private data class IngredientPage(val rows: List<NutritionIngredientWire>, val hasMore: Boolean)

    private suspend fun fetchIngredientsPage(
        userId: String,
        q: String,
        page: Int,
        scope: NutritionListScope = NutritionListScope.ALL,
        favoriteIds: Set<String> = emptySet()
    ): IngredientPage {
        if (scope == NutritionListScope.FAVORITES && favoriteIds.isEmpty()) {
            return IngredientPage(rows = emptyList(), hasMore = false)
        }
        val from = page * ingredientPageSize
        val to = from + ingredientPageSize - 1
        val pattern = if (q.isEmpty()) null else "%$q%"
        val res = supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS)
            .select(columns = Columns.raw(NutritionIngredientSelect.COLUMNS)) {
                filter {
                    when (scope) {
                        NutritionListScope.ALL -> {
                            or {
                                eq(BackendContracts.NutritionColumns.IS_PUBLIC, true)
                                eq(BackendContracts.NutritionColumns.USER_ID, userId)
                            }
                        }
                        NutritionListScope.MINE -> {
                            eq(BackendContracts.NutritionColumns.USER_ID, userId)
                        }
                        NutritionListScope.FAVORITES -> {
                            isIn(BackendContracts.NutritionColumns.ID, favoriteIds.toList())
                            or {
                                eq(BackendContracts.NutritionColumns.IS_PUBLIC, true)
                                eq(BackendContracts.NutritionColumns.USER_ID, userId)
                            }
                        }
                    }
                    if (pattern != null) {
                        ilike(BackendContracts.NutritionColumns.NAME, pattern)
                    }
                }
                order(column = BackendContracts.NutritionColumns.NAME, order = Order.ASCENDING)
                range(from.toLong(), to.toLong())
            }
        val rows = SupabaseResponseDecoding.decodeListOrObject<NutritionIngredientWire>(res.data)
        return IngredientPage(rows = rows, hasMore = rows.size == ingredientPageSize)
    }

    private suspend fun fetchIngredientsMerged(userId: String, q: String): List<NutritionIngredientWire> {
        var page = 0
        val merged = mutableListOf<NutritionIngredientWire>()
        while (merged.size < 120) {
            val batch = fetchIngredientsPage(userId, q, page)
            merged.addAll(batch.rows)
            if (!batch.hasMore || batch.rows.isEmpty()) break
            page += 1
        }
        return merged.distinctBy { it.id }
    }

    private suspend fun fetchRecipes(
        userId: String,
        q: String,
        scope: NutritionListScope = NutritionListScope.ALL,
        favoriteIds: Set<String> = emptySet()
    ): List<NutritionRecipeWire> {
        if (scope == NutritionListScope.FAVORITES && favoriteIds.isEmpty()) {
            return emptyList()
        }
        val pattern = if (q.isEmpty()) null else "%$q%"
        val res = supabase.from(BackendContracts.Tables.NUTRITION_RECIPES)
            .select(columns = Columns.raw("id,user_id,name,description")) {
                filter {
                    when (scope) {
                        NutritionListScope.ALL -> {
                            or {
                                filter(BackendContracts.NutritionColumns.USER_ID, FilterOperator.IS, null)
                                eq(BackendContracts.NutritionColumns.USER_ID, userId)
                            }
                        }
                        NutritionListScope.MINE -> {
                            eq(BackendContracts.NutritionColumns.USER_ID, userId)
                        }
                        NutritionListScope.FAVORITES -> {
                            isIn(BackendContracts.NutritionColumns.ID, favoriteIds.toList())
                        }
                    }
                    if (pattern != null) {
                        ilike(BackendContracts.NutritionColumns.NAME, pattern)
                    }
                }
                order(column = BackendContracts.NutritionColumns.NAME, order = Order.ASCENDING)
                limit(60)
            }
        return SupabaseResponseDecoding.decodeListOrObject<NutritionRecipeWire>(res.data)
    }

    private suspend fun fetchRecipeLines(recipeId: String): List<NutritionRecipeLineDraft> {
        val joinRes = supabase.from(BackendContracts.Tables.NUTRITION_RECIPE_INGREDIENTS)
            .select(columns = Columns.raw("id,recipe_id,ingredient_id,weight_g")) {
                filter { eq("recipe_id", recipeId) }
            }
        val joins = SupabaseResponseDecoding.decodeListOrObject<NutritionRecipeIngredientWire>(joinRes.data)
        if (joins.isEmpty()) return emptyList()
        val ingredientIds = joins.map { it.ingredientId }.distinct()
        val ingRes = supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS)
            .select(columns = Columns.raw(NutritionIngredientSelect.COLUMNS)) {
                filter { isIn(BackendContracts.NutritionColumns.ID, ingredientIds) }
            }
        val ingredients = SupabaseResponseDecoding.decodeListOrObject<NutritionIngredientWire>(ingRes.data)
            .associateBy { it.id }
        return joins.mapNotNull { join ->
            val ing = ingredients[join.ingredientId] ?: return@mapNotNull null
            NutritionRecipeLineDraft(ing, join.weightG)
        }
    }

    private suspend fun fetchDiaryItems(userId: String, dateStr: String): List<NutritionDiaryItemUi> {
        val logRes = supabase.from(BackendContracts.Tables.NUTRITION_DIARY_LOGS)
            .select(columns = Columns.raw("id,user_id,log_date,meal_slot,ingredient_id,recipe_id,quantity_g")) {
                filter {
                    eq(BackendContracts.NutritionColumns.USER_ID, userId)
                    eq(BackendContracts.NutritionColumns.LOG_DATE, dateStr)
                }
                order(column = BackendContracts.NutritionColumns.MEAL_SLOT, order = Order.ASCENDING)
            }
        val logs = SupabaseResponseDecoding.decodeListOrObject<NutritionDiaryLogWire>(logRes.data)
        if (logs.isEmpty()) return emptyList()

        val ingredientIds = logs.mapNotNull { it.ingredientId }.distinct()
        val recipeIds = logs.mapNotNull { it.recipeId }.distinct()
        val ingredientsById = mutableMapOf<String, NutritionIngredientWire>()
        if (ingredientIds.isNotEmpty()) {
            val ingRes = supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS)
                .select(columns = Columns.raw(NutritionIngredientSelect.COLUMNS)) {
                    filter { isIn(BackendContracts.NutritionColumns.ID, ingredientIds) }
                }
            SupabaseResponseDecoding.decodeListOrObject<NutritionIngredientWire>(ingRes.data).forEach { ingredientsById[it.id] = it }
        }
        val recipesById = mutableMapOf<String, NutritionRecipeWire>()
        val recipeKcalPerGram = mutableMapOf<String, Double>()
        if (recipeIds.isNotEmpty()) {
            val recRes = supabase.from(BackendContracts.Tables.NUTRITION_RECIPES)
                .select(columns = Columns.raw("id,user_id,name,description")) {
                    filter { isIn(BackendContracts.NutritionColumns.ID, recipeIds) }
                }
            SupabaseResponseDecoding.decodeListOrObject<NutritionRecipeWire>(recRes.data).forEach { recipesById[it.id] = it }
            val joinRes = supabase.from(BackendContracts.Tables.NUTRITION_RECIPE_INGREDIENTS)
                .select(columns = Columns.raw("id,recipe_id,ingredient_id,weight_g")) {
                    filter { isIn("recipe_id", recipeIds) }
                }
            val joins = SupabaseResponseDecoding.decodeListOrObject<NutritionRecipeIngredientWire>(joinRes.data)
            val missing = joins.map { it.ingredientId }.distinct().filter { it !in ingredientsById }
            if (missing.isNotEmpty()) {
                val extraRes = supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS)
                    .select(columns = Columns.raw(NutritionIngredientSelect.COLUMNS)) {
                        filter { isIn(BackendContracts.NutritionColumns.ID, missing) }
                    }
                SupabaseResponseDecoding.decodeListOrObject<NutritionIngredientWire>(extraRes.data).forEach { ingredientsById[it.id] = it }
            }
            joins.groupBy { it.recipeId }.forEach { (recipeId, items) ->
                var totalKcal = 0.0
                var totalWeight = 0.0
                items.forEach { item ->
                    val ing = ingredientsById[item.ingredientId] ?: return@forEach
                    totalKcal += item.weightG * ing.caloriesPer100g / 100.0
                    totalWeight += item.weightG
                }
                if (totalWeight > 0) recipeKcalPerGram[recipeId] = totalKcal / totalWeight
            }
        }
        return logs.map { log ->
            log.ingredientId?.let { id ->
                ingredientsById[id]?.let { ing ->
                    return@map NutritionDiaryItemUi(log.id, log.mealSlot, ing.name, log.quantityG, log.quantityG * ing.caloriesPer100g / 100.0, false)
                }
            }
            log.recipeId?.let { id ->
                recipesById[id]?.let { recipe ->
                    val d = recipeKcalPerGram[id] ?: 0.0
                    return@map NutritionDiaryItemUi(log.id, log.mealSlot, recipe.name, log.quantityG, log.quantityG * d, true)
                }
            }
            NutritionDiaryItemUi(log.id, log.mealSlot, "Unknown", log.quantityG, 0.0, false)
        }
    }

    private suspend fun loadFollowingForPlan() {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return
        val followRes = supabase.from("follows").select(Columns.raw("followee_id")) {
            filter { eq("follower_id", userId) }
        }
        val follows = SupabaseResponseDecoding.decodeListOrObject<FollowRowWire>(followRes.data)
        val ids = follows.map { it.followeeId }
        if (ids.isEmpty()) {
            _uiState.update { it.copy(followingForPlan = emptyList()) }
            return
        }
        val profRes = supabase.from(BackendContracts.Tables.PROFILES).select(Columns.raw("user_id,username")) {
            filter { isIn("user_id", ids) }
        }
        val profiles = SupabaseResponseDecoding.decodeListOrObject<FollowingProfileWire>(profRes.data)
            .filter { it.userId != userId }
            .sortedBy { it.username?.lowercase() ?: it.userId }
        _uiState.update { it.copy(followingForPlan = profiles) }
    }

    private suspend fun saveMealPlansFromCart(userId: String, state: NutritionUiState) {
        val dateStr = state.planDate.format(dateFormatter)
        val defaultAssignees = planDefaultAssigneeIds(userId, state)
        for (item in state.logCart) {
            val assignees = if (item.assignedUserIds.isEmpty()) defaultAssignees else item.assignedUserIds
            if (assignees.isEmpty()) continue
            val planPayload = buildJsonObject {
                put("creator_id", userId)
                put("plan_date", dateStr)
                put("meal_slot", state.addMealSlot)
                item.ingredientId?.let { put("ingredient_id", it) }
                item.recipeId?.let { put("recipe_id", it) }
            }
            val planRes = supabase.from(BackendContracts.Tables.NUTRITION_MEAL_PLANS).insert(planPayload) {
                select(Columns.raw("id"))
            }
            val plans = SupabaseResponseDecoding.decodeListOrObject<MealPlanIdWire>(planRes.data)
            val planId = plans.firstOrNull()?.id ?: error("Plan not created")
            for (targetUserId in assignees) {
                val grams = NutritionLogCartLogic.clampGrams(item.perUserGrams[targetUserId] ?: item.grams)
                val targetPayload = buildJsonObject {
                    put("plan_id", planId)
                    put("target_user_id", targetUserId)
                    put("quantity_g", grams)
                    item.ingredientId?.let { put("ingredient_id", it) }
                    item.recipeId?.let { put("recipe_id", it) }
                }
                supabase.from(BackendContracts.Tables.NUTRITION_MEAL_PLAN_TARGETS).insert(targetPayload)
            }
        }
    }

    @Serializable
    private data class MealPlanIdWire(val id: String)

    private suspend fun fetchPendingInvites(userId: String): List<NutritionMealPlanInviteUi> {
        val res = supabase.from(BackendContracts.Tables.NUTRITION_MEAL_PLAN_TARGETS)
            .select(Columns.raw(MEAL_PLAN_TARGET_SELECT)) {
                filter {
                    eq("target_user_id", userId)
                    eq("status", "pending")
                }
            }
        val targets = SupabaseResponseDecoding.decodeListOrObject<MealPlanTargetWire>(res.data)
        return enrichInvites(targets, userId)
    }

    private suspend fun fetchPlannedItems(userId: String, dateStr: String): List<NutritionMealPlanItemUi> {
        val res = supabase.from(BackendContracts.Tables.NUTRITION_MEAL_PLAN_TARGETS)
            .select(Columns.raw(MEAL_PLAN_TARGET_SELECT)) {
                filter {
                    eq("target_user_id", userId)
                    eq("status", "accepted")
                }
            }
        val targets = SupabaseResponseDecoding.decodeListOrObject<MealPlanTargetWire>(res.data)
        if (targets.isEmpty()) return emptyList()
        val plans = fetchMealPlansByIds(targets.map { it.planId }.distinct())
            .filter { it.planDate == dateStr }
        return enrichPlannedItems(targets, userId, dateStr, plans)
    }

    private suspend fun enrichInvites(
        targets: List<MealPlanTargetWire>,
        inviteeId: String
    ): List<NutritionMealPlanInviteUi> {
        if (targets.isEmpty()) return emptyList()
        val planIds = targets.map { it.planId }.distinct()
        val plans = fetchMealPlansByIds(planIds)
        val plansById = plans.associateBy { it.id }
        val names = foodNamesForPlansAndTargets(plans, targets)
        val kcal = foodKcalPerGramForPlansAndTargets(plans, targets)
        val creators = plans.map { it.creatorId }.distinct()
        val usernames = usernamesFor(creators)
        return targets.mapNotNull { target ->
            val plan = plansById[target.planId] ?: return@mapNotNull null
            if (plan.creatorId == inviteeId) return@mapNotNull null
            if (target.targetUserId != inviteeId) return@mapNotNull null
            val foodId = target.ingredientId ?: target.recipeId ?: plan.ingredientId ?: plan.recipeId
            val name = foodId?.let { names[it] } ?: "Meal"
            val density = foodId?.let { kcal[it] } ?: 0.0
            NutritionMealPlanInviteUi(
                targetId = target.id,
                planId = plan.id,
                planDate = plan.planDate,
                mealSlot = plan.mealSlot,
                foodName = name,
                quantityG = target.quantityG,
                caloriesKcal = target.quantityG * density,
                creatorUsername = usernames[plan.creatorId]
            )
        }
    }

    private suspend fun enrichPlannedItems(
        targets: List<MealPlanTargetWire>,
        userId: String,
        dateStr: String,
        plansForDate: List<MealPlanWire>
    ): List<NutritionMealPlanItemUi> {
        val plansById = plansForDate.associateBy { it.id }
        val planIds = plansById.keys.toList()
        val siblings = if (planIds.isEmpty()) emptyList() else fetchTargetsForPlans(planIds)
        val siblingsByPlan = siblings.groupBy { it.planId }
        val names = foodNamesForPlansAndTargets(plansForDate, targets)
        val kcal = foodKcalPerGramForPlansAndTargets(plansForDate, targets)
        val userIds = (targets.map { it.targetUserId } + plansForDate.map { it.creatorId } + siblings.map { it.targetUserId }).distinct()
        val usernames = usernamesFor(userIds)
        return targets.mapNotNull { target ->
            if (target.targetUserId != userId) return@mapNotNull null
            val plan = plansById[target.planId] ?: return@mapNotNull null
            if (target.status != "accepted") return@mapNotNull null
            val foodId = target.ingredientId ?: target.recipeId ?: plan.ingredientId ?: plan.recipeId
            val name = foodId?.let { names[it] } ?: "Meal"
            val density = foodId?.let { kcal[it] } ?: 0.0
            val isCreator = plan.creatorId == userId
            val partnerLabel = if (isCreator) null else usernames[plan.creatorId]?.let { "from @$it" }
            val statusLabel = if (isCreator) {
                partnerStatusLabel(userId, siblingsByPlan[target.planId].orEmpty(), usernames)
            } else null
            NutritionMealPlanItemUi(
                targetId = target.id,
                planId = plan.id,
                targetUserId = target.targetUserId,
                mealSlot = plan.mealSlot,
                foodName = name,
                quantityG = target.quantityG,
                caloriesKcal = target.quantityG * density,
                status = target.status,
                isCreator = isCreator,
                partnerLabel = partnerLabel,
                partnerStatusLabel = statusLabel
            )
        }.sortedBy { it.mealSlot }
    }

    private fun partnerStatusLabel(
        viewingUserId: String,
        siblings: List<MealPlanTargetWire>,
        usernames: Map<String, String>
    ): String? {
        val others = siblings.filter { it.targetUserId != viewingUserId }
        if (others.isEmpty()) return null
        return others.joinToString(" · ") { row ->
            val name = usernames[row.targetUserId]?.let { "@$it" } ?: "Partner"
            "$name · ${row.status.replaceFirstChar { it.uppercase() }}"
        }
    }

    private suspend fun fetchTargetsForPlans(planIds: List<String>): List<MealPlanTargetWire> {
        if (planIds.isEmpty()) return emptyList()
        val res = supabase.from(BackendContracts.Tables.NUTRITION_MEAL_PLAN_TARGETS)
            .select(Columns.raw(MEAL_PLAN_TARGET_SELECT)) {
                filter { isIn("plan_id", planIds) }
            }
        return SupabaseResponseDecoding.decodeListOrObject<MealPlanTargetWire>(res.data)
    }

    private suspend fun foodNamesForPlansAndTargets(
        plans: List<MealPlanWire>,
        targets: List<MealPlanTargetWire>
    ): Map<String, String> {
        val ingredientIds = (plans.mapNotNull { it.ingredientId } + targets.mapNotNull { it.ingredientId }).distinct()
        val recipeIds = (plans.mapNotNull { it.recipeId } + targets.mapNotNull { it.recipeId }).distinct()
        val map = mutableMapOf<String, String>()
        if (ingredientIds.isNotEmpty()) {
            val res = supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS).select(Columns.raw("id,name")) {
                filter { isIn("id", ingredientIds) }
            }
            SupabaseResponseDecoding.decodeListOrObject<IdNameRow>(res.data).forEach { map[it.id] = it.name }
        }
        if (recipeIds.isNotEmpty()) {
            val res = supabase.from(BackendContracts.Tables.NUTRITION_RECIPES).select(Columns.raw("id,name")) {
                filter { isIn("id", recipeIds) }
            }
            SupabaseResponseDecoding.decodeListOrObject<IdNameRow>(res.data).forEach { map[it.id] = it.name }
        }
        return map
    }

    private suspend fun foodKcalPerGramForPlansAndTargets(
        plans: List<MealPlanWire>,
        targets: List<MealPlanTargetWire>
    ): Map<String, Double> {
        val map = mutableMapOf<String, Double>()
        val ingredientIds = (plans.mapNotNull { it.ingredientId } + targets.mapNotNull { it.ingredientId }).distinct()
        val recipeIds = (plans.mapNotNull { it.recipeId } + targets.mapNotNull { it.recipeId }).distinct()
        if (ingredientIds.isNotEmpty()) {
            val res = supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS)
                .select(Columns.raw("id,calories_per_100g")) {
                    filter { isIn("id", ingredientIds) }
                }
            SupabaseResponseDecoding.decodeListOrObject<IngredientCaloriesRow>(res.data).forEach {
                map[it.id] = it.caloriesPer100g / 100.0
            }
        }
        for (recipeId in recipeIds) {
            if (map.containsKey(recipeId)) continue
            val lines = fetchRecipeLines(recipeId)
            val profile = rollupProfilePer100g(lines)
            map[recipeId] = profile.calories / 100.0
        }
        return map
    }

    private suspend fun fetchMealPlansByIds(ids: List<String>): List<MealPlanWire> {
        if (ids.isEmpty()) return emptyList()
        val res = supabase.from(BackendContracts.Tables.NUTRITION_MEAL_PLANS)
            .select(Columns.raw("id,creator_id,plan_date,meal_slot,recipe_id,ingredient_id")) {
                filter { isIn("id", ids) }
            }
        return SupabaseResponseDecoding.decodeListOrObject<MealPlanWire>(res.data)
    }

    private suspend fun foodNamesForPlans(plans: List<MealPlanWire>): Map<String, String> {
        val map = mutableMapOf<String, String>()
        val ingredientIds = plans.mapNotNull { it.ingredientId }.distinct()
        val recipeIds = plans.mapNotNull { it.recipeId }.distinct()
        if (ingredientIds.isNotEmpty()) {
            val res = supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS).select(Columns.raw("id,name")) {
                filter { isIn("id", ingredientIds) }
            }
            SupabaseResponseDecoding.decodeListOrObject<IdNameRow>(res.data).forEach { map[it.id] = it.name }
        }
        if (recipeIds.isNotEmpty()) {
            val res = supabase.from(BackendContracts.Tables.NUTRITION_RECIPES).select(Columns.raw("id,name")) {
                filter { isIn("id", recipeIds) }
            }
            SupabaseResponseDecoding.decodeListOrObject<IdNameRow>(res.data).forEach { map[it.id] = it.name }
        }
        return map
    }

    private suspend fun foodKcalPerGramForPlans(plans: List<MealPlanWire>): Map<String, Double> {
        val map = mutableMapOf<String, Double>()
        for (plan in plans) {
            plan.ingredientId?.let { id ->
                val res = supabase.from(BackendContracts.Tables.NUTRITION_INGREDIENTS)
                    .select(Columns.raw("id,calories_per_100g")) {
                        filter { eq("id", id) }
                    }
                val row = SupabaseResponseDecoding.decodeListOrObject<IngredientCaloriesRow>(res.data).firstOrNull()
                if (row != null) map[id] = row.caloriesPer100g / 100.0
            }
            plan.recipeId?.let { id ->
                val lines = fetchRecipeLines(id)
                val profile = rollupProfile(lines)
                map[id] = profile.calories / 100.0
            }
        }
        return map
    }

    private suspend fun usernamesFor(userIds: List<String>): Map<String, String> {
        if (userIds.isEmpty()) return emptyMap()
        val res = supabase.from(BackendContracts.Tables.PROFILES).select(Columns.raw("user_id,username")) {
            filter { isIn("user_id", userIds.distinct()) }
        }
        return SupabaseResponseDecoding.decodeListOrObject<FollowingProfileWire>(res.data)
            .mapNotNull { p -> p.username?.takeIf { it.isNotBlank() }?.let { p.userId to it } }
            .toMap()
    }

    private data class MacroProfile(val calories: Double)

    private suspend fun rollupProfile(lines: List<NutritionRecipeLineDraft>): MacroProfile {
        var totalKcal = 0.0
        var totalWeight = 0.0
        for (line in lines) {
            totalKcal += line.weightG * line.ingredient.caloriesPer100g / 100.0
            totalWeight += line.weightG
        }
        val per100 = if (totalWeight > 0) totalKcal / totalWeight * 100.0 else 0.0
        return MacroProfile(per100)
    }
}

class NutritionViewModelFactory(private val supabase: SupabaseClient) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != NutritionViewModel::class.java) error("Unknown ViewModel")
        return NutritionViewModel(supabase) as T
    }
}
