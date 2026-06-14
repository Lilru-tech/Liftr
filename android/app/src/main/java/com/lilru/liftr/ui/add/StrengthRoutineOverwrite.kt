package com.lilru.liftr.ui.add

import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.domain.strengthSetMultiplicities
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
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
data class StrengthProgramSet(
    val setNumber: Int,
    val rowOrder: Int = setNumber,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val notes: String?,
    val weightSegments: List<StrengthSegmentPayload>? = null
)

data class StrengthProgramItem(
    val exerciseId: Long,
    val orderIndex: Int,
    val notes: String?,
    val customName: String?,
    val supersetGroupId: String? = null,
    val supersetPosition: Int? = null,
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
    val diffLines: List<StrengthRoutineOverwriteDiffLine>,
    val routineBaselineItems: List<StrengthProgramItem>
)

fun actionableOverwriteDiffLineIds(lines: List<StrengthRoutineOverwriteDiffLine>): Set<String> =
    lines.filter { it.fieldTitle != "Sets" }.map { it.id }.toSet()

private fun deepCopyProgramSet(s: StrengthProgramSet): StrengthProgramSet =
    s.copy(weightSegments = s.weightSegments?.map { it.copy() })

private fun deepCopyProgramItem(item: StrengthProgramItem): StrengthProgramItem =
    item.copy(sets = item.sets.map { deepCopyProgramSet(it) })

private fun renumberExpandedSets(sets: List<StrengthProgramSet>): List<StrengthProgramSet> =
    sets.sortedBy { it.setNumber }.mapIndexed { idx, s ->
        s.copy(setNumber = idx + 1, rowOrder = idx + 1)
    }

fun collapseStrengthProgramSetsForStorage(sets: List<StrengthProgramSet>): List<StrengthProgramSet> {
    val sorted = sets.sortedBy { it.setNumber }
    if (sorted.isEmpty()) return emptyList()
    val out = mutableListOf<StrengthProgramSet>()
    var i = 0
    while (i < sorted.size) {
        var count = 1
        while (i + count < sorted.size &&
            !strengthProgramSetPrescriptionDiffers(sorted[i], sorted[i + count])
        ) {
            count += 1
        }
        val template = sorted[i]
        out.add(
            template.copy(
                setNumber = count,
                rowOrder = out.size + 1,
                weightSegments = template.weightSegments?.map { it.copy() }
            )
        )
        i += count
    }
    return out
}

fun collapseStrengthProgramItemsForStorage(items: List<StrengthProgramItem>): List<StrengthProgramItem> =
    items.sortedBy { it.orderIndex }.map { item ->
        item.copy(sets = collapseStrengthProgramSetsForStorage(item.sets))
    }

private fun overwriteDiffLineApplicationRank(fieldTitle: String): Int = when (fieldTitle) {
    "Removed exercise" -> 0
    "Added exercise" -> 1
    "Exercise" -> 2
    "Removed set" -> 3
    "Added set" -> 4
    "Reps" -> 10
    "Weight" -> 11
    "RPE" -> 12
    "Rest" -> 13
    "Drop steps" -> 14
    "Set notes" -> 15
    "Prescription" -> 100
    else -> 50
}

private fun exerciseIndexInMerged(merged: List<StrengthProgramItem>, orderIndex: Int): Int? =
    merged.indexOfFirst { it.orderIndex == orderIndex }.takeIf { it >= 0 }

private fun sortedSetsForMerge(sets: List<StrengthProgramSet>): List<StrengthProgramSet> =
    sets.sortedBy { it.setNumber }

