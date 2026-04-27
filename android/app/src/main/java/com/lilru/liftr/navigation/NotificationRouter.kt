package com.lilru.liftr.navigation

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
/**
 * Misma lógica que [Liftr/AppState.swift] `processNotification` (enrutado por `type` y `data`).
 */
object NotificationRouter {
    private val json = Json { ignoreUnknownKeys = true }

    fun overlayFromInAppRow(type: String?, data: JsonObject?, myUserId: String?): MainOverlay? {
        val t = (type ?: "").lowercase().trim()
        if (t.isEmpty()) {
            // Fallback: solo claves (lista actual de NotificationsViewModel)
            if (data == null) return null
            return overlayFromStringMap(
                tRaw = "legacy",
                map = dataKeyValues(data),
                myUserId = myUserId
            )
        }
        return overlayFromStringMap(
            tRaw = t,
            map = if (data != null) dataKeyValues(data) else emptyMap(),
            myUserId = myUserId
        )
    }

    fun overlayFromFcmData(map: Map<String, String>, myUserId: String?): MainOverlay? {
        var type = map["type"] ?: map["notification_type"] ?: return null
        if (type.isEmpty()) return null
        val data = parseNestedDataMap(map)
        if (data.isNotEmpty() && (map["workout_id"] == null) && (map["follower_id"] == null)) {
            // merge: algunos servicios envían todo en "data" como JSON
            return overlayFromStringMap(type, data, myUserId)
        }
        // Mezclar pares comunes
        val merged = HashMap(data)
        map["workout_id"]?.let { merged["workout_id"] = it }
        map["owner_id"]?.let { merged["owner_id"] = it }
        map["follower_id"]?.let { merged["follower_id"] = it }
        map["competition_id"]?.let { merged["competition_id"] = it }
        return overlayFromStringMap(type, merged, myUserId)
    }

    private fun dataKeyValues(data: JsonObject): Map<String, String> = buildMap {
        for ((k, v) in data) {
            this[k] = v.jsonPrimitive.contentOrNull ?: continue
        }
    }

    private fun parseNestedDataMap(map: Map<String, String>): Map<String, String> {
        val jsonStr = map["data"] ?: return emptyMap()
        return runCatching {
            val obj = json.parseToJsonElement(jsonStr) as? JsonObject ?: return emptyMap()
            dataKeyValues(obj)
        }.getOrDefault(emptyMap())
    }

    private fun overlayFromStringMap(tRaw: String, map: Map<String, String>, myUserId: String?): MainOverlay? {
        when (tRaw) {
            "new_follower" -> {
                val id = map["follower_id"]?.trim() ?: return null
                if (!looksLikeUuid(id)) return null
                return MainOverlay.FollowerProfile(id)
            }
            "workout_kind_inactive" -> {
                val raw = (map["workout_kind"] ?: "strength").lowercase()
                return MainOverlay.AddWorkoutDraftKind(
                    when (raw) {
                        "cardio" -> "cardio"
                        "sport" -> "sport"
                        else -> "strength"
                    }
                )
            }
        }

        val t = tRaw
        return when (t) {
            "workout_like",
            "workout_comment",
            "comment_reply",
            "comment_like" -> {
                val w = map["workout_id"]?.toIntOrNull() ?: return null
                val oid = map["owner_id"]?.trim()?.takeIf { it.isNotEmpty() && looksLikeUuid(it) }
                MainOverlay.WorkoutDetail(workoutId = w, ownerId = oid)
            }
            "added_as_participant" -> {
                val w = map["workout_id"]?.toIntOrNull() ?: return null
                MainOverlay.WorkoutDetail(workoutId = w, ownerId = null) // se resuelve con suspend
            }
            "achievement_unlocked" -> MainOverlay.Achievements(fromNotification = true)
            "goal_completed", "goal_almost_done" -> {
                val u = myUserId ?: return null
                MainOverlay.Goals(u)
            }
            "competition_invite",
            "competition_accepted",
            "competition_declined",
            "competition_cancelled",
            "competition_expired",
            "competition_result_win",
            "competition_result_lose" -> {
                val cid = map["competition_id"]?.toIntOrNull()
                if (cid != null) MainOverlay.CompetitionDetailById(cid) else MainOverlay.CompetitionsHub
            }
            "competition_workout_pending_review" -> MainOverlay.CompetitionReviews
            "competition_workout_accepted",
            "competition_workout_rejected" -> {
                val cid = map["competition_id"]?.toIntOrNull()
                if (cid != null) MainOverlay.CompetitionDetailById(cid) else MainOverlay.CompetitionsHub
            }
            "legacy" -> {
                if (map["workout_id"] != null) {
                    val w = map["workout_id"]?.toIntOrNull() ?: return null
                    MainOverlay.WorkoutDetail(w, null)
                } else if (map["follower_id"] != null) {
                    val id = map["follower_id"]!! 
                    if (looksLikeUuid(id)) MainOverlay.FollowerProfile(id) else null
                } else null
            }
            else -> null
        }
    }

    private fun looksLikeUuid(s: String) =
        s.length == 36 && s.count { it == '-' } == 4

    @Serializable
    private data class OwnerRow(
        @SerialName("user_id") val userId: String
    )

    /**
     * Resuelve owner de entrenamiento para `added_as_participant` (paridad con iOS).
     */
    suspend fun resolveWorkoutOwnerId(
        supabase: SupabaseClient,
        workoutId: Int
    ): String? = withContext(Dispatchers.IO) {
        runCatching {
            supabase.from(BackendContracts.Tables.WORKOUTS)
                .select(columns = Columns.raw("user_id")) {
                    filter { eq("id", workoutId.toString()) }
                    limit(1)
                }
                .decodeList<OwnerRow>()
                .firstOrNull()
                ?.userId
        }.getOrNull()
    }
}
