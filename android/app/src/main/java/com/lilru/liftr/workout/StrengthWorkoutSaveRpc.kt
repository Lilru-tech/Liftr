package com.lilru.liftr.workout

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class StrengthWorkoutSaveResultWire(
    @SerialName("workout_id") val workoutId: Int,
    @SerialName("user_id") val userId: String? = null,
    val kind: String? = null,
    val title: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    val state: String? = null,
    val score: Double? = null
)

internal object StrengthWorkoutSaveRpc {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun updateStrengthWorkoutV1(
        supabase: SupabaseClient,
        workoutId: Int,
        title: String?,
        notes: String?,
        startedAtIso: String,
        endedAtIso: String?,
        perceivedIntensity: String?,
        exercises: List<StrengthEditExercisePayload>
    ): StrengthWorkoutSaveResultWire {
        val params = buildJsonObject {
            put("p_workout_id", workoutId)
            put("p_started_at", startedAtIso)
            put("p_exercises", StrengthWorkoutEditSavePayload.exercisesToJsonArray(exercises))
            if (title != null) put("p_title", title) else put("p_title", JsonNull)
            if (notes != null) put("p_notes", notes) else put("p_notes", JsonNull)
            if (endedAtIso != null) put("p_ended_at", endedAtIso) else put("p_ended_at", JsonNull)
            if (perceivedIntensity != null) {
                put("p_perceived_intensity", perceivedIntensity)
            } else {
                put("p_perceived_intensity", JsonNull)
            }
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.UPDATE_STRENGTH_WORKOUT_V1, params) { }
        return json.decodeFromString(res.data)
    }

    suspend fun finishStrengthWorkoutV1(
        supabase: SupabaseClient,
        workoutId: Int,
        endedAtIso: String,
        pausedSec: Int,
        hostExercises: List<StrengthFinishExercisePayload>,
        linked: List<StrengthFinishLinkedPayload> = emptyList()
    ): List<StrengthWorkoutSaveResultWire> {
        val params = buildJsonObject {
            put("p_workout_id", workoutId)
            put("p_ended_at", endedAtIso)
            put("p_paused_sec", pausedSec)
            put("p_exercises", StrengthWorkoutFinishCollapse.exercisesToJsonArray(hostExercises))
            put(
                "p_linked",
                buildJsonArray {
                    linked.forEach { link ->
                        add(
                            buildJsonObject {
                                put("workout_id", link.workoutId)
                                put("exercises", StrengthWorkoutFinishCollapse.exercisesToJsonArray(link.exercises))
                            }
                        )
                    }
                }
            )
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.FINISH_STRENGTH_WORKOUT_V1, params) { }
        return decodeFlexibleList(res.data)
    }

    private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }
}

internal data class StrengthFinishLinkedPayload(
    val workoutId: Int,
    val exercises: List<StrengthFinishExercisePayload>
)