private fun applyOverwriteDiffLine(
    line: StrengthRoutineOverwriteDiffLine,
    merged: MutableList<StrengthProgramItem>,
    proposedExpanded: List<StrengthProgramItem>
) {
    when (line.fieldTitle) {
        "Prescription" -> return
        "Removed exercise" -> {
            val idx = exerciseIndexInMerged(merged, line.exerciseOrderIndex) ?: return
            merged.removeAt(idx)
            merged.forEachIndexed { offset, item ->
                merged[offset] = deepCopyProgramItem(item).copy(orderIndex = offset + 1)
            }
        }
        "Added exercise" -> {
            val src = proposedExpanded.firstOrNull { it.orderIndex == line.exerciseOrderIndex } ?: return
            merged.add(deepCopyProgramItem(src))
            merged.sortBy { it.orderIndex }
        }
        "Exercise" -> {
            val idx = exerciseIndexInMerged(merged, line.exerciseOrderIndex) ?: return
            val src = proposedExpanded.firstOrNull { it.orderIndex == line.exerciseOrderIndex } ?: return
            merged[idx] = deepCopyProgramItem(src)
        }
        "Removed set" -> {
            val exIdx = exerciseIndexInMerged(merged, line.exerciseOrderIndex) ?: return
            if (line.setNumber <= 0) return
            val sets = sortedSetsForMerge(merged[exIdx].sets).toMutableList()
            if (line.setNumber > sets.size) return
            sets.removeAt(line.setNumber - 1)
            merged[exIdx] = merged[exIdx].copy(sets = renumberExpandedSets(sets))
        }
        "Added set" -> {
            val exIdx = exerciseIndexInMerged(merged, line.exerciseOrderIndex) ?: return
            val propEx = proposedExpanded.firstOrNull { it.orderIndex == line.exerciseOrderIndex } ?: return
            if (line.setNumber <= 0) return
            val propSets = sortedSetsForMerge(propEx.sets)
            if (line.setNumber > propSets.size) return
            val newSet = deepCopyProgramSet(propSets[line.setNumber - 1])
            val sets = sortedSetsForMerge(merged[exIdx].sets).toMutableList()
            when {
                line.setNumber - 1 == sets.size -> sets.add(newSet)
                line.setNumber - 1 < sets.size -> sets.add(line.setNumber - 1, newSet)
                else -> return
            }
            merged[exIdx] = merged[exIdx].copy(sets = renumberExpandedSets(sets))
        }
        "Reps", "Weight", "RPE", "Rest", "Set notes", "Drop steps" -> {
            val exIdx = exerciseIndexInMerged(merged, line.exerciseOrderIndex) ?: return
            val propEx = proposedExpanded.firstOrNull { it.orderIndex == line.exerciseOrderIndex } ?: return
            if (line.setNumber <= 0) return
            val propSets = sortedSetsForMerge(propEx.sets)
            if (line.setNumber > propSets.size) return
            val propSet = propSets[line.setNumber - 1]
            val sets = sortedSetsForMerge(merged[exIdx].sets).toMutableList()
            if (line.setNumber > sets.size) return
            val target = sets[line.setNumber - 1]
            val updated = when (line.fieldTitle) {
                "Reps" -> target.copy(reps = propSet.reps)
                "Weight" -> target.copy(weightKg = propSet.weightKg)
                "RPE" -> target.copy(rpe = propSet.rpe)
                "Rest" -> target.copy(restSec = propSet.restSec)
                "Set notes" -> target.copy(notes = propSet.notes)
                "Drop steps" -> target.copy(weightSegments = propSet.weightSegments?.map { it.copy() })
                else -> target
            }
            sets[line.setNumber - 1] = updated
            merged[exIdx] = merged[exIdx].copy(sets = sets)
        }
    }
}

fun mergeStrengthRoutineWithSelectedChanges(
    routine: List<StrengthProgramItem>,
    proposed: List<StrengthProgramItem>,
    selectedLineIds: Set<String>
): List<StrengthProgramItem> {
    if (selectedLineIds.contains("prescription-fallback")) {
        return collapseStrengthProgramItemsForStorage(
            expandedStrengthProgramItemsForCompare(normalizedProgramItemsForCompare(proposed))
        )
    }
    val merged = expandedStrengthProgramItemsForCompare(
        normalizedProgramItemsForCompare(routine)
    ).map { deepCopyProgramItem(it) }.toMutableList()
    val proposedExpanded = expandedStrengthProgramItemsForCompare(
        normalizedProgramItemsForCompare(proposed)
    )
    val sorted = buildStrengthRoutineOverwriteDiffLines(proposed, routine) { "" }
        .filter { it.fieldTitle != "Sets" && selectedLineIds.contains(it.id) }
        .sortedWith(
            compareBy<StrengthRoutineOverwriteDiffLine> { overwriteDiffLineApplicationRank(it.fieldTitle) }
                .thenBy { it.exerciseOrderIndex }
                .thenBy { it.setNumber }
                .thenBy { it.id }
        )
    for (line in sorted) {
        applyOverwriteDiffLine(line, merged, proposedExpanded)
    }
    merged.forEachIndexed { offset, item ->
        merged[offset] = deepCopyProgramItem(item).copy(orderIndex = offset + 1)
    }
    return collapseStrengthProgramItemsForStorage(merged)
}

fun mergedStrengthRoutineProgramItemsForOverwrite(
    prompt: StrengthRoutineOverwritePrompt,
    proposed: List<StrengthProgramItem>,
    selectedLineIds: Set<String>
): List<StrengthProgramItem> =
    mergeStrengthRoutineWithSelectedChanges(prompt.routineBaselineItems, proposed, selectedLineIds)

