package com.lilru.liftr.ui.active

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedRectangleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lilru.liftr.R
import java.util.Locale
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

@Composable
fun ActiveStrengthSupersetCard(
    group: StrengthDisplayGroup,
    exercises: List<ActiveStrengthExerciseLine>,
    activeExerciseIndex: Int,
    setProgress: Map<Int, Int>,
    completedSetsByExerciseId: Map<Int, List<CompletedSetLine>>,
    restSecondsByExerciseId: Map<Int, Int>,
    finishing: Boolean,
    onMemberTap: (Int) -> Unit,
    onSetDone: () -> Unit,
    onSkipRest: () -> Unit,
    onNextExercise: () -> Unit,
    showNextExercise: Boolean,
    modifier: Modifier = Modifier
) {
    val members = group.exerciseIndices.mapNotNull { exercises.getOrNull(it) }
    val activeEx = exercises.getOrNull(activeExerciseIndex)
    val laneSetIndex = activeEx?.let { setProgress[it.workoutExerciseId] ?: 0 } ?: 0
    val activeSet = activeEx?.sets?.getOrNull(laneSetIndex)
    val groupAllDone = members.all { (setProgress[it.workoutExerciseId] ?: 0) >= it.sets.size }
    val groupRestSec = members.mapNotNull { restSecondsByExerciseId[it.workoutExerciseId] }
        .filter { it > 0 }
        .maxOrNull() ?: 0
    val groupIsResting = groupRestSec > 0

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = stringResource(R.string.active_strength_superset_label),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = stringResource(R.string.active_strength_superset_set_round, laneSetIndex + 1, members.size),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = members.joinToString(" → ") { it.displayName },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Column(
            modifier = Modifier
                .heightIn(max = 336.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            members.forEachIndexed { offset, member ->
                SupersetMemberRow(
                    member = member,
                    position = offset + 1,
                    memberCount = members.size,
                    setIndex = laneSetIndex,
                    setProgress = setProgress,
                    completedSets = completedSetsByExerciseId[member.workoutExerciseId].orEmpty(),
                    isActiveMember = exercises.getOrNull(activeExerciseIndex)?.workoutExerciseId == member.workoutExerciseId,
                    groupIsResting = groupIsResting,
                    groupRestSec = groupRestSec,
                    onTap = {
                        val idx = exercises.indexOfFirst { it.workoutExerciseId == member.workoutExerciseId }
                        if (idx >= 0) onMemberTap(idx)
                    }
                )
                if (offset < members.lastIndex) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
                }
            }
        }

        if (!groupAllDone && activeSet != null && activeEx != null) {
            if (groupIsResting) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onSkipRest) {
                        Text("Skip rest")
                    }
                }
            } else {
                Button(
                    onClick = onSetDone,
                    enabled = !finishing,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        primarySetActionLabel(
                            ex = activeEx,
                            exercises = exercises,
                            setIndex = laneSetIndex,
                            setProgress = setProgress,
                            currentSet = activeSet
                        )
                    )
                }
            }
        } else if (groupAllDone && showNextExercise) {
            Button(onClick = onNextExercise, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.active_strength_next_exercise))
            }
        }
    }
}

@Composable
private fun SupersetMemberRow(
    member: ActiveStrengthExerciseLine,
    position: Int,
    memberCount: Int,
    setIndex: Int,
    setProgress: Map<Int, Int>,
    completedSets: List<CompletedSetLine>,
    isActiveMember: Boolean,
    groupIsResting: Boolean,
    groupRestSec: Int,
    onTap: () -> Unit
) {
    val memberDone = (setProgress[member.workoutExerciseId] ?: 0) > setIndex
    val plannedSet = member.sets.getOrNull(setIndex)
    val isCurrent = isActiveMember && plannedSet != null && !memberDone && !groupIsResting
    val statusLabel = when {
        groupIsResting -> "Rest"
        memberDone -> "Done"
        isCurrent -> "Current"
        else -> "Upcoming"
    }
    val statusColor = when {
        groupIsResting -> MaterialTheme.colorScheme.primary
        memberDone -> Color(0xFF2E7D32)
        isCurrent -> MaterialTheme.colorScheme.primary
        else -> Color(0xFFD08A1B)
    }
    val rowBg = when {
        groupIsResting -> MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
        isCurrent -> MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
        else -> Color.Transparent
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedRectangleShape(14.dp))
            .background(rowBg)
            .clickable(onClick = onTap)
            .padding(horizontal = 10.dp, vertical = 8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            Text(
                text = "$position. ${member.displayName}",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f)
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (memberDone && !groupIsResting) {
                    Icon(
                        imageVector = Icons.Filled.CheckCircle,
                        contentDescription = null,
                        tint = statusColor,
                        modifier = Modifier.size(16.dp)
                    )
                }
                Text(
                    text = statusLabel.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = statusColor,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(statusColor.copy(alpha = 0.15f))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                )
            }
        }
        if (groupIsResting) {
            SupersetMemberRestCountdown(restSec = groupRestSec)
        } else if (memberDone) {
            val performed = completedSets.getOrNull(setIndex)
            val reps = performed?.reps ?: plannedSet?.reps ?: 0
            val weight = performed?.weightKg ?: plannedSet?.weightKg
            Text(
                text = "$reps reps · ${formatKg(weight)}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else if (plannedSet != null) {
            val segs = plannedSet.weightSegments
            if (segs != null && segs.size >= 2) {
                Text("Drop set", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                segs.forEach { el ->
                    val o = el.jsonObject
                    val r = o["reps"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0
                    val w = o["weight_kg"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: 0.0
                    Text(
                        "$r reps · ${String.format(Locale.US, "%.1f", w)} kg",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            } else {
                Text(
                    text = "${plannedSet.reps ?: 0} reps · ${formatKg(plannedSet.weightKg)}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
                plannedSet.rpe?.let {
                    Text(
                        text = "Target RPE ${String.format(Locale.US, "%.1f", it)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        Text(
            text = stringResource(R.string.active_strength_superset_member_position, position, memberCount),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.75f)
        )
    }
}

@Composable
private fun SupersetMemberRestCountdown(restSec: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedRectangleShape(10.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "Rest",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(40.dp)
        )
        Text(
            text = "${restSec}s",
            style = MaterialTheme.typography.headlineSmall.copy(fontSize = 26.sp),
            fontWeight = FontWeight.Bold,
            modifier = Modifier.weight(1f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
        Spacer(modifier = Modifier.width(40.dp))
    }
}

private fun formatKg(kg: Double?): String =
    "${kg?.let { String.format(Locale.US, "%.1f", it) } ?: "0.0"} kg"
