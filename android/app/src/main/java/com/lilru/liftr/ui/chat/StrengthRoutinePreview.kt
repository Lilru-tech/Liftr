package com.lilru.liftr.ui.chat

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R

internal data class StrengthRoutinePreviewBlock(
    val id: String,
    val isSuperset: Boolean,
    val exercises: List<RoutineShareStrengthEx>
)

internal fun strengthRoutinePreviewBlocks(
    exercises: List<RoutineShareStrengthEx>
): List<StrengthRoutinePreviewBlock> {
    val ordered = exercises.sortedBy { it.orderIndex }
    val blocks = mutableListOf<StrengthRoutinePreviewBlock>()
    var idx = 0
    while (idx < ordered.size) {
        val current = ordered[idx]
        val groupId = current.supersetGroupId
        if (groupId == null) {
            blocks.add(
                StrengthRoutinePreviewBlock(
                    id = "exercise-$idx",
                    isSuperset = false,
                    exercises = listOf(current)
                )
            )
            idx += 1
            continue
        }
        val group = mutableListOf(current)
        var nextIdx = idx + 1
        while (nextIdx < ordered.size && ordered[nextIdx].supersetGroupId == groupId) {
            group.add(ordered[nextIdx])
            nextIdx += 1
        }
        if (group.size > 1) {
            val sortedGroup = group.sortedWith(
                compareBy<RoutineShareStrengthEx> { it.supersetPosition ?: Int.MAX_VALUE }
                    .thenBy { it.orderIndex }
            )
            blocks.add(
                StrengthRoutinePreviewBlock(
                    id = "superset-$groupId",
                    isSuperset = true,
                    exercises = sortedGroup
                )
            )
        } else {
            blocks.add(
                StrengthRoutinePreviewBlock(
                    id = "exercise-$idx",
                    isSuperset = false,
                    exercises = listOf(current)
                )
            )
        }
        idx = nextIdx
    }
    return blocks
}

@Composable
internal fun StrengthRoutineSharePreview(
    exercises: List<RoutineShareStrengthEx>,
    exerciseNames: Map<Long, String>,
    emDash: String
) {
    val blocks = strengthRoutinePreviewBlocks(exercises)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (block in blocks) {
            if (block.isSuperset) {
                StrengthRoutineSupersetPreviewCard(block, exerciseNames, emDash)
            } else {
                val ex = block.exercises.firstOrNull() ?: continue
                StrengthRoutineExercisePreviewCard(ex, exerciseNames, emDash)
            }
        }
    }
}

@Composable
private fun StrengthRoutineSupersetPreviewCard(
    block: StrengthRoutinePreviewBlock,
    exerciseNames: Map<Long, String>,
    emDash: String
) {
    val memberCount = block.exercises.size
    val shape = RoundedCornerShape(12.dp)
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.35f), shape),
        shape = shape,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f)
    ) {
        Column(
            Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    Icons.Filled.Link,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    stringResource(R.string.active_strength_superset_label),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(Modifier.weight(1f))
                Text(
                    stringResource(R.string.add_strength_superset_exercise_count, memberCount),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            for ((offset, ex) in block.exercises.withIndex()) {
                val position = ex.supersetPosition ?: (offset + 1)
                val display = ex.customName?.trim().orEmpty().ifEmpty {
                    exerciseNames[ex.exerciseId] ?: "Exercise ${ex.exerciseId}"
                }
                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.04f)
                ) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(10.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            stringResource(
                                R.string.active_strength_superset_member_position,
                                position,
                                memberCount
                            ),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Text(display, style = MaterialTheme.typography.titleSmall)
                        StrengthRoutineExerciseSetsPreview(ex, emDash)
                    }
                }
            }
        }
    }
}

@Composable
private fun StrengthRoutineExercisePreviewCard(
    ex: RoutineShareStrengthEx,
    exerciseNames: Map<Long, String>,
    emDash: String
) {
    val display = ex.customName?.trim().orEmpty().ifEmpty {
        exerciseNames[ex.exerciseId] ?: "Exercise ${ex.exerciseId}"
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f)
        )
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(display, style = MaterialTheme.typography.titleSmall)
            val exNotes = ex.notes?.trim().orEmpty()
            if (exNotes.isNotEmpty()) {
                Text(
                    exNotes,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            StrengthRoutineExerciseSetsPreview(ex, emDash)
        }
    }
}

@Composable
private fun StrengthRoutineExerciseSetsPreview(ex: RoutineShareStrengthEx, emDash: String) {
    val setsSorted = ex.strengthRoutineSets.orEmpty().sortedBy { it.setNumber }
    if (setsSorted.isEmpty()) {
        Text(
            stringResource(R.string.shared_routine_set_line, 1, emDash, emDash, emDash, emDash),
            style = MaterialTheme.typography.bodySmall
        )
    } else {
        for (s in setsSorted) {
            val reps = s.reps?.toString() ?: emDash
            val kg = s.weightKg?.let { v ->
                if (v == kotlin.math.floor(v)) v.toInt().toString() else String.format("%.1f", v)
            } ?: emDash
            val rpe = s.rpe?.let { v ->
                if (v == kotlin.math.floor(v)) v.toInt().toString() else String.format("%.1f", v)
            } ?: emDash
            val rest = s.restSec?.let { stringResource(R.string.shared_routine_rest_sec, it) } ?: emDash
            Text(
                stringResource(R.string.shared_routine_set_line, s.setNumber, reps, kg, rpe, rest),
                style = MaterialTheme.typography.bodySmall
            )
            val sn = s.notes?.trim().orEmpty()
            if (sn.isNotEmpty()) {
                Text(
                    sn,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