data class StrengthSegmentPayload(val reps: Int, val weightKg: Double)

/** Shared with [AddWorkoutViewModel.buildStrengthPayloadItems]. */
internal data class StrengthSetPayload(
    val setNumber: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val notes: String?,
    val weightSegments: List<StrengthSegmentPayload>? = null
)

internal fun weightSegmentsToJsonArray(segs: List<StrengthSegmentPayload>): JsonArray =
    buildJsonArray {
        segs.forEach { s ->
            add(
                buildJsonObject {
                    put("reps", s.reps)
                    put("weight_kg", s.weightKg)
                }
            )
        }
    }

internal fun draftSetToStrengthPayload(set: StrengthSetDraft): StrengthSetPayload? {
    val rpe = set.rpeText.trim().replace(',', '.').toDoubleOrNull()
    val restSec = set.restSecText.trim().toIntOrNull()
    val notes = set.notes.trim()
    if (set.segments.size >= 2) {
        val parsed = set.segments.mapNotNull { seg ->
            val r = seg.repsText.trim().toIntOrNull()?.takeIf { it > 0 } ?: return@mapNotNull null
            val w = seg.weightText.trim().replace(',', '.').toDoubleOrNull() ?: 0.0
            StrengthSegmentPayload(r, w)
        }
        if (parsed.size != set.segments.size || parsed.size < 2) return null
        val first = parsed.first()
        return StrengthSetPayload(
            setNumber = set.setNumber.coerceIn(1, 99),
            reps = first.reps,
            weightKg = first.weightKg,
            rpe = rpe,
            restSec = restSec,
            notes = notes.ifBlank { null },
            weightSegments = parsed
        )
    }
    val reps = set.repsText.trim().toIntOrNull()
    val weight = set.weightText.trim().replace(',', '.').toDoubleOrNull()
    if ((reps == null || reps <= 0) && weight == null && rpe == null && restSec == null && notes.isBlank()) {
        return null
    }
    return StrengthSetPayload(
        setNumber = set.setNumber.coerceIn(1, 99),
        reps = reps?.takeIf { it > 0 },
        weightKg = weight,
        rpe = rpe,
        restSec = restSec,
        notes = notes.ifBlank { null },
        weightSegments = null
    )
}

internal fun strengthProgramSetFromPayload(p: StrengthSetPayload, rowOrder: Int = p.setNumber): StrengthProgramSet =
    StrengthProgramSet(
        setNumber = p.setNumber,
        rowOrder = rowOrder,
        reps = p.reps,
        weightKg = p.weightKg,
        rpe = p.rpe,
        restSec = p.restSec,
        notes = p.notes,
        weightSegments = p.weightSegments
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

internal fun strengthRoutineContentFingerprintFromItems(items: List<StrengthProgramItem>): String {
    val sorted = expandedStrengthProgramItemsForCompare(items).sortedBy { it.orderIndex }
    val lines = sorted.map { item ->
        val setParts = item.sets.sortedBy { it.setNumber }.map { s ->
            val w = s.weightKg?.toString() ?: ""
            val r = s.rpe?.toString() ?: ""
            val rest = s.restSec?.toString() ?: ""
            val rep = s.reps?.toString() ?: ""
            val n = s.notes ?: ""
            val seg = s.weightSegments?.joinToString("|") { e -> "${e.reps}x${e.weightKg}" } ?: ""
            "${s.setNumber}|$rep|$w|$r|$rest|$n|$seg"
        }
        val cn = item.customName ?: ""
        val note = item.notes ?: ""
        val sg = item.supersetGroupId ?: ""
        val sp = item.supersetPosition?.toString() ?: ""
        "${item.exerciseId}|${item.orderIndex}|$cn|$note|$sg|$sp|${setParts.joinToString(";")}"
    }
    return sha256Hex(lines.joinToString("\n"))
}

internal fun strengthRoutineStructureFingerprintFromItems(items: List<StrengthProgramItem>): String {
    val sorted = items.sortedBy { it.orderIndex }
    return sha256Hex(sorted.joinToString("\n") { it.exerciseId.toString() })
}

internal fun normalizedProgramItemsForCompare(items: List<StrengthProgramItem>): List<StrengthProgramItem> =
    items.sortedBy { it.orderIndex }.mapIndexed { idx, item ->
        StrengthProgramItem(
            exerciseId = item.exerciseId,
            orderIndex = idx + 1,
            notes = item.notes,
            customName = item.customName,
            supersetGroupId = item.supersetGroupId,
            supersetPosition = item.supersetPosition,
            sets = item.sets
        )
    }

internal fun strengthProgramItemsFromDrafts(exercises: List<StrengthExerciseDraft>): List<StrengthProgramItem>? {
    if (exercises.any { it.exerciseId == null }) return null
    val out = mutableListOf<StrengthProgramItem>()
    exercises.forEachIndexed { exerciseIndex, exercise ->
        val exId = exercise.exerciseId ?: return null
        val validSets = exercise.sets.mapIndexedNotNull { setIdx, set ->
            draftSetToStrengthPayload(set)?.let { payload ->
                strengthProgramSetFromPayload(payload, rowOrder = setIdx + 1)
            }
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
                supersetGroupId = exercise.supersetGroupId,
                supersetPosition = exercise.supersetPosition,
                sets = validSets
            )
        )
    }
    return out
}

