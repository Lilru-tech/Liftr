package com.lilru.liftr.ui.competition

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GppGood
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
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
import io.github.jan.supabase.SupabaseClient
import java.time.Duration
import java.time.Instant
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun CompetitionsHubScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    contextOpponentId: String? = null,
    modifier: Modifier = Modifier
) {
    val vm: CompetitionsHubViewModel = viewModel(
        key = "competitions-${contextOpponentId ?: "all"}",
        factory = CompetitionsHubViewModelFactory(supabase, contextOpponentId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val myId = ui.myUserId
    var openDetail by remember { mutableStateOf<CompetitionRowUi?>(null) }
    var showReviews by remember { mutableStateOf(false) }

    if (showReviews) {
        CompetitionReviewsScreen(
            supabase = supabase,
            onBack = { showReviews = false },
            modifier = modifier
        )
        return
    }
    if (openDetail != null) {
        CompetitionDetailScreen(
            supabase = supabase,
            competition = openDetail!!,
            goal = ui.goalsByCompId[openDetail!!.id],
            knownProfiles = ui.profilesById,
            onBack = { openDetail = null },
            modifier = modifier
        )
        return
    }

    LaunchedEffect(Unit) { vm.refresh(isPull = false) }

    val pullState = rememberPullRefreshState(
        refreshing = ui.isRefreshing,
        onRefresh = { vm.refresh(isPull = true) }
    )

    val tabs = listOf(CompetitionsHubTab.Active, CompetitionsHubTab.Pending, CompetitionsHubTab.History)
    val list = when (ui.tab) {
        CompetitionsHubTab.Active -> ui.active
        CompetitionsHubTab.Pending -> ui.pending
        CompetitionsHubTab.History -> ui.history
    }
    val headToHead = remember(ui.history, contextOpponentId, myId) {
        if (contextOpponentId == null || myId == null) {
            emptyList()
        } else {
            ui.history.filter { c ->
                (c.userA == contextOpponentId || c.userB == contextOpponentId) &&
                    (c.userA == myId || c.userB == myId)
            }
        }
    }
    val headToHeadIds = remember(headToHead) { headToHead.map { it.id }.toSet() }
    val listWithoutHeadRepeat = remember(list, headToHeadIds, ui.tab) {
        if (ui.tab == CompetitionsHubTab.History) {
            list.filter { it.id !in headToHeadIds }
        } else {
            list
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                stringResource(R.string.competitions_title),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.weight(1f, fill = true)
            )
            IconButton(onClick = { showReviews = true }) {
                Icon(
                    imageVector = Icons.Filled.GppGood,
                    contentDescription = stringResource(R.string.competitions_reviews_content_desc)
                )
            }
        }
        SingleChoiceSegmentedButtonRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 4.dp)
        ) {
            tabs.forEachIndexed { index, tab ->
                SegmentedButton(
                    selected = ui.tab == tab,
                    onClick = { vm.setTab(tab) },
                    shape = SegmentedButtonDefaults.itemShape(index, tabs.size)
                ) {
                    Text(
                        when (tab) {
                            CompetitionsHubTab.Active -> stringResource(R.string.competitions_tab_active)
                            CompetitionsHubTab.Pending -> stringResource(R.string.competitions_tab_pending)
                            CompetitionsHubTab.History -> stringResource(R.string.competitions_tab_history)
                        },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
        when {
            ui.loading && !ui.isRefreshing -> {
                Box(
                    Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(Modifier.padding(24.dp))
                }
            }
            ui.error != null && ui.competitions.isEmpty() && !ui.isRefreshing -> {
                Text(
                    ui.error!!,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.weight(1f, fill = true)
                )
            }
            else -> {
                Box(Modifier.weight(1f)) {
                    Box(Modifier
                        .fillMaxSize()
                        .pullRefresh(pullState)
                    ) {
                        LazyColumn(
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier.fillMaxSize()
                        ) {
                            if (ui.error != null) {
                                item {
                                    Text(
                                        ui.error!!,
                                        color = MaterialTheme.colorScheme.error
                                    )
                                }
                            }
                            if (ui.tab == CompetitionsHubTab.History) {
                                item {
                                    ui.historySummary?.let { s -> HistorySummaryCard(s) }
                                }
                            }
                            if (ui.tab == CompetitionsHubTab.History && headToHead.isNotEmpty()) {
                                item {
                                    Text(
                                        stringResource(R.string.competitions_vs_user_section),
                                        style = MaterialTheme.typography.titleSmall,
                                        modifier = Modifier.padding(vertical = 4.dp)
                                    )
                                }
                            }
                            items(headToHead, key = { "h2h-${it.id}" }) { c ->
                                CompetitionCard(
                                    row = c,
                                    goal = ui.goalsByCompId[c.id],
                                    myId = myId,
                                    profiles = ui.profilesById,
                                    progress = ui.progressByCompId[c.id] ?: emptyMap(),
                                    onAccept = null,
                                    onDecline = null,
                                    onCancel = null,
                                    onBlock = null,
                                    onOpenDetail = { openDetail = c }
                                )
                            }
                            if (listWithoutHeadRepeat.isEmpty() && (ui.tab != CompetitionsHubTab.History || headToHead.isEmpty())) {
                                item {
                                    val empty = when (ui.tab) {
                                        CompetitionsHubTab.Active -> stringResource(R.string.competitions_empty_active)
                                        CompetitionsHubTab.Pending -> stringResource(R.string.competitions_empty_pending)
                                        CompetitionsHubTab.History -> stringResource(R.string.competitions_empty_history)
                                    }
                                    Text(
                                        empty,
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(top = 16.dp)
                                    )
                                }
                            }
                            items(listWithoutHeadRepeat, key = { it.id }) { c ->
                                val pending = ui.tab == CompetitionsHubTab.Pending
                                CompetitionCard(
                                    row = c,
                                    goal = ui.goalsByCompId[c.id],
                                    myId = myId,
                                    profiles = ui.profilesById,
                                    progress = ui.progressByCompId[c.id] ?: emptyMap(),
                                    onAccept = if (pending) {
                                        { if (!ui.actionBusy) vm.acceptCompetition(c.id) }
                                    } else {
                                        null
                                    },
                                    onDecline = if (pending) {
                                        { if (!ui.actionBusy) vm.declineCompetition(c.id) }
                                    } else {
                                        null
                                    },
                                    onCancel = if (pending) {
                                        { if (!ui.actionBusy) vm.cancelCompetition(c.id) }
                                    } else {
                                        null
                                    },
                                    onBlock = if (pending) {
                                        { oid -> vm.blockUser(oid) }
                                    } else {
                                        null
                                    },
                                    onOpenDetail = { openDetail = c }
                                )
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
        }
    }
}

@Composable
private fun HistorySummaryCard(summary: CompetitionHistorySummaryUi) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(stringResource(R.string.competitions_summary), style = MaterialTheme.typography.titleSmall)
                Text(
                    stringResource(
                        R.string.competitions_win_rate,
                        (summary.winRate * 100).roundToInt()
                    ),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatPill(
                    stringResource(R.string.competitions_stat_competitions),
                    "${summary.totalHistory}",
                    Modifier.weight(1f)
                )
                StatPill(
                    stringResource(R.string.competitions_stat_finished),
                    "${summary.finished}",
                    Modifier.weight(1f)
                )
                StatPill(
                    stringResource(R.string.competitions_stat_wld),
                    "${summary.wins}-${summary.losses}-${summary.draws}",
                    Modifier.weight(1f)
                )
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.competitions_most_challenged),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f)
                )
                LiftrAvatar(
                    imageUrl = summary.mostChallengedOpponentAvatar,
                    displayName = summary.mostChallengedOpponentName,
                    size = 28.dp
                )
                Text(
                    summary.mostChallengedOpponentName,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(start = 6.dp)
                )
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.competitions_best_rival),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f)
                )
                LiftrAvatar(
                    imageUrl = summary.bestRivalAvatar,
                    displayName = summary.bestRivalName,
                    size = 28.dp
                )
                Column(Modifier.padding(start = 6.dp), horizontalAlignment = Alignment.End) {
                    Text(summary.bestRivalName, style = MaterialTheme.typography.labelMedium)
                    Text(
                        "${summary.bestRivalWinRateText} · ${summary.bestRivalRecordText}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    stringResource(R.string.competitions_favorite_metric),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(summary.favoriteMetricLabel, style = MaterialTheme.typography.labelMedium)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    stringResource(R.string.competitions_avg_duration),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(summary.avgDurationText, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

@Composable
private fun StatPill(label: String, value: String, modifier: Modifier = Modifier) {
    Card(modifier = modifier, colors = CardDefaults.cardColors()) {
        Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleSmall)
        }
    }
}

@Composable
private fun CompetitionCard(
    row: CompetitionRowUi,
    goal: CompetitionGoalUi?,
    myId: String?,
    profiles: Map<String, ProfileLiteUi>,
    progress: Map<String, CompetitionProgressUi>,
    onAccept: (() -> Unit)?,
    onDecline: (() -> Unit)?,
    onCancel: (() -> Unit)?,
    onBlock: ((opponentId: String) -> Unit)?,
    onOpenDetail: (() -> Unit)? = null,
) {
    val opponentId = if (myId == null) null else {
        if (row.userA == myId) row.userB else row.userA
    }
    val opp = opponentId?.let { profiles[it] }
    val statusLine = statusLabelForDisplay(row.status)
    val goalText = goalTextString(goal)
    val now = remember { Instant.now() }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val openMod = onOpenDetail?.let { o ->
                Modifier
                    .fillMaxWidth()
                    .clickable(onClick = o)
            } ?: Modifier.fillMaxWidth()
            Column(openMod) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    LiftrAvatar(
                        imageUrl = opp?.avatarUrl,
                        displayName = opp?.username,
                        size = 40.dp
                    )
                    Column(Modifier.weight(1f).padding(horizontal = 8.dp)) {
                        Text(opp?.username ?: stringResource(R.string.competitions_opponent), style = MaterialTheme.typography.titleSmall)
                        Text(statusLine, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    when (row.status) {
                        "pending" -> {
                            val exp = runCatching { formatCompetitionDateTime(row.inviteExpiresAt) }.getOrDefault(row.inviteExpiresAt)
                            Text(
                                stringResource(R.string.competitions_expires, exp),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        "active" -> {
                            val tl = goal?.timeLimitAtIso
                            if (tl != null) {
                                Text(
                                    timeLimitRemainingLabel(tl, now),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        else -> { }
                    }
                }
                if (row.status == "active") {
                    val metric = goal?.metric
                    val target = goal?.targetValue
                    val pa = progress[row.userA] ?: CompetitionProgressUi()
                    val pb = progress[row.userB] ?: CompetitionProgressUi()
                    Text(
                        stringResource(R.string.competitions_progress_header),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    ProgressRow(
                        name = profiles[row.userA]?.username ?: "A",
                        isMe = myId == row.userA,
                        p = pa,
                        metric = metric,
                        targetValue = target
                    )
                    ProgressRow(
                        name = profiles[row.userB]?.username ?: "B",
                        isMe = myId == row.userB,
                        p = pb,
                        metric = metric,
                        targetValue = target
                    )
                } else {
                    Text(stringResource(R.string.competitions_goal_header), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(goalText, style = MaterialTheme.typography.bodyMedium)
                    val tl = goal?.timeLimitAtIso
                    if (tl != null) {
                        val formatted = runCatching { formatCompetitionDateTime(tl) }.getOrDefault(tl)
                        Text(
                            stringResource(R.string.competitions_time_limit_line, formatted),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            if (row.status == "pending" && myId != null && opponentId != null) {
                val invitedId = if (row.createdBy == row.userA) row.userB else row.userA
                val amInvited = myId == invitedId
                if (amInvited && onAccept != null && onDecline != null) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = onDecline, modifier = Modifier.weight(1f)) {
                            Text(stringResource(R.string.competitions_pending_decline))
                        }
                        FilledTonalButton(onClick = onAccept, modifier = Modifier.weight(1f)) {
                            Text(stringResource(R.string.competitions_pending_accept))
                        }
                    }
                } else if (myId == row.createdBy && onCancel != null) {
                    OutlinedButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.competitions_pending_cancel))
                    }
                }
                if (onBlock != null) {
                    TextButton(onClick = { onBlock(opponentId) }, modifier = Modifier.fillMaxWidth()) {
                        Text(
                            stringResource(R.string.competitions_block_user),
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun goalTextString(goal: CompetitionGoalUi?): String {
    if (goal?.metric == null && goal?.timeLimitAtIso != null) {
        return stringResource(R.string.competitions_goal_time_limit_only)
    }
    val m = goal?.metric ?: return stringResource(R.string.competitions_goal_generic)
    val tv = goal?.targetValue ?: 0.0
    val n = max(0, tv.roundToInt())
    return when (m) {
        "workouts" -> stringResource(R.string.competitions_goal_workouts, n)
        "calories" -> stringResource(R.string.competitions_goal_calories, n)
        "score" -> stringResource(R.string.competitions_goal_score, n)
        else -> stringResource(R.string.competitions_goal_generic)
    }
}

@Composable
private fun timeLimitRemainingLabel(tlIso: String, now: Instant): String {
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
private fun ProgressRow(
    name: String,
    isMe: Boolean,
    p: CompetitionProgressUi,
    metric: String?,
    targetValue: Double?,
) {
    val valueLine = if (metric == null) {
        stringResource(
            R.string.competitions_value_mixed,
            p.workoutsCount,
            p.caloriesTotal.roundToInt(),
            p.scoreTotal.roundToInt()
        )
    } else {
        when (metric) {
            "workouts" -> stringResource(
                R.string.competitions_value_workouts,
                p.workoutsCount
            )
            "calories" -> stringResource(
                R.string.competitions_value_kcal,
                p.caloriesTotal.roundToInt()
            )
            "score" -> stringResource(
                R.string.competitions_value_score,
                p.scoreTotal.roundToInt()
            )
            else -> stringResource(
                R.string.competitions_value_mixed,
                p.workoutsCount,
                p.caloriesTotal.roundToInt(),
                p.scoreTotal.roundToInt()
            )
        }
    }
    val ratio = if (targetValue == null || targetValue <= 0) {
        null
    } else {
        val current = when (metric) {
            "workouts" -> p.workoutsCount.toDouble()
            "calories" -> p.caloriesTotal
            "score" -> p.scoreTotal
            else -> 0.0
        }
        min(1.0, max(0.0, current / targetValue)).toFloat()
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                if (isMe) {
                    stringResource(R.string.competitions_user_you, name)
                } else {
                    name
                },
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                valueLine,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary
            )
        }
        if (ratio != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LinearProgressIndicator(
                    progress = { ratio },
                    modifier = Modifier.weight(1f)
                )
                Text(
                    "${(ratio * 100f).roundToInt()}%",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
