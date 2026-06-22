package com.lilru.liftr.data

import androidx.compose.ui.graphics.Color
import com.lilru.liftr.ui.AppSnackbar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray

object CoinManager {
    @Volatile
    var balance: Int = 0
        private set

    private var lastEarnToastAtMs: Long = 0L
    private var hasEstablishedBalanceBaseline = false
    private val mutex = Mutex()
    private const val EARN_TOAST_DEBOUNCE_MS = 2_000L
    private const val EARN_TOAST_MAX_AGE_MS = 120_000L

    private val _transactionHistoryRefresh = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val transactionHistoryRefresh = _transactionHistoryRefresh.asSharedFlow()

    fun notifyTransactionHistoryShouldRefresh() {
        _transactionHistoryRefresh.tryEmit(Unit)
    }

    fun syncBalance(value: Int) {
        balance = maxOf(0, value)
        hasEstablishedBalanceBaseline = true
    }

    fun resetSession() {
        balance = 0
        hasEstablishedBalanceBaseline = false
        lastEarnToastAtMs = 0L
    }

    suspend fun refreshBalance(
        supabase: SupabaseClient,
        notifyIfEarned: Boolean = false
    ) {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        val previousBalance = balance
        runCatching {
            @Serializable
            data class Row(@SerialName("coins_balance") val coinsBalance: Int? = null)
            val res = supabase.from(BackendContracts.Tables.PROFILES)
                .select(columns = Columns.raw(BackendContracts.ProfileColumns.COINS_BALANCE)) {
                    filter { eq("user_id", me) }
                    limit(1)
                }
            val next = maxOf(0, SupabaseResponseDecoding.decodeListOrObject<Row>(res.data).firstOrNull()?.coinsBalance ?: 0)
            balance = next
            if (!hasEstablishedBalanceBaseline) {
                hasEstablishedBalanceBaseline = true
                return@runCatching
            }
            if (notifyIfEarned && next > previousBalance) {
                notifyTransactionHistoryShouldRefresh()
                showEarnToast(supabase, next - previousBalance)
            }
        }
    }

    suspend fun refreshBalanceAfterMutation(
        supabase: SupabaseClient,
        notifyIfEarned: Boolean = true
    ) {
        refreshBalance(supabase, notifyIfEarned)
    }

