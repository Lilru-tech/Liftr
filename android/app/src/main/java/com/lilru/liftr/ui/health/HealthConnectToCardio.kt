package com.lilru.liftr.ui.health

import androidx.health.connect.client.records.ExerciseSessionRecord
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.territory.TerritoryCaptureClient
import com.lilru.liftr.ui.add.AddCardioActivity
import com.lilru.liftr.ui.add.AddWorkoutIntensity
import com.lilru.liftr.ui.add.AddWorkoutState
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject
import java.time.ZoneId

fun exerciseTypeToActivityWire(exerciseType: Int): String = when (exerciseType) {
    ExerciseSessionRecord.EXERCISE_TYPE_WALKING,
    ExerciseSessionRecord.EXERCISE_TYPE_HIKING -> AddCardioActivity.WALK.wire
    ExerciseSessionRecord.EXERCISE_TYPE_BIKING -> AddCardioActivity.BIKE.wire
    ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY -> AddCardioActivity.INDOOR_CYCLING.wire
    ExerciseSessionRecord.EXERCISE_TYPE_ROWING_MACHINE,
    ExerciseSessionRecord.EXERCISE_TYPE_ELLIPTICAL -> AddCardioActivity.ROWERG.wire
    ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL -> AddCardioActivity.SWIM_POOL.wire
    ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER -> AddCardioActivity.SWIM_OPEN_WATER.wire
    else -> AddCardioActivity.RUN.wire
}

internal fun healthConnectWorkoutExternalId(metadataId: String): String? {
    val trimmed = metadataId.trim()
    return trimmed.takeIf { it.isNotEmpty() }?.let { "hc:$it" }
}

private fun isOutdoorTerritoryEligible(exerciseType: Int): Boolean = when (exerciseType) {
    ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY,
    ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL -> false
    else -> true
}

suspend fun importHealthConnectSessionToCardio(
    supabase: SupabaseClient,
    rec: ExerciseSessionRecord
): Result<Int> = runCatching {
    val userId = supabase.auth.currentUserOrNull()?.id
        ?: error("No hay sesión de usuario.")
    val started = rec.startTime.atZone(ZoneId.systemDefault()).toInstant().toString()
    val end = rec.endTime ?: error("La sesión no tiene fin.")
    val durationSec = java.time.Duration.between(rec.startTime, end).seconds.toInt()
    if (durationSec <= 0) error("Duración no válida.")
    val code = exerciseTypeToActivityWire(rec.exerciseType)
    val title = (rec.title ?: "Import Health").trim().ifEmpty { "Import Health" }
    val stats = buildJsonObject { }
    val healthConnectUuid = healthConnectWorkoutExternalId(rec.metadata.id)
    val p = buildJsonObject {
        put("p_user_id", userId)
        put("p_activity_code", code)
        put("p_started_at", started)
        put("p_ended_at", end.atZone(ZoneId.systemDefault()).toInstant().toString())
        put("p_perceived_intensity", AddWorkoutIntensity.MODERATE.wire)
        put("p_state", AddWorkoutState.PUBLISHED.name.lowercase())
        put("p_title", title)
        put("p_duration_sec", durationSec)
        put("p_stats", stats)
        healthConnectUuid?.let { put("p_healthkit_uuid", it) }
    }
    val wrapper = buildJsonObject { put("p", p) }
    val res = supabase.postgrest.rpc(BackendContracts.Rpc.CREATE_CARDIO_WORKOUT_V2, wrapper) { }
    val id = parseWorkoutIdFromCreateCardioResponse(res.data) ?: error("No se pudo leer el id del entreno.")
    if (isOutdoorTerritoryEligible(rec.exerciseType)) {
        TerritoryCaptureClient.applyCapture(supabase, id.toInt())
    }
    id.toInt()
}

private fun parseWorkoutIdFromCreateCardioResponse(raw: String): Long? {
    val trimmed = raw.trim()
    trimmed.toLongOrNull()?.let { return it }
    runCatching { JSONArray(trimmed).optLong(0).takeIf { it > 0L } }.getOrNull()?.let { return it }
    runCatching { JSONObject(trimmed).optLong("id").takeIf { it > 0L } }.getOrNull()?.let { return it }
    return null
}
