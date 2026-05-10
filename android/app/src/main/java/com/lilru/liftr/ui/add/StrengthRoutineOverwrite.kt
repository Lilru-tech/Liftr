package com.lilru.liftr.ui.add

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Instant
import java.util.Locale
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
data class StrengthProgramSet(
    val setNumber: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val notes: String?
)

data class StrengthProgramItem(
    val exerciseId: Long,
    val orderIndex: Int,
    val notes: String?,
    val customName: String?,
    val sets: List<StrengthProgramSet>
)

data class StrengthRoutineOverwriteDiffLine(
    val id: String,
    val exerciseContext: String,
    val exerciseTitle: String,
    val setNumber: Int,
    val exerciseOrderIndex: Int,
    val fieldTitle: String,
    val oldValue: String,
    val newValue: String
)

data class StrengthRoutineOverwritePrompt(
    val routineId: Long,
    val routineName: String,
    val diffLines: List<StrengthRoutineOverwriteDiffLine>
)

/** Shared with [AddWorkoutViewModel.buildStrengthPayloadItems]. */
internal data class StrengthSetPayload(
    val setNumber: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val notes: String?
)

sealed class StrengthRoutineOverwriteCandidate {
    data object None : StrengthRoutineOverwriteCandidate()
    data class Prompt(val value: StrengthRoutineOverwritePrompt) : StrengthRoutineOverwriteCandidate()
}

data class StrengthCreateWorkoutParams(
    val title: String,
    val notes: String,
    val durationMin: Int?,
    val intensity: AddWorkoutIntensity,
    val state: AddWorkoutState,
    val startedAtIso: String?,
    val endedAtIso: String?,
    val useCustomSchedule: Boolean,
    val scheduleEndedEnabled: Boolean
)

data class StrengthRoutineOverwritePending(
    val prompt: StrengthRoutineOverwritePrompt,
    val createParams: StrengthCreateWorkoutParams,
    val exercisesSnapshot: List<StrengthExerciseDraft>
)

private fun sha256Hex(text: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(StandardCharsets.UTF_8))
    return digest.joinToString("") { b -> "%02x".format(b) }
}

private fun customNameForFingerprint(ex: StrengthExerciseDraft): String {
    val c = ex.customName.trim()
    if (c.isNotEmpty()) return c
    return ex.exerciseName.trim()
}

/**
 * Matches iOS [strengthRoutineContentFingerprint] (AddWorkout / StrengthRoutineOverwrite.swift).
 */
fun strengthRoutineContentFingerprintFromDrafts(exercises: List<StrengthExerciseDraft>): String {
    val items = strengthProgramItemsFromDrafts(exercises) ?: return sha256Hex("")
    return strengthRoutineContentFingerprintFromItems(items)
}

fun strengthRoutineContentFingerprintFromItems(items: List<StrengthProgramItem>): String {
    val sorted = items.sortedBy { it.orderIndex }
    val lines = sorted.map { item ->
        val setParts = item.sets.sortedBy { it.setNumber }.map { s ->
            val w = s.weightKg?.toString() ?: ""
            val r = s.rpe?.toString() ?: ""
            val rest = s.restSec?.toString() ?: ""
            val rep = s.reps?.toString() ?: ""
            val n = s.notes ?: ""
            "${s.setNumber}|$rep|$w|$r|$rest|$n"
        }
        val cn = item.customName ?: ""
        val note = item.notes ?: ""
        "${item.exerciseId}|${item.orderIndex}|$cn|$note|${setParts.joinToString(";")}"
    }
    return sha256Hex(lines.joinToString("\n"))
}

fun strengthRoutineStructureFingerprintFromItems(items: List<StrengthProgramItem>): String {
    val sorted = items.sortedBy { it.orderIndex }
    val lines = sorted.map { item ->
        val cn = (item.customName ?: "").trim()
        val note = (item.notes ?: "").trim()
        "${item.exerciseId}|${item.orderIndex}|$cn|${note}|${item.sets.size}"
    }
    return sha256Hex(lines.joinToString("\n"))
}