    private suspend fun showEarnToast(supabase: SupabaseClient, fallbackDelta: Int) {
        val now = System.currentTimeMillis()
        mutex.withLock {
            if (now - lastEarnToastAtMs < EARN_TOAST_DEBOUNCE_MS) return
        }

        val message = runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.LIST_MY_COIN_TRANSACTIONS_V1,
                buildJsonObject { put("p_limit", 5) }
            ) { }
            val arr = parseRpcArray(res.data)
            val now = System.currentTimeMillis()
            val recent = (0 until arr.length()).mapNotNull { idx ->
                arr.optJSONObject(idx)
            }.firstOrNull { o ->
                o.optInt("amount") > 0 && isRecentEarn(o.optString("created_at"), now)
            } ?: return
            val amount = recent.optInt("amount")
            val label = displayLabel(recent.optString("action_type"))
            "+$amount Liftr Coins · $label"
        }.getOrNull() ?: return
        mutex.withLock { lastEarnToastAtMs = now }
        AppSnackbar.showSuccess(message)
    }

    private fun parseRpcArray(raw: String): JSONArray {
        val trimmed = raw.trim()
        return when {
            trimmed.startsWith("[") -> JSONArray(trimmed)
            trimmed.startsWith("{") -> JSONArray().put(org.json.JSONObject(trimmed))
            else -> JSONArray()
        }
    }

    private fun isRecentEarn(createdAt: String?, nowMs: Long): Boolean {
        if (createdAt.isNullOrBlank()) return false
        val createdMs = runCatching {
            java.time.Instant.parse(createdAt).toEpochMilli()
        }.getOrNull() ?: return false
        val age = nowMs - createdMs
        return age in 0..EARN_TOAST_MAX_AGE_MS
    }

    fun formattedAmount(amount: Int): String =
        if (amount >= 0) "+$amount" else "$amount"

    fun sourceKey(actionType: String): String = when (actionType) {
        "workout_logged",
        "workout_coin_doubling_v1",
        "workout_economy_rebalance_v1",
        "workout_economy_reduction_30pct_v1" -> "workouts"
        "workout_pet_training_bonus" -> "pet_workout_bonus"
        "pet_coins_generated",
        "pet_passive_economy_rebalance_v1",
        "pet_passive_economy_reduction_30pct_v1" -> "pet_coins"
        "like_given", "comment_added", "user_followed", "earned_follower" -> "social"
        "nutrition_ingredient_logged", "nutrition_recipe_logged",
        "nutrition_ingredient_created", "nutrition_recipe_created" -> "nutrition"
        "achievement_unlocked", "achievement_unlocked_bronze",
        "achievement_unlocked_silver", "achievement_unlocked_gold" -> "achievements"
        "weekly_goal_perfect_week", "workout_consistency_streak" -> "goals_streaks"
        "competition_bet_win", "competition_bet_refund_draw",
        "competition_bet_refund_cancelled", "competition_bet_escrow" -> "competition"
        "pet_combat_reward" -> "pet_combat"
        else -> "other"
    }

    fun displayLabel(actionType: String): String = when (actionType) {
        "like_given" -> "Like given"
        "comment_added" -> "Comment added"
        "user_followed" -> "Follow"
        "earned_follower" -> "New follower"
        "achievement_unlocked" -> "Achievement"
        "workout_logged" -> "Workout logged"
        "workout_pet_training_bonus" -> "Pet workout bonus"
        "workout_coin_doubling_v1" -> "Workout reward boost"
        "workout_economy_rebalance_v1" -> "Workout economy update"
        "pet_passive_economy_rebalance_v1" -> "Pet passive rebalance"
        "workout_economy_reduction_30pct_v1" -> "Workout economy adjustment"
        "pet_passive_economy_reduction_30pct_v1" -> "Pet passive adjustment"
        "weekly_goal_perfect_week" -> "Perfect week"
        "workout_consistency_streak" -> "7-day streak"
        "competition_bet_escrow" -> "Competition stake"
        "competition_bet_win" -> "Competition win"
        "competition_bet_refund_draw" -> "Competition draw refund"
        "competition_bet_refund_cancelled" -> "Competition refund"
        "pet_coins_generated" -> "Pet coins"
        "pet_market_purchase" -> "Pet shop purchase"
        "pet_egg_reroll" -> "Egg reroll"
        "pet_rarity_upgrade" -> "Pet rarity upgrade"
        "nutrition_ingredient_logged" -> "Food logged"
        "nutrition_recipe_logged" -> "Recipe logged"
        "nutrition_ingredient_created" -> "Ingredient created"
        "nutrition_recipe_created" -> "Recipe created"
        "" -> "Coins earned"
        else -> actionType.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }

    fun sourceCategoryLabel(key: String): String = when (key) {
        "workouts" -> "Workouts"
        "pet_workout_bonus" -> "Pet workout bonus"
        "pet_coins" -> "Pet coins"
        "social" -> "Social"
        "nutrition" -> "Nutrition"
        "achievements" -> "Achievements"
        "goals_streaks" -> "Goals & streaks"
        "competition" -> "Competition"
        "pet_combat" -> "Pet combat"
        "other" -> "Other"
        else -> key.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }

    fun sourceCategoryColor(key: String): Color = when (key) {
        "workouts" -> Color(0xFF1E88E5)
        "pet_workout_bonus" -> Color(0xFF9C27B0)
        "pet_coins" -> Color(0xFFFFC107)
        "social" -> Color(0xFFE91E63)
        "nutrition" -> Color(0xFF4CAF50)
        "achievements" -> Color(0xFFFF5722)
        "goals_streaks" -> Color(0xFF00BCD4)
        "competition" -> Color(0xFF795548)
        "pet_combat" -> Color(0xFF673AB7)
        else -> Color(0xFF9E9E9E)
    }
}
