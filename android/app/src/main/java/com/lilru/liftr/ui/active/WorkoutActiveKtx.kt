package com.lilru.liftr.ui.active

import com.lilru.liftr.cardio.CardioKmPaceSplits
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.LiftrSupabase
import com.lilru.liftr.workout.WorkoutStartSync
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
internal data class WorkoutNotesStateRow(
    val notes: String? = null,
    val state: String? = null,
    val started_at: String? = null
)

/**
 * Cierre de entreno en vivo: [ended_at], notas, y pasa a [published] si estaba [planned] (alineado con
 * [WorkoutDetailView.publishWorkout] en iOS, pero integrado en el cierre del activo).
 */
internal fun workoutFinishUpdateJson(
    endedAtIso: String,
    mergedNotes: String?,
    currentState: String?,
    pausedSec: Int? = null
) = buildJsonObject {
    put("ended_at", endedAtIso)
    if (pausedSec != null) {
        put("paused_sec", pausedSec)
    }
    if (currentState?.lowercase() == "planned") {
        put("state", "published")
    }
    if (mergedNotes == null) {
        put("notes", JsonNull)
    } else {
        put("notes", mergedNotes)
    }
}

/**
 * Mismas líneas que [ActiveCardioWorkoutView.gpsNoteLinePrefixes] en iOS: al finalizar
 * se eliminan del [notes] existente para no acumular metadata GPS obsoleta.
 */
private val gpsNoteLinePrefixes: List<String> = listOf(
    "[GPS] Km splits (min/km):",
    "[GPS] Avg pace /km:"
)

/**
 * Alinea con [ActiveCardioWorkoutView.mergeWorkoutNotes] en iOS.
 * [gpsLine] es null en Android mientras no haya trazado GPS.
 */
/**
 * Líneas [GPS] al publicar (paridad con [Liftr.ActiveCardioWorkoutView] notas con splits y ritmo medio).
 */
internal fun buildGpsWorkoutNotesAppendix(
    splitPaceSecPerKm: List<Int>,
    avgPaceSecPerKm: Int?
): String? {
    val parts = mutableListOf<String>()
    if (splitPaceSecPerKm.isNotEmpty()) {
        val body = CardioKmPaceSplits.formatFieldText(splitPaceSecPerKm)
        parts.add("[GPS] Km splits (min/km): $body")
    }
    if (avgPaceSecPerKm != null && avgPaceSecPerKm > 0) {
        val m = avgPaceSecPerKm / 60
        val s = avgPaceSecPerKm % 60
        parts.add("[GPS] Avg pace /km: ${String.format("%d:%02d", m, s)}")
    }
    if (parts.isEmpty()) return null
    return parts.joinToString("\n")
}

internal fun mergeWorkoutNotesForFinish(existing: String?, gpsLine: String?): String? {
    val trimmed = existing?.trim() ?: ""
    val withoutOld = trimmed
        .lines()
        .filter { line ->
            val t = line.trim()
            !gpsNoteLinePrefixes.any { t.startsWith(it) }
        }
        .joinToString("\n")
        .trim()
    val chunks = buildList {
        if (withoutOld.isNotEmpty()) add(withoutOld)
        val g = gpsLine?.trim()
        if (!g.isNullOrEmpty()) add(g)
    }
    val merged = chunks.joinToString("\n\n")
    return merged.ifEmpty { null }
}

/**
 * Alinea con [WorkoutDetailView.startPlannedWorkout] / `setWorkoutStartedNow` en iOS:
 * marca [started_at] al abrir el entreno en vivo.
 */
internal suspend fun patchWorkoutStartedAtNow(supabase: SupabaseClient, workoutId: Int) {
    val ctx = LiftrSupabase.appContext ?: return
    WorkoutStartSync.enqueueStart(ctx, workoutId)
}