fun strengthProgramItemsFromDrafts(exercises: List<StrengthExerciseDraft>): List<StrengthProgramItem>? {
    if (exercises.any { it.exerciseId == null }) return null
    val out = mutableListOf<StrengthProgramItem>()
    exercises.forEachIndexed { exerciseIndex, exercise ->
        val exId = exercise.exerciseId ?: return null
        val validSets = exercise.sets.mapNotNull { set ->
            val reps = set.repsText.trim().toIntOrNull()
            val weight = set.weightText.trim().replace(",", ".").toDoubleOrNull()
            val rpe = set.rpeText.trim().replace(",", ".").toDoubleOrNull()
            val restSec = set.restSecText.trim().toIntOrNull()
            val notes = set.notes.trim()
            if ((reps == null || reps <= 0) && weight == null && rpe == null && restSec == null && notes.isBlank()) {
                return@mapNotNull null
            }
            val safeReps = reps?.takeIf { it > 0 }
            StrengthProgramSet(
                setNumber = set.setNumber.coerceIn(1, 99),
                reps = safeReps,
                weightKg = weight,
                rpe = rpe,
                restSec = restSec,
                notes = notes.ifBlank { null }
            )
        }
        if (validSets.isEmpty()) return null
        val cn = customNameForFingerprint(exercise).ifBlank { null }
        val note = exercise.notes.trim().ifBlank { null }
        out.add(
            StrengthProgramItem(
                exerciseId = exId,
                orderIndex = exerciseIndex + 1,
                notes = note,
                customName = cn,
                sets = validSets
            )
        )
    }
    return out
}

private fun structuresMatch(a: List<StrengthProgramItem>, b: List<StrengthProgramItem>): Boolean =
    strengthRoutineStructureFingerprintFromItems(a) == strengthRoutineStructureFingerprintFromItems(b)

private fun displayNameForDiff(exerciseName: String, item: StrengthProgramItem): String {
    val cn = (item.customName ?: "").trim()
    if (cn.isNotEmpty()) return cn
    val trimmed = exerciseName.trim()
    if (trimmed.isNotEmpty()) return trimmed
    return "Exercise ${item.exerciseId}"
}

private fun formatWeight(d: Double?): String {
    if (d == null) return "—"
    val i = d.toInt()
    return if (d == i.toDouble()) i.toString() else d.toString()
}

private fun formatRpe(d: Double?): String {
    if (d == null) return "—"
    return String.format(Locale.US, "%.1f", d)
}

private fun buildDiffLines(
    proposed: List<StrengthProgramItem>,
    routine: List<StrengthProgramItem>,
    exerciseDisplayName: (Long) -> String
): List<StrengthRoutineOverwriteDiffLine> {
    val lines = mutableListOf<StrengthRoutineOverwriteDiffLine>()
    val prop = proposed.sortedBy { it.orderIndex }
    val rout = routine.sortedBy { it.orderIndex }
    for (i in prop.indices) {
        val pEx = prop[i]
        val rEx = rout[i]
        val exLabel = displayNameForDiff(exerciseDisplayName(pEx.exerciseId), pEx)
        val setsP = pEx.sets.sortedBy { it.setNumber }
        val setsR = rEx.sets.sortedBy { it.setNumber }
        for (j in setsP.indices) {
            val ps = setsP[j]
            val rs = setsR[j]
            val setLabel = "$exLabel · Set ${ps.setNumber}"
            val baseId = "${pEx.exerciseId}-${ps.setNumber}"
            if (ps.reps != rs.reps) {
                lines.add(
                    StrengthRoutineOverwriteDiffLine(
                        id = "$baseId-reps",
                        exerciseContext = setLabel,
                        exerciseTitle = exLabel,
                        setNumber = ps.setNumber,
                        exerciseOrderIndex = pEx.orderIndex,
                        fieldTitle = "Reps",
                        oldValue = rs.reps?.toString() ?: "—",
                        newValue = ps.reps?.toString() ?: "—"
                    )
                )
            }
            if (ps.weightKg != rs.weightKg) {
                lines.add(
                    StrengthRoutineOverwriteDiffLine(
                        id = "$baseId-kg",
                        exerciseContext = setLabel,
                        exerciseTitle = exLabel,
                        setNumber = ps.setNumber,
                        exerciseOrderIndex = pEx.orderIndex,
                        fieldTitle = "Weight",
                        oldValue = "${formatWeight(rs.weightKg)} kg",
                        newValue = "${formatWeight(ps.weightKg)} kg"
                    )
                )
            }
            if (ps.rpe != rs.rpe) {
                lines.add(
                    StrengthRoutineOverwriteDiffLine(
                        id = "$baseId-rpe",
                        exerciseContext = setLabel,
                        exerciseTitle = exLabel,
                        setNumber = ps.setNumber,
                        exerciseOrderIndex = pEx.orderIndex,
                        fieldTitle = "RPE",
                        oldValue = formatRpe(rs.rpe),
                        newValue = formatRpe(ps.rpe)
                    )
                )
            }
            if (ps.restSec != rs.restSec) {
                lines.add(
                    StrengthRoutineOverwriteDiffLine(
                        id = "$baseId-rest",
                        exerciseContext = setLabel,
                        exerciseTitle = exLabel,
                        setNumber = ps.setNumber,
                        exerciseOrderIndex = pEx.orderIndex,
                        fieldTitle = "Rest",
                        oldValue = rs.restSec?.let { "$it s" } ?: "—",
                        newValue = ps.restSec?.let { "$it s" } ?: "—"
                    )
                )
            }
            val pn = (ps.notes ?: "").trim()
            val rn = (rs.notes ?: "").trim()
            if (pn != rn) {
                lines.add(
                    StrengthRoutineOverwriteDiffLine(
                        id = "$baseId-notes",
                        exerciseContext = setLabel,
                        exerciseTitle = exLabel,
                        setNumber = ps.setNumber,
                        exerciseOrderIndex = pEx.orderIndex,
                        fieldTitle = "Set notes",
                        oldValue = if (rn.isEmpty()) "—" else rn,
                        newValue = if (pn.isEmpty()) "—" else pn
                    )
                )
            }
        }
    }
    return lines
}