internal fun expandedStrengthProgramSetsForCompare(sets: List<StrengthProgramSet>): List<StrengthProgramSet> {
    val sorted = sets.sortedWith(compareBy({ it.rowOrder }, { it.setNumber }))
    if (sorted.isEmpty()) return emptyList()
    val mults = strengthSetMultiplicities(sorted.map { it.setNumber })
    val out = mutableListOf<StrengthProgramSet>()
    var seq = 1
    for ((row, mult) in sorted.zip(mults)) {
        repeat(mult) {
            out.add(
                StrengthProgramSet(
                    setNumber = seq,
                    rowOrder = seq,
                    reps = row.reps,
                    weightKg = row.weightKg,
                    rpe = row.rpe,
                    restSec = row.restSec,
                    notes = row.notes,
                    weightSegments = row.weightSegments
                )
            )
            seq += 1
        }
    }
    return out
}

private val blankStrengthProgramSetForDiff = StrengthProgramSet(
    setNumber = 0,
    rowOrder = 0,
    reps = null,
    weightKg = null,
    rpe = null,
    restSec = null,
    notes = null,
    weightSegments = null
)

internal fun expandedStrengthProgramItemsForCompare(items: List<StrengthProgramItem>): List<StrengthProgramItem> =
    items.map { item ->
        StrengthProgramItem(
            exerciseId = item.exerciseId,
            orderIndex = item.orderIndex,
            notes = item.notes,
            customName = item.customName,
            supersetGroupId = item.supersetGroupId,
            supersetPosition = item.supersetPosition,
            sets = expandedStrengthProgramSetsForCompare(item.sets)
        )
    }

private object StrengthPrescriptionCompare {
    const val WEIGHT_EPSILON = 0.0001
    const val RPE_EPSILON = 0.001

    fun repsChanged(proposed: Int?, routine: Int?): Boolean = proposed != routine

    fun optionalDoubleChanged(proposed: Double?, routine: Double?, epsilon: Double): Boolean {
        if (proposed == null && routine == null) return false
        if (proposed == null || routine == null) return true
        return kotlin.math.abs(proposed - routine) > epsilon
    }

    fun restChanged(proposed: Int?, routine: Int?): Boolean = proposed != routine
}

internal fun exerciseStructureMatch(a: List<StrengthProgramItem>, b: List<StrengthProgramItem>): Boolean =
    strengthRoutineStructureFingerprintFromItems(a) == strengthRoutineStructureFingerprintFromItems(b)

private fun structuresMatch(a: List<StrengthProgramItem>, b: List<StrengthProgramItem>): Boolean =
    exerciseStructureMatch(a, b)

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

