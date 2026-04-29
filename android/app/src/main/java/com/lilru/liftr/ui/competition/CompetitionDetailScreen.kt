package com.lilru.liftr.ui.competition

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.home.WorkoutDetailScreen
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import java.time.Duration
import java.time.Instant
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun CompetitionDetailScreen(
    supabase: SupabaseClient,
    competition: CompetitionRowUi,
    goal: CompetitionGoalUi?,
    knownProfiles: Map<String, ProfileLiteUi>,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: CompetitionDetailViewModel = viewModel(
        key = "comp-d-${competition.id}",
        factory = CompetitionDetailViewModelFactory(supabase, competition.id, knownProfiles)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var openWorkoutId by remember { mutableStateOf<Int?>(null) }

    if (openWorkoutId != null) {
        WorkoutDetailScreen(
            supabase = supabase,
            workoutId = openWorkoutId!!,
            onBack = { openWorkoutId = null },
            modifier = modifier
        )
        return
    }

    val myId = supabase.auth.currentUserOrNull()?.id
    val opponentId = remember(myId, competition) {
        if (myId == null) null else
            if (competition.userA == myId) competition.userB else competition.userA
    }
    val opponent = opponentId?.let { knownProfiles[it] }
    val now = remember { Instant.now() }

    LaunchedEffect(competition.id) { vm.load(isPull = false) }

    val pullState = rememberPullRefreshState(
        refreshing = ui.isRefreshing,
        onRefresh = { vm.load(isPull = true) }
    )

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .pullRefresh(pullState)
                .verticalScroll(rememberScrollState())
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
        LiftrBackTopBar(onBack = onBack)
        Text(
            stringResource(R.string.competition_detail_title),
            style = MaterialTheme.typography.titleLarge
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            LiftrAvatar(
                imageUrl = opponent?.avatarUrl,
                displayName = opponent?.username,
                size = 40.dp
            )
            Column(Modifier.padding(horizontal = 8.dp)) {
                Text(
                    opponent?.username ?: stringResource(R.string.competitions_opponent),
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    goalLineComposable(goal),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (competition.status == "active") {
            val tl = goal?.timeLimitAtIso
            if (tl != null) {
                Text(
                    timeLimitRemainingForDetail(tl, now),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (ui.loading && !ui.isRefreshing) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(20.dp),
                horizontalArrangement = Arrangement.Center
            ) {
                CircularProgressIndicator()
            }
        } else if (ui.error != null) {
            Text(ui.error!!, color = MaterialTheme.colorScheme.error)
        } else if (ui.rows.isEmpty()) {
            Text(
                stringResource(R.string.competition_detail_no_workouts),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Text(stringResource(R.string.competition_detail_workouts), style = MaterialTheme.typography.titleSmall)
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.fillMaxWidth()) {
                    ui.rows.forEachIndexed { i, r ->
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .clickable { openWorkoutId = r.workoutId }
                                .padding(horizontal = 14.dp, vertical = 10.dp)
                        ) {
                            Text(
                                r.ownerName,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(r.titleOrKind, style = MaterialTheme.typography.bodyMedium)
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    r.status.uppercase(Locale.getDefault()),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    modifier = Modifier.padding(vertical = 2.dp, horizontal = 4.dp)
                                )
                                if (r.startedAtIso.isNotBlank()) {
                                    Text(
                                        formatCompetitionDateTime(r.startedAtIso),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                        if (i < ui.rows.size - 1) {
                            HorizontalDivider(Modifier.padding(start = 14.dp), thickness = 0.5.dp)
                        }
                    }
                }
            }
        }
        }
        PullRefreshIndicator(
            refreshing = ui.isRefreshing,
            state = pullState,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }
}

@Composable
private fun timeLimitRemainingForDetail(tlIso: String, now: Instant): String {
    val end = runCatching { Instant.parse(tlIso.trim()) }.getOrNull()
        ?: return stringResource(R.string.competitions_ended)
    if (!end.isAfter(now)) {
        return stringResource(R.string.competitions_ended)
    }
    val d = Duration.between(now, end)
    val days = d.toDays()
    val hours = d.toHours() % 24
    val mins = d.toMinutes() % 60
    return when {
        days > 0 -> stringResource(
            R.string.competitions_ends_in_days,
            days.toInt(),
            hours.toInt()
        )
        hours > 0 -> stringResource(
            R.string.competitions_ends_in_hours,
            hours.toInt(),
            mins.toInt()
        )
        else -> stringResource(
            R.string.competitions_ends_in_mins,
            max(1, mins.toInt())
        )
    }
}

@Composable
private fun goalLineComposable(goal: CompetitionGoalUi?): String {
    if (goal?.metric == null && goal?.timeLimitAtIso != null) {
        return stringResource(R.string.competitions_goal_time_limit_only)
    }
    val m = goal?.metric ?: return stringResource(R.string.competitions_goal_generic)
    val tv = goal.targetValue ?: 0.0
    val n = max(0, tv.roundToInt())
    return when (m) {
        "workouts" -> stringResource(R.string.competitions_goal_workouts, n)
        "calories" -> stringResource(R.string.competitions_goal_calories, n)
        "score" -> stringResource(R.string.competitions_goal_score, n)
        else -> stringResource(R.string.competitions_goal_generic)
    }
}
