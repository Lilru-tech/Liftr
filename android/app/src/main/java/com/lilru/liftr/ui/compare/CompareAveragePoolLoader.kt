package com.lilru.liftr.ui.compare

import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.home.WorkoutDetailRow
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
private data class AveragePoolWireRow(
    @SerialName("workout_id") val workoutId: Int,
    @SerialName("started_at") val startedAt: String? = null
)

object CompareAveragePoolLoader {
    const val MINE_LIMIT = 10
    const val GLOBAL_LIMIT = 50
    const val MIN_SAMPLES = 2

    private val json = Json { ignoreUnknownKeys = true }

    private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }

    fun typeLabelForWorkout(workout: WorkoutDetailRow): String {
        val t = workout.title?.trim().orEmpty()
        if (t.isNotEmpty()) return t
        return when (workout.kind.lowercase()) {
            "sport" -> "Sport"
            "cardio" -> "Cardio"
            else -> "Workout"
        }
    }

    suspend fun loadPickerAverages(
        supabase: SupabaseClient,
        baselineWorkoutId: Int,
        typeLabel: String
    ): Pair<CompareAverageOption?, CompareAverageOption?> {
        val mineIds = fetchPool(supabase, baselineWorkoutId, CompareAverageScope.MINE, MINE_LIMIT)
        val globalIds = fetchPool(supabase, baselineWorkoutId, CompareAverageScope.GLOBAL, GLOBAL_LIMIT)
        val mine = mineIds.takeIf { it.size >= MIN_SAMPLES }?.let {
            CompareAverageOption(
                scope = CompareAverageScope.MINE,
                workoutIds = it,
                sampleCount = it.size,
                typeLabel = typeLabel
            )
        }
        val global = globalIds.takeIf { it.size >= MIN_SAMPLES }?.let {
            CompareAverageOption(
                scope = CompareAverageScope.GLOBAL,
                workoutIds = it,
                sampleCount = it.size,
                typeLabel = typeLabel
            )
        }
        return mine to global
    }

    private suspend fun fetchPool(
        supabase: SupabaseClient,
        baselineWorkoutId: Int,
        scope: CompareAverageScope,
        limit: Int
    ): List<Int> {
        val scopeStr = when (scope) {
            CompareAverageScope.MINE -> "mine"
            CompareAverageScope.GLOBAL -> "global"
        }
        val params = buildJsonObject {
            put("p_baseline_workout", baselineWorkoutId)
            put("p_scope", scopeStr)
            put("p_limit", limit)
        }
        val res = supabase.postgrest.rpc(
            BackendContracts.Rpc.LIST_COMPARE_AVERAGE_POOL_V1,
            params
        ) { }
        val rows = decodeFlexibleList<AveragePoolWireRow>(res.data)
        return rows.map { it.workoutId }.distinct()
    }
}
