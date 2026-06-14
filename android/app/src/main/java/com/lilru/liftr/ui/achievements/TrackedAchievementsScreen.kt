package com.lilru.liftr.ui.achievements

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlin.math.abs

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrackedAchievementsScreen(
    supabase: SupabaseClient,
    targetUserId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: AchievementsViewModel = viewModel(
        factory = AchievementsViewModelFactory(supabase, targetUserId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var selected by remember { mutableStateOf<AchievementRowUi?>(null) }
    val detailSheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val tracked = ui.items.filter { it.isTracked }.sortedBy { it.title.lowercase() }

    LaunchedEffect(ui.items) {
        if (selected != null && tracked.none { it.achievementId == selected!!.achievementId }) {
            selected = null
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Text(
            stringResource(R.string.achievements_tracked_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            stringResource(R.string.achievements_tracked_count, tracked.size),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (ui.loading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else if (tracked.isEmpty()) {
            Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    stringResource(R.string.achievements_tracked_empty_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.achievements_tracked_empty_body),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(16.dp))
                Button(onClick = {
                    AppNavEvents.send(MainOverlay.Achievements())
                    onBack()
                }) {
                    Text(stringResource(R.string.achievements_tracked_browse))
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(tracked, key = { it.idKey }) { row ->
                    TrackedAchievementListRow(row = row, onClick = { selected = row })
                }
            }
        }
    }

    if (selected != null) {
        val row = selected!!
        val trackLimitReached = !row.isTracked && ui.trackedCount >= 5
        ModalBottomSheet(
            onDismissRequest = { selected = null },
            sheetState = detailSheet
        ) {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(row.title, style = MaterialTheme.typography.titleMedium)
                Text(
                    prettySubtypeFromCode(row.code, row.category),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                val target = row.requirementValue ?: 0.0
                if (target > 0) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(stringResource(R.string.achievements_progress_label))
                            Text(stringResource(R.string.achievements_progress_percent, row.progressPercentInt))
                        }
                        LinearProgressIndicator(
                            progress = { row.progressFraction },
                            modifier = Modifier.fillMaxWidth().height(8.dp)
                        )
                        if (row.progressCurrent != null) {
                            Text(
                                "${formatAchievementGoalNumber(row.progressCurrent!!)} / ${formatAchievementGoalNumber(target)}",
                                style = MaterialTheme.typography.labelMedium
                            )
                        } else {
                            Text(
                                stringResource(R.string.achievements_tracked_refresh_hint),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.outline
                            )
                        }
                    }
                }
                if (!row.isUnlocked) {
                    OutlinedButton(
                        onClick = { vm.toggleTrack(row.achievementId) },
                        enabled = !ui.trackBusy && !trackLimitReached,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(
                            imageVector = if (row.isTracked) Icons.Filled.CheckCircle else Icons.Outlined.CheckCircle,
                            contentDescription = null,
                            modifier = Modifier.padding(end = 8.dp)
                        )
                        Text(
                            if (row.isTracked) {
                                stringResource(R.string.achievements_tracking)
                            } else {
                                stringResource(R.string.achievements_track_action)
                            }
                        )
                    }
                }
                OutlinedButton(
                    onClick = { selected = null },
                    modifier = Modifier.fillMaxWidth()
                ) { Text(stringResource(R.string.feature_requests_close)) }
            }
        }
    }
}

@Composable
private fun TrackedAchievementListRow(
    row: AchievementRowUi,
    onClick: () -> Unit
) {
    val symbol = imageVectorForAchievement(row.code, row.category)
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        Column(
            Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = symbol,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp)
                )
                Column(Modifier.weight(1f)) {
                    Text(row.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text(
                        prettySubtypeFromCode(row.code, row.category),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    stringResource(R.string.achievements_progress_percent, row.progressPercentInt),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            LinearProgressIndicator(
                progress = { row.progressFraction },
                modifier = Modifier.fillMaxWidth().height(8.dp)
            )
            if (row.progressCurrent != null && (row.requirementValue ?: 0.0) > 0) {
                Text(
                    "${formatAchievementGoalNumber(row.progressCurrent!!)} / ${formatAchievementGoalNumber(row.requirementValue!!)}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else if (row.requirementValue != null) {
                Text(
                    stringResource(R.string.achievements_tracked_refresh_hint),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.outline
                )
            }
        }
    }
}

private fun formatAchievementGoalNumber(v: Double): String =
    if (abs(v - v.toInt()) < 1e-6) v.toInt().toString() else String.format(java.util.Locale.US, "%.1f", v)