internal fun buildStrengthRoutineOverwriteDiffLines(
    proposed: List<StrengthProgramItem>,
    routine: List<StrengthProgramItem>,
    exerciseDisplayName: (Long) -> String
): List<StrengthRoutineOverwriteDiffLine> {
    val lines = mutableListOf<StrengthRoutineOverwriteDiffLine>()
    val prop = expandedStrengthProgramItemsForCompare(normalizedProgramItemsForCompare(proposed))
    val rout = expandedStrengthProgramItemsForCompare(normalizedProgramItemsForCompare(routine))
    val maxExercises = maxOf(prop.size, rout.size)
    for (i in 0 until maxExercises) {
        val pEx = prop.getOrNull(i)
        val rEx = rout.getOrNull(i)
        if (pEx == null && rEx != null) {
            val exLabel = displayNameForDiff(exerciseDisplayName(rEx.exerciseId), rEx)
            lines.add(
                StrengthRoutineOverwriteDiffLine(
                    id = "${rEx.exerciseId}-removed-exercise",
                    exerciseContext = exLabel,
                    exerciseTitle = exLabel,
                    setNumber = 0,
                    exerciseOrderIndex = rEx.orderIndex,
                    fieldTitle = "Removed exercise",
                    oldValue = exLabel,
                    newValue = "—"
                )
            )
            continue
        }
        if (rEx == null && pEx != null) {
            val exLabel = displayNameForDiff(exerciseDisplayName(pEx.exerciseId), pEx)
            lines.add(
                StrengthRoutineOverwriteDiffLine(
                    id = "${pEx.exerciseId}-added-exercise",
                    exerciseContext = exLabel,
                    exerciseTitle = exLabel,
                    setNumber = 0,
                    exerciseOrderIndex = pEx.orderIndex,
                    fieldTitle = "Added exercise",
                    oldValue = "—",
                    newValue = exLabel
                )
            )
            continue
        }
        if (pEx == null || rEx == null) continue
        if (pEx.exerciseId != rEx.exerciseId) {
            val pLabel = displayNameForDiff(exerciseDisplayName(pEx.exerciseId), pEx)
            val rLabel = displayNameForDiff(exerciseDisplayName(rEx.exerciseId), rEx)
            lines.add(
                StrengthRoutineOverwriteDiffLine(
                    id = "${pEx.exerciseId}-${rEx.exerciseId}-exercise-swap",
                    exerciseContext = pLabel,
                    exerciseTitle = pLabel,
                    setNumber = 0,
                    exerciseOrderIndex = pEx.orderIndex,
                    fieldTitle = "Exercise",
                    oldValue = rLabel,
                    newValue = pLabel
                )
            )
            continue
        }
        val exLabel = displayNameForDiff(exerciseDisplayName(pEx.exerciseId), pEx)
        val setsP = pEx.sets.sortedBy { it.setNumber }
        val setsR = rEx.sets.sortedBy { it.setNumber }
        if (setsP.size != setsR.size) {
            lines.add(
                StrengthRoutineOverwriteDiffLine(
                    id = "${pEx.exerciseId}-sets-count",
                    exerciseContext = exLabel,
                    exerciseTitle = exLabel,
                    setNumber = 0,
                    exerciseOrderIndex = pEx.orderIndex,
                    fieldTitle = "Sets",
                    oldValue = setsR.size.toString(),
                    newValue = setsP.size.toString()
                )
            )
        }
        val prefixMatches = setsP.take(setsR.size).zip(setsR.take(setsP.size)).all { (ps, rs) ->
            !strengthProgramSetPrescriptionDiffers(ps, rs)
        }
        val isAppendOnly = setsP.size > setsR.size && prefixMatches
        val maxCount = maxOf(setsP.size, setsR.size)
        for (idx in 0 until maxCount) {
            val setNum = idx + 1
            val ps = setsP.getOrNull(idx)
            val rs = setsR.getOrNull(idx)
            val setLabel = "$exLabel · Set $setNum"
            val baseId = "${pEx.exerciseId}-$setNum"
            if (ps == null && rs != null) {
                if (isAppendOnly) continue
                lines.add(
                    StrengthRoutineOverwriteDiffLine(
                        id = "$baseId-removed",
                        exerciseContext = setLabel,
                        exerciseTitle = exLabel,
                        setNumber = setNum,
                        exerciseOrderIndex = pEx.orderIndex,
                        fieldTitle = "Removed set",
                        oldValue = "Set $setNum",
                        newValue = "—"
                    )
                )
                continue
            }
            if (ps != null && rs == null) {
                lines.add(
                    StrengthRoutineOverwriteDiffLine(
                        id = "$baseId-added",
                        exerciseContext = setLabel,
                        exerciseTitle = exLabel,
                        setNumber = setNum,
                        exerciseOrderIndex = pEx.orderIndex,
                        fieldTitle = "Added set",
                        oldValue = "—",
                        newValue = "Set $setNum"
                    )
                )
                val routineBaseline = setsR.lastOrNull()
                val isDuplicateAppend = isAppendOnly
                    && routineBaseline != null
                    && !strengthProgramSetPrescriptionDiffers(ps, routineBaseline)
                if (!isDuplicateAppend) {
                    appendPrescriptionDiffLines(
                        lines,
                        ps,
                        blankStrengthProgramSetForDiff,
                        exLabel,
                        pEx,
                        setNum,
                        baseId,
                        setLabel
                    )
                }
                continue
            }
            if (ps == null || rs == null) continue
            appendPrescriptionDiffLines(lines, ps, rs, exLabel, pEx, setNum, baseId, setLabel)
        }
    }
    return lines
}

