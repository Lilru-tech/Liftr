package com.lilru.liftr.ui.tasks

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.home.HomeWorkoutFeedCard
import com.lilru.liftr.ui.home.WorkoutSummary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun WeeklyTaskContributionsScreen(
    task: UserWeeklyTaskUi,
    vm: PersonalWeeklyTasksViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var detail by remember { mutableStateOf<UserTaskDetailUi?>(null) }
    var contributions by remember { mutableStateOf(listOf<WeeklyTaskWorkoutUi>()) }
    var workouts by remember { mutableStateOf(listOf<WorkoutSummary>()) }
    var loading by remember { mutableStateOf(true) }
    var err by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(task.taskId) {
        loading = true
        err = null
        val result = withContext(Dispatchers.IO) {
            runCatching {
                val d = vm.loadTaskDetail(task.taskId)
                val rows = vm.loadTaskWorkouts(task.taskId)
                val summaries = vm.loadTaskWorkoutSummaries(rows)
                Triple(d, rows, summaries)
            }
        }
        loading = false
        result.onSuccess { (d, rows, summaries) ->
            detail = d
            contributions = rows
            workouts = summaries
        }.onFailure { e ->
            err = e.message?.take(200)
        }
    }

    val qualifyingCount = contributions.count { it.qualifies }
    val bestLabel = contributions.maxByOrNull { it.contributionValue ?: 0.0 }?.contributionLabel

    Column(modifier.fillMaxSize()) {
        LiftrBackTopBar(
            title = detail?.title ?: task.title,
            onBack = onBack,
        )
        when {
            loading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            err != null -> {
                Text(
                    err ?: stringResource(R.string.home_weekly_tasks_detail_load_error),
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp)
                )
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    item {
                        detail?.let { d ->
                            WeeklyTaskDetailHeader(d, task)
                        }
                    }
                    item {
                        WeeklyTaskSummaryCard(
                            workoutCount = workouts.size,
                            qualifyingCount = qualifyingCount,
                            bestLabel = bestLabel
                        )
                    }
                    if (workouts.isEmpty()) {
                        item {
                            Text(
                                stringResource(R.string.home_weekly_tasks_detail_empty),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        items(workouts, key = { it.id }) { w ->
                            val contrib = contributions.firstOrNull { it.workoutId == w.id }
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                contrib?.contributionLabel?.let { label ->
                                    Row(
                                        Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text(
                                            label,
                                            style = MaterialTheme.typography.labelMedium,
                                            fontWeight = FontWeight.SemiBold,
                                            color = if (contrib.qualifies) Color(0xFF4CAF50) else Color(0xFFFF9800)
                                        )
                                        if (contrib.qualifies) {
                                            Text(
                                                stringResource(R.string.home_weekly_tasks_detail_qualifies),
                                                style = MaterialTheme.typography.labelSmall,
                                                fontWeight = FontWeight.Bold,
                                                color = Color(0xFF4CAF50),
                                                modifier = Modifier
                                                    .background(Color(0xFF4CAF50).copy(alpha = 0.15f), RoundedCornerShape(50))
                                                    .padding(horizontal = 8.dp, vertical = 2.dp)
                                            )
                                        }
                                    }
                                }
                                HomeWorkoutFeedCard(
                                    workout = w,
                                    meUserId = vm.sessionUserId,
                                    dayGroupLabel = null,
                                    onClick = { AppNavEvents.send(MainOverlay.WorkoutDetail(w.id, null)) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WeeklyTaskDetailHeader(d: UserTaskDetailUi, task: UserWeeklyTaskUi) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.55f), shape)
            .border(1.dp, Color.White.copy(alpha = 0.18f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(d.category.replaceFirstChar { it.uppercase() }, fontWeight = FontWeight.SemiBold)
            Text(d.status.replaceFirstChar { it.uppercase() }, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        d.difficultyBand?.let { band ->
            Text(band.replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.labelSmall)
        }
        Text(d.description, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (d.status == "accepted" || d.status == "completed") {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(stringResource(R.string.home_weekly_tasks_progress), fontWeight = FontWeight.SemiBold)
                Text(
                    "${d.progressPercent ?: task.progressPercentInt}%",
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            LinearProgressIndicator(
                progress = { (d.progressPercent ?: task.progressPercentInt) / 100f },
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                "${d.progressCurrentLabel ?: task.progressCurrentLabel} / ${d.progressTargetLabel ?: task.progressTargetLabel}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            "${d.rewardXp} XP · ${d.rewardCoins} coins · ${d.rewardTaskPoints} TP",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun WeeklyTaskSummaryCard(
    workoutCount: Int,
    qualifyingCount: Int,
    bestLabel: String?,
) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.55f), shape)
            .border(1.dp, Color.White.copy(alpha = 0.18f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(stringResource(R.string.home_weekly_tasks_detail_summary), fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Column {
                Text(stringResource(R.string.home_weekly_tasks_detail_workouts), style = MaterialTheme.typography.labelSmall)
                Text("$workoutCount", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            Column {
                Text(stringResource(R.string.home_weekly_tasks_detail_qualifying), style = MaterialTheme.typography.labelSmall)
                Text("$qualifyingCount", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            bestLabel?.let { best ->
                Column {
                    Text(stringResource(R.string.home_weekly_tasks_detail_best), style = MaterialTheme.typography.labelSmall)
                    Text(best, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}
