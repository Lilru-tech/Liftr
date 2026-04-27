package com.lilru.liftr.competition

import android.util.Log
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

private const val TAG = "CompetitionSubmit"

/**
 * Misma lógica que [Liftr.Competition/CompetitionService] `fetchMyActiveCompetitionId` (iOS)
 * y el helper previo en [com.lilru.liftr.ui.add.AddWorkoutViewModel].
 */
suspend fun SupabaseClient.fetchMyActiveCompetitionId(): Int? {
    val uid = auth.currentUserOrNull()?.id ?: return null
    suspend fun oneSide(column: String): Int? {
        val res = from(BackendContracts.Tables.COMPETITIONS)
            .select(columns = Columns.raw("id")) {
                filter {
                    eq("status", "active")
                    eq(column, uid)
                }
                limit(1)
            }
        return parseCompetitionIdFromSelect(res.data)
    }
    return oneSide("user_a") ?: oneSide("user_b")
}

private fun parseCompetitionIdFromSelect(data: String): Int? =
    runCatching {
        Json.parseToJsonElement(data).jsonArray.firstOrNull()
            ?.jsonObject?.get("id")?.jsonPrimitive?.content?.toIntOrNull()
    }.getOrNull()

/**
 * Enlaza un entreno con la competición activa del usuario vía RPC `submit_workout_to_competition`
 * (no bloquea: errores se registran, como `try?` en iOS Add).
 *
 * Usar tras **crear** en Add (como iOS). Al **publicar** un `planned` desde el detalle, iOS no invoca esto; Android
 * tampoco, para la misma paridad.
 */
suspend fun SupabaseClient.submitWorkoutToCompetitionIfActive(workoutId: Long?) {
    if (workoutId == null || workoutId <= 0L) return
    val cid = fetchMyActiveCompetitionId() ?: return
    runCatching {
        val params = buildJsonObject {
            put("p_competition_id", cid)
            put("p_workout_id", workoutId)
        }
        postgrest.rpc(BackendContracts.Rpc.SUBMIT_WORKOUT_TO_COMPETITION, params) { }
    }.onFailure { e ->
        Log.w(TAG, "submit_workout_to_competition failed for workout=$workoutId", e)
    }
}
