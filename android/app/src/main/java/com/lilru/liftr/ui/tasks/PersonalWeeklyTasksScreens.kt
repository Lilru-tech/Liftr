package com.lilru.liftr.ui.tasks

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.draw.clip
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient

@Composable
fun PersonalWeeklyTasksScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm: PersonalWeeklyTasksViewModel = viewModel(
        factory = PersonalWeeklyTasksViewModel.Factory(supabase)
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val homeContext = LocalContext.current
    var taskToUnaccept by remember { mutableStateOf<UserWeeklyTaskUi?>(null) }
    var showRefreshConfirm by remember { mutableStateOf(false) }
    var taskForDetail by remember { mutableStateOf<UserWeeklyTaskUi?>(null) }
    var showHistory by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        markWeeklyTasksHomeSeen(supabase, homeContext)
    }

    if (showHistory) {
        WeeklyTasksHistoryScreen(
            supabase = supabase,
            onBack = { showHistory = false },
            modifier = modifier
        )
        return
    }

    if (taskForDetail != null) {
        WeeklyTaskContributionsScreen(
            task = taskForDetail!!,
            vm = vm,
            onBack = { taskForDetail = null },
            modifier = modifier
        )
        return
    }

    Column(modifier.fillMaxSize()) {
        LiftrBackTopBar(
            title = stringResource(R.string.home_weekly_tasks_title),
            onBack = onBack,
            actions = {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    WeeklyTasksToolbarPill(onClick = { showHistory = true }) {
                        Icon(
                            Icons.Filled.History,
                            contentDescription = stringResource(R.string.home_weekly_tasks_history_button)
                        )
                    }
                    if (state.showRefreshMenu) {
                        WeeklyTasksToolbarPill(
                            onClick = { showRefreshConfirm = true },
                            enabled = !state.refreshingMenu
                        ) {
                            if (state.refreshingMenu) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp))
                            } else {
                                Icon(
                                    Icons.Filled.Refresh,
                                    contentDescription = stringResource(R.string.home_weekly_tasks_refresh_title)
                                )
                            }
                        }
                    } else if (state.allMenuTasksCompleted) {
                        newMenuCountdownText(state.weekEnd)?.let { countdown ->
                            WeeklyTasksToolbarPill {
                                Text(
                                    countdown,
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                    WeeklyTasksToolbarPill {
                        Text(
                            "${state.acceptedCount}/3",
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        )
        when {
            state.loading && state.tasks.isEmpty() -> {
                Column(
                    Modifier.fillMaxWidth().padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    CircularProgressIndicator()
                }
            }
            state.error != null && state.tasks.isEmpty() -> {
                Text(
                    state.error ?: "",
                    modifier = Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.error
                )
            }
            state.tasks.isEmpty() -> {
                Text(
                    stringResource(R.string.home_weekly_tasks_empty),
                    modifier = Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)
                ) {
                    item {
                        Text(
                            stringResource(R.string.home_weekly_tasks_help),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (state.allMenuTasksCompleted) {
                            newMenuCountdownText(state.weekEnd)?.let { countdown ->
                                Spacer(Modifier.height(6.dp))
                                Text(
                                    countdown,
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        state.error?.let { err ->
                            Spacer(Modifier.height(6.dp))
                            Text(err, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                        }
                        Spacer(Modifier.height(8.dp))
                    }
                    items(state.tasks, key = { it.taskId }) { task ->
                        PersonalWeeklyTaskCard(
                            task = task,
                            isAccepting = state.acceptingTaskId == task.taskId,
                            isUnaccepting = state.unacceptingTaskId == task.taskId,
                            onTap = { taskForDetail = task },
                            onAccept = { vm.accept(task.taskId) },
                            onUnaccept = { taskToUnaccept = task }
                        )
                    }
                }
            }
        }
    }

    taskToUnaccept?.let { task ->
        AlertDialog(
            onDismissRequest = { taskToUnaccept = null },
            title = { Text(stringResource(R.string.home_weekly_tasks_unaccept_title)) },
            text = { Text(stringResource(R.string.home_weekly_tasks_unaccept_message)) },
            confirmButton = {
                TextButton(onClick = {
                    vm.unaccept(task.taskId)
                    taskToUnaccept = null
                }) {
                    Text(stringResource(R.string.home_weekly_tasks_unaccept_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { taskToUnaccept = null }) {
                    Text(stringResource(R.string.goals_new_cancel))
                }
            }
        )
    }

    if (showRefreshConfirm) {
        AlertDialog(
            onDismissRequest = { showRefreshConfirm = false },
            title = { Text(stringResource(R.string.home_weekly_tasks_refresh_title)) },
            text = { Text(refreshConfirmMessage(state)) },
            confirmButton = {
                TextButton(onClick = {
                    showRefreshConfirm = false
                    vm.refreshMenu()
                }) {
                    Text(refreshConfirmAction(state))
                }
            },
            dismissButton = {
                TextButton(onClick = { showRefreshConfirm = false }) {
                    Text(stringResource(R.string.goals_new_cancel))
                }
            }
        )
    }
}

@Composable
private fun WeeklyTasksToolbarPill(
    onClick: (() -> Unit)? = null,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(50)
    val base = Modifier
        .clip(shape)
        .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.55f))
        .border(0.8.dp, Color.White.copy(alpha = 0.18f), shape)
        .padding(horizontal = 10.dp, vertical = 6.dp)
    if (onClick != null) {
        Row(
            base.clickable(enabled = enabled, onClick = onClick),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            content()
        }
    } else {
        Row(
            base,
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            content()
        }
    }
}

@Composable
private fun refreshConfirmMessage(state: PersonalWeeklyTasksUiState): String {
    val refreshCost = state.nextRefreshCostCoins
    return when {
        state.freeRefreshAvailable -> stringResource(R.string.home_weekly_tasks_refresh_message_free)
        refreshCost != null && refreshCost > 0 ->
            stringResource(R.string.home_weekly_tasks_refresh_message_paid, refreshCost)
        else -> stringResource(R.string.home_weekly_tasks_refresh_message_free)
    }
}

@Composable
private fun refreshConfirmAction(state: PersonalWeeklyTasksUiState): String {
    val refreshCost = state.nextRefreshCostCoins
    return when {
        state.freeRefreshAvailable -> stringResource(R.string.home_weekly_tasks_refresh_confirm_free)
        refreshCost != null && refreshCost > 0 ->
            stringResource(R.string.home_weekly_tasks_refresh_confirm_paid, refreshCost)
        else -> stringResource(R.string.home_weekly_tasks_refresh_confirm_free)
    }
}

@Composable
private fun newMenuCountdownText(weekEnd: String?): String? {
    if (weekEnd.isNullOrBlank()) return null
    return runCatching {
        val end = java.time.Instant.parse(weekEnd)
        val now = java.time.Instant.now()
        if (!end.isAfter(now)) return@runCatching stringResource(R.string.home_weekly_tasks_new_menu_soon)
        val hours = java.time.Duration.between(now, end).toHours()
        when {
            hours >= 24 -> {
                val days = (hours / 24).toInt()
                if (days == 1) {
                    stringResource(R.string.home_weekly_tasks_new_menu_in_day)
                } else {
                    stringResource(R.string.home_weekly_tasks_new_menu_in_days, days)
                }
            }
            else -> {
                val h = hours.coerceAtLeast(1).toInt()
                if (h == 1) {
                    stringResource(R.string.home_weekly_tasks_new_menu_in_hour)
                } else {
                    stringResource(R.string.home_weekly_tasks_new_menu_in_hours, h)
                }
            }
        }
    }.getOrNull()
}

@Composable
private fun PersonalWeeklyTaskCard(
    task: UserWeeklyTaskUi,
    isAccepting: Boolean,
    isUnaccepting: Boolean,
    onTap: () -> Unit,
    onAccept: () -> Unit,
    onUnaccept: () -> Unit,
) {
    val categoryLabel = when (task.category.lowercase()) {
        "cardio" -> "Cardio"
        "strength" -> stringResource(R.string.home_filter_strength)
        "sport" -> stringResource(R.string.home_filter_sport)
        else -> task.category.replaceFirstChar { it.uppercase() }
    }
    val statusLabel = when (task.status) {
        "accepted" -> stringResource(R.string.home_weekly_tasks_status_accepted)
        "completed" -> stringResource(R.string.home_weekly_tasks_status_completed)
        "expired" -> stringResource(R.string.home_weekly_tasks_status_expired)
        else -> stringResource(R.string.home_weekly_tasks_status_available)
    }
    val statusColor = when {
        task.isCompleted -> Color(0xFF4CAF50)
        task.isAccepted -> Color(0xFFFF9800)
        else -> Color(0xFF42A5F5)
    }
    val borderColor = when {
        task.isCompleted -> Color(0xFF4CAF50).copy(alpha = 0.55f)
        task.isAccepted -> Color(0xFFFF9800).copy(alpha = 0.55f)
        task.isGenerated -> Color(0xFF42A5F5).copy(alpha = 0.35f)
        else -> Color.White.copy(alpha = 0.18f)
    }
    val progressColor = if (task.isCompleted) Color(0xFF4CAF50) else Color(0xFFFF9800)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onTap)
            .background(
                MaterialTheme.colorScheme.surface.copy(alpha = 0.55f),
                RoundedCornerShape(14.dp)
            )
            .border(
                if (task.isAccepted || task.isCompleted) 2.dp else 1.dp,
                borderColor,
                RoundedCornerShape(14.dp)
            )
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(categoryLabel, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                task.difficultyBand?.let { band ->
                    Text(
                        band.replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Text(statusLabel, style = MaterialTheme.typography.labelMedium, color = statusColor, fontWeight = FontWeight.SemiBold)
        }
        Text(task.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(task.description, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (task.isCompleted) {
            Text(
                stringResource(
                    R.string.home_weekly_tasks_rewards_claimed,
                    task.rewardXp,
                    task.rewardCoins,
                    task.rewardTaskPoints
                ),
                style = MaterialTheme.typography.labelMedium,
                color = Color(0xFF4CAF50),
                fontWeight = FontWeight.SemiBold
            )
        } else {
            Text(
                "${task.rewardXp} XP · ${task.rewardCoins} coins · ${task.rewardTaskPoints} TP",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (task.showsProgressBlock) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    stringResource(R.string.home_weekly_tasks_progress),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    "${task.progressPercentInt}%",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            LinearProgressIndicator(
                progress = { task.displayProgressRatio },
                modifier = Modifier.fillMaxWidth(),
                color = progressColor,
            )
            Text(
                "${task.progressCurrentLabel} / ${task.progressTargetLabel}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (task.isGenerated) {
            Button(
                onClick = onAccept,
                enabled = !task.isLocked && !isAccepting,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (task.isLocked) MaterialTheme.colorScheme.surfaceVariant else Color(0xFFFF9800),
                    contentColor = if (task.isLocked) MaterialTheme.colorScheme.onSurfaceVariant else Color.White
                )
            ) {
                if (isAccepting) {
                    CircularProgressIndicator(modifier = Modifier.height(18.dp))
                } else {
                    Text(
                        if (task.isLocked) {
                            stringResource(R.string.home_weekly_tasks_slots_full)
                        } else {
                            stringResource(R.string.home_weekly_tasks_accept)
                        }
                    )
                }
            }
        }
        if (task.isAccepted) {
            Button(
                onClick = onUnaccept,
                enabled = !isUnaccepting,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                )
            ) {
                if (isUnaccepting) {
                    CircularProgressIndicator(modifier = Modifier.height(18.dp))
                } else {
                    Text(stringResource(R.string.home_weekly_tasks_unaccept))
                }
            }
        }
    }
}
