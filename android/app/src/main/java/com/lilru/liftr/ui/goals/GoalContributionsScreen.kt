package com.lilru.liftr.ui.goals

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
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
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.home.HomeWorkoutFeedCard
import com.lilru.liftr.ui.home.WorkoutSummary
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Paridad con [GoalContributionsView] (iOS): [Week summary] con rejilla, By type, y [WorkoutFeedCard].
 */
@Composable
fun GoalContributionsScreen(
    goal: GoalRowUi,
    vm: GoalsViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var rows by remember { mutableStateOf(listOf<WorkoutSummary>()) }
    var loading by remember { mutableStateOf(true) }
    var err by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(goal.id) {
        loading = true
        err = null
        val r = withContext(Dispatchers.IO) { runCatching { vm.loadContributions(goal) } }
        loading = false
        r.onSuccess { rows = it }
        r.onFailure { e -> err = e.message?.take(200) }
    }
    val summary = remember(goal, rows) {
        if (rows.isEmpty()) null else buildGoalContributionsSummary(goal, rows)
    }
    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Text(goal.title, style = MaterialTheme.typography.titleLarge)
        Text(
            "${GoalMetric.fromWire(goal.metric).title} · ${goal.weekStartDate}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        when {
            loading -> {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .weight(1f, fill = true),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }
            err != null -> Text(err!!, color = MaterialTheme.colorScheme.error)
            rows.isEmpty() && !loading -> {
                Text(
                    stringResource(R.string.goals_contrib_empty),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            else -> {
                val s = summary
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f, fill = true)
                ) {
                    if (s != null) {
                        item(key = "summary") {
                            ContribSummaryCard(goal = goal, s = s)
                        }
                    }
                    items(items = rows, key = { it.id }) { w ->
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

@Composable
private fun ContribStatTile(modifier: Modifier, label: String, value: String) {
    val vShape = RoundedCornerShape(10.dp)
    Column(
        modifier
            .background(Color.White.copy(alpha = 0.08f), vShape)
            .border(0.6.dp, Color.White.copy(alpha = 0.10f), vShape)
            .padding(horizontal = 10.dp, vertical = 8.dp)
            .fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            value,
            style = MaterialTheme.typography.titleSmall.copy(
                fontWeight = FontWeight.SemiBold,
                fontFeatureSettings = "tnum"
            )
        )
    }
}

@Composable
private fun ContribStatGrid(s: GoalContributionsSummaryUi) {
    val statRows = listOf(
        stringResource(R.string.goals_contrib_stat_workouts) to s.workoutCount.toString(),
        stringResource(R.string.goals_contrib_stat_total_score) to s.totalScore.toString(),
        stringResource(R.string.goals_contrib_stat_avg_score) to s.avgScore.toString(),
        stringResource(R.string.goals_contrib_stat_max_score) to s.maxScore.toString(),
        stringResource(R.string.goals_contrib_stat_total_kcal) to s.totalKcal.toString(),
        stringResource(R.string.goals_contrib_stat_avg_kcal) to s.avgKcal.toString(),
        stringResource(R.string.goals_contrib_stat_max_kcal) to s.maxKcal.toString(),
        stringResource(R.string.goals_contrib_stat_active_days) to s.activeDays.toString()
    )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        for (rowItems in statRows.chunked(3)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                for ((label, value) in rowItems) {
                    ContribStatTile(
                        Modifier.weight(1f),
                        label,
                        value
                    )
                }
                repeat(3 - rowItems.size) {
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun ContribSummaryCard(goal: GoalRowUi, s: GoalContributionsSummaryUi) {
    val metric = GoalMetric.fromWire(goal.metric)
    val cardShape = RoundedCornerShape(14.dp)
    val pillShape = RoundedCornerShape(50)
    Column(
        Modifier
            .fillMaxWidth()
            .background(
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.75f),
                shape = cardShape
            )
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), cardShape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.goals_contrib_week_summary),
                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold)
            )
            Spacer(Modifier.weight(1f))
            Text(
                metric.title,
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            s.goalProgressLine,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        ContribStatGrid(s)
        if (s.kindCounts.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    stringResource(R.string.goals_contrib_by_type),
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    s.kindCounts.forEach { (k, n) ->
                        val label = k.replaceFirstChar { c -> c.titlecase() }
                        Text(
                            "$label · $n",
                            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier
                                .background(Color.White.copy(alpha = 0.10f), pillShape)
                                .border(0.5.dp, Color.White.copy(alpha = 0.12f), pillShape)
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }
                }
            }
        }
    }
}