@Serializable
private data class RoutineFullRow(
    val id: Long,
    val name: String,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("strength_routine_exercises") val exercises: List<RoutineExWire>? = null
)

@Serializable
private data class RoutineExWire(
    @SerialName("exercise_id") val exerciseId: Long,
    @SerialName("order_index") val orderIndex: Int,
    val notes: String? = null,
    @SerialName("custom_name") val customName: String? = null,
    @SerialName("strength_routine_sets") val sets: List<RoutineSetWire>? = null
)

@Serializable
private data class RoutineSetWire(
    @SerialName("set_number") val setNumber: Int,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null,
    val notes: String? = null
)

private fun programItemsFromRoutineRow(row: RoutineFullRow): List<StrengthProgramItem> {
    val exs = (row.exercises ?: emptyList()).sortedBy { it.orderIndex }
    return exs.map { ex ->
        val setsSorted = (ex.sets ?: emptyList()).sortedBy { it.setNumber }
        StrengthProgramItem(
            exerciseId = ex.exerciseId,
            orderIndex = ex.orderIndex,
            notes = ex.notes,
            customName = ex.customName,
            sets = setsSorted.map { s ->
                StrengthProgramSet(
                    setNumber = s.setNumber,
                    reps = s.reps,
                    weightKg = s.weightKg,
                    rpe = s.rpe,
                    restSec = s.restSec,
                    notes = s.notes
                )
            }
        )
    }
}

private const val ROUTINE_FULL_SELECT =
    "id,name,updated_at,strength_routine_exercises(exercise_id,order_index,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes))"

suspend fun fetchStrengthRoutineOverwriteCandidate(
    supabase: SupabaseClient,
    userId: String,
    proposed: List<StrengthProgramItem>,
    exerciseDisplayName: (Long) -> String
): StrengthRoutineOverwriteCandidate {
    if (proposed.isEmpty()) return StrengthRoutineOverwriteCandidate.None
    val proposedContent = strengthRoutineContentFingerprintFromItems(proposed)
    val res = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).select(columns = Columns.raw(ROUTINE_FULL_SELECT)) {
        filter { eq("user_id", userId) }
    }
    val dec = Json { ignoreUnknownKeys = true }
    val rows: List<RoutineFullRow> = runCatching {
        when (val root = Json.parseToJsonElement(res.data)) {
            is JsonArray -> root.map { dec.decodeFromString<RoutineFullRow>(it.toString()) }
            is JsonObject -> listOf(dec.decodeFromString<RoutineFullRow>(root.toString()))
            else -> emptyList()
        }
    }.getOrElse { emptyList() }
    if (rows.isEmpty()) return StrengthRoutineOverwriteCandidate.None

    data class Match(val row: RoutineFullRow, val items: List<StrengthProgramItem>, val contentHash: String)
    val matches = mutableListOf<Match>()
    for (row in rows) {
        val items = programItemsFromRoutineRow(row)
        if (items.isEmpty()) continue
        if (!structuresMatch(proposed, items)) continue
        val ch = strengthRoutineContentFingerprintFromItems(items)
        if (ch == proposedContent) continue
        matches.add(Match(row, items, ch))
    }
    if (matches.isEmpty()) return StrengthRoutineOverwriteCandidate.None

    val best = matches.maxWith(compareBy<Match> { m ->
        m.row.updatedAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: Instant.EPOCH
    }.thenBy { it.row.id })

    val diff = buildDiffLines(proposed, best.items, exerciseDisplayName)
    if (diff.isEmpty()) return StrengthRoutineOverwriteCandidate.None
    return StrengthRoutineOverwriteCandidate.Prompt(
        StrengthRoutineOverwritePrompt(
            routineId = best.row.id,
            routineName = best.row.name,
            diffLines = diff
        )
    )
}