private fun strengthProgramSetPrescriptionDiffers(proposed: StrengthProgramSet, routine: StrengthProgramSet): Boolean {
    if (StrengthPrescriptionCompare.repsChanged(proposed.reps, routine.reps)) return true
    if (StrengthPrescriptionCompare.optionalDoubleChanged(proposed.weightKg, routine.weightKg, StrengthPrescriptionCompare.WEIGHT_EPSILON)) return true
    if (StrengthPrescriptionCompare.optionalDoubleChanged(proposed.rpe, routine.rpe, StrengthPrescriptionCompare.RPE_EPSILON)) return true
    if (StrengthPrescriptionCompare.restChanged(proposed.restSec, routine.restSec)) return true
    val pn = (proposed.notes ?: "").trim()
    val rn = (routine.notes ?: "").trim()
    if (pn != rn) return true
    val psSeg = proposed.weightSegments?.joinToString(" → ") { "${it.reps}×${it.weightKg}" } ?: ""
    val rsSeg = routine.weightSegments?.joinToString(" → ") { "${it.reps}×${it.weightKg}" } ?: ""
    return psSeg != rsSeg
}

private fun appendPrescriptionDiffLines(
    lines: MutableList<StrengthRoutineOverwriteDiffLine>,
    ps: StrengthProgramSet,
    rs: StrengthProgramSet,
    exLabel: String,
    pEx: StrengthProgramItem,
    setNum: Int,
    baseId: String,
    setLabel: String
) {
    if (StrengthPrescriptionCompare.repsChanged(ps.reps, rs.reps)) {
        lines.add(
            StrengthRoutineOverwriteDiffLine(
                id = "$baseId-reps",
                exerciseContext = setLabel,
                exerciseTitle = exLabel,
                setNumber = setNum,
                exerciseOrderIndex = pEx.orderIndex,
                fieldTitle = "Reps",
                oldValue = rs.reps?.toString() ?: "—",
                newValue = ps.reps?.toString() ?: "—"
            )
        )
    }
    if (StrengthPrescriptionCompare.optionalDoubleChanged(ps.weightKg, rs.weightKg, StrengthPrescriptionCompare.WEIGHT_EPSILON)) {
        lines.add(
            StrengthRoutineOverwriteDiffLine(
                id = "$baseId-kg",
                exerciseContext = setLabel,
                exerciseTitle = exLabel,
                setNumber = setNum,
                exerciseOrderIndex = pEx.orderIndex,
                fieldTitle = "Weight",
                oldValue = "${formatWeight(rs.weightKg)} kg",
                newValue = "${formatWeight(ps.weightKg)} kg"
            )
        )
    }
    if (StrengthPrescriptionCompare.optionalDoubleChanged(ps.rpe, rs.rpe, StrengthPrescriptionCompare.RPE_EPSILON)) {
        lines.add(
            StrengthRoutineOverwriteDiffLine(
                id = "$baseId-rpe",
                exerciseContext = setLabel,
                exerciseTitle = exLabel,
                setNumber = setNum,
                exerciseOrderIndex = pEx.orderIndex,
                fieldTitle = "RPE",
                oldValue = formatRpe(rs.rpe),
                newValue = formatRpe(ps.rpe)
            )
        )
    }
    if (StrengthPrescriptionCompare.restChanged(ps.restSec, rs.restSec)) {
        lines.add(
            StrengthRoutineOverwriteDiffLine(
                id = "$baseId-rest",
                exerciseContext = setLabel,
                exerciseTitle = exLabel,
                setNumber = setNum,
                exerciseOrderIndex = pEx.orderIndex,
                fieldTitle = "Rest",
                oldValue = rs.restSec?.let { "$it s" } ?: "—",
                newValue = ps.restSec?.let { "$it s" } ?: "—"
            )
        )
    }
    val psSeg = ps.weightSegments?.joinToString(" → ") { "${it.reps}×${it.weightKg}" } ?: ""
    val rsSeg = rs.weightSegments?.joinToString(" → ") { "${it.reps}×${it.weightKg}" } ?: ""
    if (psSeg != rsSeg) {
        lines.add(
            StrengthRoutineOverwriteDiffLine(
                id = "$baseId-seg",
                exerciseContext = setLabel,
                exerciseTitle = exLabel,
                setNumber = setNum,
                exerciseOrderIndex = pEx.orderIndex,
                fieldTitle = "Drop steps",
                oldValue = rsSeg.ifBlank { "—" },
                newValue = psSeg.ifBlank { "—" }
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
                setNumber = setNum,
                exerciseOrderIndex = pEx.orderIndex,
                fieldTitle = "Set notes",
                oldValue = if (rn.isEmpty()) "—" else rn,
                newValue = if (pn.isEmpty()) "—" else pn
            )
        )
    }
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
    @SerialName("superset_group_id") val supersetGroupId: String? = null,
    @SerialName("superset_position") val supersetPosition: Int? = null,
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
    val notes: String? = null,
    @SerialName("weight_segments") val weightSegments: JsonArray? = null
)

