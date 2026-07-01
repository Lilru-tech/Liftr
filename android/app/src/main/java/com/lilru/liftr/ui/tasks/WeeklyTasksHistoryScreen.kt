package com.lilru.liftr.ui.tasks

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import io.github.jan.supabase.SupabaseClient

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WeeklyTasksHistoryScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm: WeeklyTasksHistoryViewModel = viewModel(
        factory = WeeklyTasksHistoryViewModel.Factory(supabase)
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val themeId = LiftrPreferences.backgroundTheme(ctx)

    Column(
        modifier
            .fillMaxSize()
            .liftrAppBackgroundGradient(themeId)
    ) {
        LiftrBackTopBar(
            title = stringResource(R.string.home_weekly_tasks_history_title),
            onBack = onBack,
        )
        when {
            state.loading && state.stats == null -> {
                Column(
                    Modifier.fillMaxWidth().padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    CircularProgressIndicator()
                }
            }
            state.error != null && state.stats == null -> {
                Text(
                    state.error ?: "",
                    modifier = Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.error
                )
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)
                ) {
                    state.stats?.let { stats ->
                        item {
                            HistorySummaryCard(stats)
                            Spacer(Modifier.height(8.dp))
                        }
                    }
                    item {
                        Text(
                            stringResource(R.string.home_weekly_tasks_history_completed_section),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(bottom = 4.dp)
                        )
                    }
                    if (state.totalCompletedTasks == 0) {
                        item {
                            Text(
                                stringResource(R.string.home_weekly_tasks_history_empty_completed),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    } else {
                        items(state.completedTasks, key = { it.taskId }) { task ->
                            HistoryTaskCard(task)
                        }
                        if (state.hasMore) {
                            item {
                                TextButton(
                                    onClick = { vm.loadMore() },
                                    enabled = !state.loadingMore,
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    if (state.loadingMore) {
                                        CircularProgressIndicator(modifier = Modifier.height(18.dp))
                                    } else {
                                        Text(stringResource(R.string.home_weekly_tasks_history_see_more))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HistorySummaryCard(stats: WeeklyTasksHistoryStatsUi) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.55f), RoundedCornerShape(14.dp))
            .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                stringResource(R.string.home_weekly_tasks_history_all_time),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                stringResource(R.string.home_weekly_tasks_history_completed_pct, stats.completionRatePercent),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SummaryPill(stringResource(R.string.home_weekly_tasks_history_accepted), "${stats.totalAccepted}")
            SummaryPill(stringResource(R.string.home_weekly_tasks_history_completed), "${stats.totalCompleted}")
            SummaryPill(stringResource(R.string.home_weekly_tasks_history_missed), "${stats.totalExpired}")
            SummaryPill("XP", "${stats.totalXpEarned}")
            SummaryPill(stringResource(R.string.home_weekly_tasks_history_coins), "${stats.totalCoinsEarned}")
            SummaryPill("TP", "${stats.totalTaskPointsEarned}")
        }
        Text(
            stringResource(
                R.string.home_weekly_tasks_history_this_week,
                stats.currentWeekCompleted,
                stats.currentWeekAccepted
            ),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun SummaryPill(title: String, value: String) {
    Column(
        modifier = Modifier
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f), RoundedCornerShape(10.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun HistoryTaskCard(task: WeeklyTasksHistoryTaskUi) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp)
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.55f), RoundedCornerShape(14.dp))
            .border(2.dp, Color(0xFF4CAF50).copy(alpha = 0.55f), RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(task.category.replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.labelMedium)
                task.difficultyBand?.let { band ->
                    Text(
                        band.replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Text(
                stringResource(R.string.home_weekly_tasks_status_completed),
                style = MaterialTheme.typography.labelMedium,
                color = Color(0xFF4CAF50),
                fontWeight = FontWeight.SemiBold
            )
        }
        Text(task.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        task.completedAt?.take(10)?.let { date ->
            Text(date, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(
            stringResource(
                R.string.home_weekly_tasks_history_rewards,
                task.rewardXp,
                task.rewardCoins,
                task.rewardTaskPoints
            ),
            style = MaterialTheme.typography.labelMedium,
            color = Color(0xFF4CAF50),
            fontWeight = FontWeight.SemiBold
        )
    }
}
