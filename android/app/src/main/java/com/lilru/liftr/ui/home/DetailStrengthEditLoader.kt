package com.lilru.liftr.ui.home

import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.add.StrengthExerciseDraft
import com.lilru.liftr.ui.add.StrengthSegmentDraft
import com.lilru.liftr.ui.add.StrengthSetDraft
import com.lilru.liftr.ui.add.parseWeightSegmentsColumn
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.util.UUID
import kotlin.math.floor
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray

@Serializable
private data class WExWire(
    val id: Int,
    @SerialName("exercise_id") val exerciseId: Long,
    @SerialName("order_index") val orderIndex: Int,
    val notes: String? = null,
    @SerialName("custom_name") val customName: String? = null,
    val exercises: Nm? = null
) {
    @Serializable
    data class Nm(val name: String? = null)
}

@Serializable
private data class SetWire(
    val id: Int = 0,
    @SerialName("workout_exercise_id") val workoutExerciseId: Int,
    @SerialName("set_number") val setNumber: Int,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null,
    @SerialName("weight_segments") val weightSegments: JsonArray? = null
)

private val j = Json { ignoreUnknownKeys = true }

@Serializable
private data class VolWire(@SerialName("total_volume_kg") val totalVolumeKg: Double? = null)

private fun decodeVolumeRow(raw: String): VolWire? {
    val t = raw.trim()
    if (t.isBlank()) return null
    return runCatching {
        if (t.startsWith("[")) j.decodeFromString<List<VolWire>>(t).firstOrNull()
        else j.decodeFromString<VolWire>(t)
    }.getOrNull()
}

private fun fmtNum(w: Double): String =
    if (floor(w) == w) w.toInt().toString() else String.format(java.util.Locale.US, "%.1f", w)

data class StrengthEditLoadResult(
    val exercises: List<StrengthExerciseDraft>,
    val initialWorkoutExerciseIds: Set<Int>
)

/**
 * Carga filas de [workout_exercises] + [exercise_sets] (paridad con iOS [EditWorkoutMetaSheet] strength).
 */
suspend fun loadStrengthEditsForWorkout(
    supabase: SupabaseClient,
    workoutId: Int
): StrengthEditLoadResult? {
    val exs = runCatching {
        val r = supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES)
            .select(
                columns = Columns.raw("id, exercise_id, order_index, notes, custom_name, exercises(name)"),
            ) {
                filter { eq("workout_id", workoutId) }
                order("order_index", Order.ASCENDING)
            }
        j.decodeFromString<List<WExWire>>(jsonArrayData(r.data))
    }.getOrNull() ?: return null
    if (exs.isEmpty()) {
        return StrengthEditLoadResult(emptyList(), emptySet())
    }
    val exIds = exs.map { it.id }
    var setsByEx: Map<Int, List<StrengthSetDraft>> = emptyMap()
    if (exIds.isNotEmpty()) {
        val sData = runCatching {
            supabase.from(BackendContracts.Tables.EXERCISE_SETS)
                .select(
                    columns = Columns.raw(
                        "id, workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec, weight_segments"
                    )
                ) {
                    filter { isIn("workout_exercise_id", exIds) }
                    order("set_number", Order.ASCENDING)
                    order("id", Order.ASCENDING)
                }
        }.getOrNull() ?: return null
        val sRows = runCatching { j.decodeFromString<List<SetWire>>(jsonArrayData(sData.data)) }
            .getOrNull() ?: return null
        setsByEx = sRows.groupBy({ it.workoutExerciseId }, { s ->
            val segs = parseWeightSegmentsColumn(s.weightSegments)
            val r0 = segs.firstOrNull()?.repsText ?: s.reps?.toString() ?: "8"
            val w0 = segs.firstOrNull()?.weightText ?: s.weightKg?.let { fmtNum(it) } ?: ""
            StrengthSetDraft(
                setNumber = s.setNumber.coerceIn(1, 99),
                repsText = r0,
                weightText = w0,
                rpeText = s.rpe?.let { fmtNum(it) } ?: "",
                restSecText = s.restSec?.toString() ?: "",
                segments = segs
            )
        })
    }
    val rows = exs.map { ex ->
        val catalog = ex.exercises?.name?.trim().orEmpty()
        StrengthExerciseDraft(
            id = UUID.randomUUID().toString(),
            workoutExerciseId = ex.id,
            exerciseId = ex.exerciseId,
            exerciseName = catalog,
            customName = ex.customName?.trim() ?: "",
            notes = ex.notes?.trim() ?: "",
            sets = setsByEx[ex.id]?.ifEmpty { null } ?: listOf(StrengthSetDraft())
        )
    }
    return StrengthEditLoadResult(rows, exIds.toSet())
}