private fun programItemsFromRoutineRow(row: RoutineFullRow): List<StrengthProgramItem> {
    val exs = (row.exercises ?: emptyList()).sortedBy { it.orderIndex }
    return exs.map { ex ->
        val setsInOrder = ex.sets ?: emptyList()
        StrengthProgramItem(
            exerciseId = ex.exerciseId,
            orderIndex = ex.orderIndex,
            notes = ex.notes,
            customName = ex.customName,
            supersetGroupId = ex.supersetGroupId,
            supersetPosition = ex.supersetPosition,
            sets = setsInOrder.mapIndexed { idx, s ->
                val arr = s.weightSegments
                val segPayload = if (arr == null || arr.size < 2) {
                    null
                } else {
                    val parsed = arr.mapNotNull { el ->
                        val o = el.jsonObject
                        val r = o["reps"]?.jsonPrimitive?.content?.toIntOrNull() ?: return@mapNotNull null
                        val w = o["weight_kg"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: return@mapNotNull null
                        StrengthSegmentPayload(r, w)
                    }
                    parsed.takeIf { it.size == arr.size && it.size >= 2 }
                }
                StrengthProgramSet(
                    setNumber = s.setNumber,
                    rowOrder = idx + 1,
                    reps = s.reps,
                    weightKg = s.weightKg,
                    rpe = s.rpe,
                    restSec = s.restSec,
                    notes = s.notes,
                    weightSegments = segPayload
                )
            }
        )
    }
}


private fun strengthRoutineOverwritePromptIfContentDiffers(
    row: RoutineFullRow,
    routineItems: List<StrengthProgramItem>,
    proposed: List<StrengthProgramItem>,
    proposedContent: String,
    exerciseDisplayName: (Long) -> String
): StrengthRoutineOverwriteCandidate {
    val normalizedRoutine = normalizedProgramItemsForCompare(routineItems)
    if (normalizedRoutine.isEmpty()) return StrengthRoutineOverwriteCandidate.None
    val routineContent = strengthRoutineContentFingerprintFromItems(normalizedRoutine)
    if (routineContent == proposedContent) return StrengthRoutineOverwriteCandidate.None
    var diff = buildStrengthRoutineOverwriteDiffLines(proposed, normalizedRoutine, exerciseDisplayName)
    if (diff.isEmpty()) {
        diff = listOf(
            StrengthRoutineOverwriteDiffLine(
                id = "prescription-fallback",
                exerciseContext = row.name,
                exerciseTitle = row.name,
                setNumber = 0,
                exerciseOrderIndex = 0,
                fieldTitle = "Prescription",
                oldValue = "Saved template",
                newValue = "Updated workout"
            )
        )
    }
    if (diff.isEmpty()) return StrengthRoutineOverwriteCandidate.None
    return StrengthRoutineOverwriteCandidate.Prompt(
        StrengthRoutineOverwritePrompt(
            routineId = row.id,
            routineName = row.name,
            diffLines = diff,
            routineBaselineItems = normalizedRoutine
        )
    )
}

internal suspend fun fetchStrengthRoutineOverwriteCandidate(
    supabase: SupabaseClient,
    userId: String,
    proposed: List<StrengthProgramItem>,
    exerciseDisplayName: (Long) -> String,
    preferredRoutineId: Long? = null
): StrengthRoutineOverwriteCandidate {
    if (proposed.isEmpty()) return StrengthRoutineOverwriteCandidate.None
    val proposedNormalized = normalizedProgramItemsForCompare(proposed)
    val proposedContent = strengthRoutineContentFingerprintFromItems(proposedNormalized)
    val res = runCatching {
        supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).select(columns = Columns.raw(STRENGTH_ROUTINE_FULL_SELECT)) {
            filter {
                eq("user_id", userId)
                if (preferredRoutineId != null) {
                    eq("id", preferredRoutineId)
                }
            }
        }
    }.getOrElse { err ->
        if (!strengthRoutineSupersetColumnsUnavailable(err)) throw err
        supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).select(columns = Columns.raw(STRENGTH_ROUTINE_FULL_SELECT_LEGACY)) {
            filter {
                eq("user_id", userId)
                if (preferredRoutineId != null) {
                    eq("id", preferredRoutineId)
                }
            }
        }
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

    if (preferredRoutineId != null) {
        val row = rows.firstOrNull { it.id == preferredRoutineId } ?: rows.first()
        val items = programItemsFromRoutineRow(row)
        return strengthRoutineOverwritePromptIfContentDiffers(
            row = row,
            routineItems = items,
            proposed = proposedNormalized,
            proposedContent = proposedContent,
            exerciseDisplayName = exerciseDisplayName
        )
    }

    data class Match(val row: RoutineFullRow, val items: List<StrengthProgramItem>, val contentHash: String)
    val matches = mutableListOf<Match>()
    for (row in rows) {
        val items = normalizedProgramItemsForCompare(programItemsFromRoutineRow(row))
        if (items.isEmpty()) continue
        if (!structuresMatch(proposedNormalized, items)) continue
        val ch = strengthRoutineContentFingerprintFromItems(items)
        if (ch == proposedContent) continue
        matches.add(Match(row, items, ch))
    }
    if (matches.isEmpty()) return StrengthRoutineOverwriteCandidate.None

    val best = matches.maxWith(compareBy<Match> { m ->
        m.row.updatedAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: Instant.EPOCH
    }.thenBy { it.row.id })

    return strengthRoutineOverwritePromptIfContentDiffers(
        row = best.row,
        routineItems = best.items,
        proposed = proposedNormalized,
        proposedContent = proposedContent,
        exerciseDisplayName = exerciseDisplayName
    )
}

