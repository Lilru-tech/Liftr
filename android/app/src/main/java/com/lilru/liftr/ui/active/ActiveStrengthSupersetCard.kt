package com.lilru.liftr.ui.active

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import java.util.Locale
import kotlin.math.max
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

@Composable
fun ActiveStrengthRestTimerRow(
    restSec: Int,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(44.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f))
            .padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = stringResource(R.string.active_strength_rest_title),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.width(8.dp))
        Text(
            text = "${restSec}s",
            style = MaterialTheme.typography.titleMedium,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Start,
            modifier = Modifier.widthIn(min = 48.dp)
        )
    }
}

@Composable
fun ActiveStrengthSkipRestOutlinedButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.fillMaxWidth()
    ) {
        Text(stringResource(R.string.active_strength_skip_rest))
    }
}

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
    onEditSet: (memberExerciseIndex: Int, roundIndex: Int) -> Unit,
    editEnabled: Boolean = true,
    onSetDone: () -> Unit,
    onSkipRest: () -> Unit,
    onNextExercise: () -> Unit,
    showNextExercise: Boolean,
    modifier: Modifier = Modifier
) {
    val members = group.exerciseIndices.mapNotNull { exercises.getOrNull(it) }
    val activeEx = exercises.getOrNull(activeExerciseIndex)
    val workSetIndex = supersetGroupWorkSetIndex(members, setProgress)
    val maxRounds = supersetMaxRoundCount(members)
    val groupAllDone = members.all { (setProgress[it.workoutExerciseId] ?: 0) >= it.sets.size }
    val activeSet = if (groupAllDone) null else activeEx?.sets?.getOrNull(workSetIndex)
    val groupRestSec = members.mapNotNull { restSecondsByExerciseId[it.workoutExerciseId] }
        .filter { it > 0 }
        .maxOrNull() ?: 0
    val groupIsResting = groupRestSec > 0
    val canShowRoundSlider = !groupAllDone && maxRounds > 0
    var visitedRound by remember(group.id, workSetIndex) {
        mutableIntStateOf(workSetIndex.coerceIn(0, max(0, maxRounds - 1)))
    }
    LaunchedEffect(workSetIndex, maxRounds) {
        if (visitedRound > workSetIndex) {
            visitedRound = workSetIndex.coerceIn(0, max(0, maxRounds - 1))
        }
    }
    val isVisitingCurrentRound = visitedRound == workSetIndex
    val visitedIsPastRound = visitedRound < workSetIndex
    val membersBlockHeight = supersetMembersContentHeightDp(members.size)
    val isMultiMemberSuperset = members.size > 1

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = stringResource(R.string.active_strength_superset_label),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (groupAllDone) {
            Text(
                text = stringResource(R.string.active_strength_all_sets_done_title),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = stringResource(R.string.active_strength_all_sets_done_subtitle),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Text(
                text = stringResource(R.string.active_strength_superset_set_round, workSetIndex + 1, members.size),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            if (canShowRoundSlider && !isVisitingCurrentRound) {
                Text(
                    text = stringResource(R.string.active_strength_viewing_set, visitedRound + 1),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Text(
            text = members.joinToString(" → ") { it.displayName },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (canShowRoundSlider) {
            val pagerState = rememberPagerState(
                initialPage = visitedRound,
                pageCount = { maxRounds }
            )
            LaunchedEffect(visitedRound) {
                if (pagerState.currentPage != visitedRound) {
                    pagerState.animateScrollToPage(visitedRound)
                }
            }
            LaunchedEffect(pagerState.currentPage) {
                visitedRound = pagerState.currentPage
            }
            LaunchedEffect(workSetIndex) {
                if (pagerState.currentPage != workSetIndex) {
                    pagerState.animateScrollToPage(workSetIndex.coerceIn(0, max(0, maxRounds - 1)))
                }
            }

            HorizontalPager(
                state = pagerState,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(membersBlockHeight.dp)
            ) { roundIdx ->
                SupersetRoundMemberList(
                    members = members,
                    exercises = exercises,
                    activeExerciseIndex = activeExerciseIndex,
                    roundIndex = roundIdx,
                    workSetIndex = workSetIndex,
                    setProgress = setProgress,
                    completedSetsByExerciseId = completedSetsByExerciseId,
                    groupAllDone = groupAllDone,
                    groupIsResting = groupIsResting,
                    onMemberTap = onMemberTap,
                    onEditSet = onEditSet,
                    editEnabled = editEnabled,
                    scrollWhenNeeded = membersBlockHeight >= 336
                )
            }

            ActiveStrengthSetSlideDots(
                total = maxRounds,
                visited = visitedRound,
                current = workSetIndex,
                modifier = Modifier.fillMaxWidth()
            )

        } else {
            val displayRound = if (groupAllDone) max(0, maxRounds - 1) else workSetIndex
            SupersetRoundMemberList(
                members = members,
                exercises = exercises,
                activeExerciseIndex = activeExerciseIndex,
                roundIndex = displayRound,
                workSetIndex = workSetIndex,
                setProgress = setProgress,
                completedSetsByExerciseId = completedSetsByExerciseId,
                groupAllDone = groupAllDone,
                groupIsResting = groupIsResting,
                onMemberTap = onMemberTap,
                onEditSet = onEditSet,
                editEnabled = editEnabled,
                scrollWhenNeeded = membersBlockHeight >= 336,
                modifier = Modifier.height(membersBlockHeight.dp)
            )
        }

        if (editEnabled && isMultiMemberSuperset && !groupAllDone && !groupIsResting && !visitedIsPastRound) {
            val editRound = if (canShowRoundSlider) visitedRound else workSetIndex
            OutlinedButton(
                onClick = { onEditSet(activeExerciseIndex, editRound) },
                enabled = !finishing && activeEx?.sets?.getOrNull(editRound) != null,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Edit reps, weight & rest")
            }
        }

        if (!groupAllDone && activeEx != null && (activeSet != null || isMultiMemberSuperset)) {
            if (groupIsResting) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    ActiveStrengthRestTimerRow(restSec = groupRestSec)
                    ActiveStrengthSkipRestOutlinedButton(
                        onClick = onSkipRest,
                        enabled = !finishing
                    )
                }
            } else if (canShowRoundSlider && !isVisitingCurrentRound) {
                Button(
                    onClick = { visitedRound = workSetIndex },
                    enabled = !finishing,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.active_strength_back_to_current_set))
                }
            } else if (!visitedIsPastRound) {
                Button(
                    onClick = onSetDone,
                    enabled = !finishing && (activeSet != null || isMultiMemberSuperset),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        if (isMultiMemberSuperset) {
                            supersetRoundActionLabel(members, workSetIndex)
                        } else {
                            primarySetActionLabel(
                                ex = activeEx,
                                exercises = exercises,
                                setIndex = workSetIndex,
                                setProgress = setProgress,
                                currentSet = activeSet!!
                            )
                        }
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
private fun SupersetRoundMemberList(
    members: List<ActiveStrengthExerciseLine>,
    exercises: List<ActiveStrengthExerciseLine>,
    activeExerciseIndex: Int,
    roundIndex: Int,
    workSetIndex: Int,
    setProgress: Map<Int, Int>,
    completedSetsByExerciseId: Map<Int, List<CompletedSetLine>>,
    groupAllDone: Boolean,
    groupIsResting: Boolean,
    onMemberTap: (Int) -> Unit,
    onEditSet: (memberExerciseIndex: Int, roundIndex: Int) -> Unit,
    editEnabled: Boolean = true,
    modifier: Modifier = Modifier,
    scrollWhenNeeded: Boolean = false
) {
    val content = Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        members.forEachIndexed { offset, member ->
            SupersetMemberRow(
                member = member,
                position = offset + 1,
                memberCount = members.size,
                setIndex = roundIndex,
                setProgress = setProgress,
                completedSets = completedSetsByExerciseId[member.workoutExerciseId].orEmpty(),
                isActiveMember = exercises.getOrNull(activeExerciseIndex)?.workoutExerciseId == member.workoutExerciseId,
                groupAllDone = groupAllDone,
                groupIsResting = groupIsResting,
                onTap = {
                    val memberIndex = exercises.indexOfFirst { it.workoutExerciseId == member.workoutExerciseId }
                    if (memberIndex >= 0) onMemberTap(memberIndex)
                }
            )
            if (offset < members.lastIndex) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
            }
        }
    }
    if (scrollWhenNeeded) {
        Column(
            modifier = modifier
                .fillMaxWidth()
                .heightIn(max = 336.dp)
                .verticalScroll(rememberScrollState())
        ) { content }
    } else {
        Box(modifier = modifier.fillMaxWidth()) { content }
    }
}

@Composable
fun ActiveStrengthSetSlideDots(
    total: Int,
    visited: Int,
    current: Int,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 2.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        repeat(total) { i ->
            val isVisited = i == visited
            val isCurrent = i == current
            val dotSize = if (isCurrent) 10.dp else 8.dp
            val fillColor = if (isVisited) MaterialTheme.colorScheme.primary else Color.Transparent
            val borderColor = if (isCurrent) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f)
            }
            Box(
                modifier = Modifier
                    .padding(horizontal = 3.dp)
                    .size(dotSize)
                    .clip(CircleShape)
                    .border(
                        width = if (isCurrent) 1.5.dp else 1.dp,
                        color = borderColor,
                        shape = CircleShape
                    )
                    .background(fillColor, CircleShape)
            )
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
    groupAllDone: Boolean,
    groupIsResting: Boolean,
    onTap: () -> Unit
) {
    val memberDone = groupAllDone ||
        supersetMemberFinishedRound(member, setIndex, setProgress, completedSets)
    val plannedSet = member.sets.getOrNull(setIndex)
    val isInActiveRound = !memberDone && !groupIsResting && !groupAllDone
    val isCurrent = isInActiveRound
    val statusLabel = when {
        groupAllDone || memberDone -> "Done"
        groupIsResting -> "Rest"
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
        isInActiveRound -> MaterialTheme.colorScheme.primary.copy(
            alpha = if (isActiveMember) 0.14f else 0.10f
        )
        else -> Color.Transparent
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
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
        if (memberDone && !groupIsResting) {
            val performed = completedSets.lastOrNull()
                ?: completedSets.getOrNull(setIndex)
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

private fun formatKg(kg: Double?): String =
    "${kg?.let { String.format(Locale.US, "%.1f", it) } ?: "0.0"} kg"