private fun jsonArrayData(raw: String): String =
    when {
        raw.isBlank() -> "[]"
        raw.trimStart().startsWith("[") -> raw
        else -> "[$raw]"
    }

data class StrengthReadonlySetLine(
    val setNumber: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val weightSegments: List<StrengthSegmentDraft> = emptyList()
)

data class StrengthReadonlyExerciseLine(
    val id: Int,
    val orderIndex: Int,
    val title: String,
    val notes: String?,
    val sets: List<StrengthReadonlySetLine>
)

/** Solo lectura: paridad con iOS [StrengthDetailBlock]. */
data class StrengthReadonlyDetail(
    val exercises: List<StrengthReadonlyExerciseLine>,
    val totalVolumeKg: Double?
)

/**
 * Carga ejercicios + series + volumen para la ficha de detalle (sin editor).
 */
suspend fun loadStrengthReadonlyForDetail(
    supabase: SupabaseClient,
    workoutId: Int
): StrengthReadonlyDetail? {
    val exs = runCatching {
        val r = supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES)
            .select(
                columns = Columns.raw("id, exercise_id, order_index, notes, custom_name, exercises(name)"),
            ) {
                filter { eq("workout_id", workoutId) }
                order("order_index", Order.ASCENDING)
            }
        j.decodeFromString<List<WExWire>>(jsonArrayData(r.data))
    }.getOrNull() ?: return null
    val setsByEx: Map<Int, List<StrengthReadonlySetLine>> =
        if (exs.isEmpty()) {
            emptyMap()
        } else {
            val exIds = exs.map { it.id }
            val sData = runCatching {
                supabase.from(BackendContracts.Tables.EXERCISE_SETS)
                    .select(
                        columns = Columns.raw(
                            "id, workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec, weight_segments"
                        )
                    ) {
                        filter { isIn("workout_exercise_id", exIds) }
                        order("set_number", Order.ASCENDING)
                        order("id", Order.ASCENDING)
                    }
            }.getOrNull() ?: return null
            val sRows = runCatching { j.decodeFromString<List<SetWire>>(jsonArrayData(sData.data)) }
                .getOrNull() ?: return null
            sRows.groupBy({ it.workoutExerciseId }, { s ->
                val segs = parseWeightSegmentsColumn(s.weightSegments)
                StrengthReadonlySetLine(
                    setNumber = s.setNumber,
                    reps = s.reps,
                    weightKg = s.weightKg,
                    rpe = s.rpe,
                    restSec = s.restSec,
                    weightSegments = segs
                )
            })
        }
    val lines = exs.map { ex ->
        val catalog = ex.exercises?.name?.trim().orEmpty()
        val title = ex.customName?.trim()?.takeIf { it.isNotEmpty() } ?: catalog.ifEmpty {
            "Exercise #${ex.exerciseId}"
        }
        StrengthReadonlyExerciseLine(
            id = ex.id,
            orderIndex = ex.orderIndex,
            title = title,
            notes = ex.notes?.trim()?.takeIf { it.isNotEmpty() },
            sets = setsByEx[ex.id].orEmpty()
        )
    }
    val vol = runCatching {
        val r = supabase.from(BackendContracts.Views.VW_WORKOUT_VOLUME)
            .select(columns = Columns.raw("total_volume_kg")) {
                filter { eq("workout_id", workoutId) }
            }
        decodeVolumeRow(r.data)?.totalVolumeKg
    }.getOrNull()
    return StrengthReadonlyDetail(exercises = lines, totalVolumeKg = vol)
}