suspend fun applyStrengthRoutinePrescriptionUpdate(
    supabase: SupabaseClient,
    userId: String,
    routineId: Long,
    exercises: List<StrengthExerciseDraft>
) {
    val payloadItems = buildStrengthPayloadItemsForRoutineUpdate(exercises)
    val contentHash = strengthRoutineContentFingerprintFromDrafts(exercises)

    val existingRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES).select(
        columns = Columns.raw("id")
    ) {
        filter { eq("routine_id", routineId) }
    }
    val existingIds = runCatching {
        parseRoutineExerciseRows(existingRes.data).map { it.id }
    }.getOrElse { emptyList() }

    if (existingIds.isNotEmpty()) {
        val idInts = existingIds.map { it.toInt() }
        supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_SETS).delete {
            filter { isIn("routine_exercise_id", idInts) }
        }
    }
    supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES).delete {
        filter { eq("routine_id", routineId) }
    }

    for ((exerciseIndex, pair) in payloadItems.withIndex()) {
        val exercise = pair.first
        val eid = exercise.exerciseId ?: error("Missing exercise_id")
        val routineExPayload = buildJsonObject {
            put("routine_id", routineId)
            put("exercise_id", eid)
            put("order_index", exerciseIndex + 1)
            if (exercise.notes.isNotBlank()) put("notes", JsonPrimitive(exercise.notes.trim()))
            if (exercise.customName.isNotBlank()) {
                put("custom_name", JsonPrimitive(exercise.customName.trim()))
            }
        }
        supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES).insert(routineExPayload) { }
    }

    val insertedRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES).select(
        columns = Columns.raw("id, routine_id, exercise_id, order_index, notes, custom_name")
    ) {
        filter { eq("routine_id", routineId) }
        order("order_index", Order.ASCENDING)
    }
    val insertedRows = parseRoutineExerciseRows(insertedRes.data)

    insertedRows.forEachIndexed { index, row ->
        val validSets = payloadItems.getOrNull(index)?.second ?: return@forEachIndexed
        for (set in validSets) {
            val setPayload = buildJsonObject {
                put("routine_exercise_id", row.id)
                put("set_number", set.setNumber.coerceIn(1, 99))
                if (set.reps != null) put("reps", set.reps)
                if (set.weightKg != null) put("weight_kg", set.weightKg)
                if (set.rpe != null) put("rpe", set.rpe)
                if (set.restSec != null) put("rest_sec", set.restSec)
                set.notes?.let { put("notes", JsonPrimitive(it)) }
            }
            supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_SETS).insert(setPayload) { }
        }
    }

    supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).update(
        buildJsonObject {
            put("content_hash", JsonPrimitive(contentHash))
        }
    ) {
        filter {
            eq("id", routineId)
            eq("user_id", userId)
        }
    }
}

private data class RoutineExerciseRowParsed(val id: Long)

private fun parseRoutineExerciseRows(raw: String): List<RoutineExerciseRowParsed> {
    val root = Json.parseToJsonElement(raw)
    val arr = when (root) {
        is JsonArray -> root
        is JsonObject -> JsonArray(listOf(root))
        else -> JsonArray(emptyList())
    }
    return arr.mapNotNull { el ->
        val o = el.jsonObject
        val id = o["id"]?.let { it as? JsonPrimitive }?.longOrNull ?: return@mapNotNull null
        RoutineExerciseRowParsed(id)
    }
}

/** Same validation as [AddWorkoutViewModel.buildStrengthPayloadItems] but public for routine patch. */
internal fun buildStrengthPayloadItemsForRoutineUpdate(
    exercises: List<StrengthExerciseDraft>
): List<Pair<StrengthExerciseDraft, List<StrengthSetPayload>>> {
    if (exercises.any { it.exerciseId == null }) {
        error("Choose a movement for each exercise (Exercise field).")
    }
    if (exercises.any { it.sets.isEmpty() }) {
        error("Each exercise needs at least one set.")
    }
    return exercises.map { exercise ->
        val exId = exercise.exerciseId ?: error("Missing exercise_id")
        if (exId <= 0L) error("Invalid exercise.")
        val validSets = exercise.sets.mapNotNull { set ->
            val reps = set.repsText.trim().toIntOrNull()
            val weight = set.weightText.trim().replace(",", ".").toDoubleOrNull()
            val rpe = set.rpeText.trim().replace(",", ".").toDoubleOrNull()
            val restSec = set.restSecText.trim().toIntOrNull()
            val notes = set.notes.trim()
            if ((reps == null || reps <= 0) && weight == null && rpe == null && restSec == null && notes.isBlank()) {
                return@mapNotNull null
            }
            val safeReps = reps?.takeIf { it > 0 }
            StrengthSetPayload(
                setNumber = set.setNumber.coerceIn(1, 99),
                reps = safeReps,
                weightKg = weight,
                rpe = rpe,
                restSec = restSec,
                notes = notes.ifBlank { null }
            )
        }
        if (validSets.isEmpty()) {
            error("Each exercise must contain at least one set with reps > 0 or additional valid fields.")
        }
        exercise to validSets
    }
}