suspend fun applyStrengthRoutinePrescriptionUpdate(
    supabase: SupabaseClient,
    userId: String,
    routineId: Long,
    exercises: List<StrengthExerciseDraft>
) {
    val normalized = normalizedSupersetDrafts(exercises)
    val items = strengthProgramItemsFromDrafts(normalized) ?: error("No exercises to save.")
    applyStrengthRoutinePrescriptionUpdateFromProgramItems(supabase, userId, routineId, items)
}

suspend fun applyStrengthRoutinePrescriptionUpdateFromProgramItems(
    supabase: SupabaseClient,
    userId: String,
    routineId: Long,
    items: List<StrengthProgramItem>
) {
    if (items.isEmpty()) error("No exercises to save.")
    val sortedItems = items.sortedBy { it.orderIndex }
    val contentHash = strengthRoutineContentFingerprintFromItems(sortedItems)

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

    for ((exerciseIndex, item) in sortedItems.withIndex()) {
        val routineExPayload = buildJsonObject {
            put("routine_id", routineId)
            put("exercise_id", item.exerciseId)
            put("order_index", exerciseIndex + 1)
            item.notes?.takeIf { it.isNotBlank() }?.let { put("notes", JsonPrimitive(it.trim())) }
            item.customName?.takeIf { it.isNotBlank() }?.let { put("custom_name", JsonPrimitive(it.trim())) }
            item.supersetGroupId?.let { put("superset_group_id", JsonPrimitive(it)) }
            item.supersetPosition?.let { put("superset_position", it) }
        }
        supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES).insert(routineExPayload) { }
    }

    val insertedRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES).select(
        columns = Columns.raw("id, routine_id, exercise_id, order_index, superset_group_id, superset_position, notes, custom_name")
    ) {
        filter { eq("routine_id", routineId) }
        order("order_index", Order.ASCENDING)
    }
    val insertedRows = parseRoutineExerciseRows(insertedRes.data)

    insertedRows.forEachIndexed { index, row ->
        val itemSets = sortedItems.getOrNull(index)?.sets ?: return@forEachIndexed
        for (set in itemSets) {
            val setPayload = buildJsonObject {
                put("routine_exercise_id", row.id)
                put("set_number", set.setNumber.coerceIn(1, 99))
                if (set.reps != null) put("reps", set.reps)
                if (set.weightKg != null) put("weight_kg", set.weightKg)
                if (set.rpe != null) put("rpe", set.rpe)
                if (set.restSec != null) put("rest_sec", set.restSec)
                set.notes?.let { put("notes", JsonPrimitive(it)) }
                set.weightSegments?.takeIf { it.size >= 2 }?.let { segs ->
                    put("weight_segments", weightSegmentsToJsonArray(segs))
                }
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

suspend fun applySelectiveStrengthRoutineOverwrite(
    supabase: SupabaseClient,
    userId: String,
    prompt: StrengthRoutineOverwritePrompt,
    proposed: List<StrengthProgramItem>,
    selectedLineIds: Set<String>
) {
    val merged = mergedStrengthRoutineProgramItemsForOverwrite(prompt, proposed, selectedLineIds)
    applyStrengthRoutinePrescriptionUpdateFromProgramItems(supabase, userId, prompt.routineId, merged)
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
        val validSets = exercise.sets.mapNotNull { set -> draftSetToStrengthPayload(set) }
        if (validSets.isEmpty()) {
            error("Each exercise must contain at least one set with reps > 0 or additional valid fields.")
        }
        exercise to validSets
    }
}
