package com.lilru.liftr.ui.ranking

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LocalMinimumInteractiveComponentEnforcement
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.lilru.liftr.BuildConfig
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.home.WorkoutDetailScreen
import com.lilru.liftr.ui.profile.ProfileTabScreen
import io.github.jan.supabase.SupabaseClient

/** Paridad con [com.lilru.liftr.ui.profile.progress.ProfileProgressScreen]: píldoras bajas estilo iOS. */
private val RankingSegmentButtonHeight = 30.dp
private val RankingSegmentRowSpacing = 6.dp

@Composable
private fun RankingSegmentLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        fontSize = 11.sp,
        lineHeight = 13.sp,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis
    )
}

@Composable
private fun rankingMetricButtonLabel(metric: RankingMetric) = when (metric) {
    RankingMetric.SCORE -> stringResource(R.string.ranking_metric_score)
    RankingMetric.CALORIES -> stringResource(R.string.ranking_metric_calories)
    RankingMetric.LEVEL -> stringResource(R.string.ranking_metric_level)
    RankingMetric.BEST_WORKOUT -> stringResource(R.string.ranking_metric_top_workouts)
    RankingMetric.GOALS_COMPLETED -> stringResource(R.string.ranking_metric_goals)
    RankingMetric.DUELS_WON -> stringResource(R.string.ranking_metric_duels)
}

@OptIn(ExperimentalMaterialApi::class, ExperimentalMaterial3Api::class)
@Composable
fun RankingTabScreen(
    supabase: SupabaseClient,
    onOpenAddWithPendingDuplicate: () -> Unit = {},
    rankingInitial: RankingInitial? = null,
    embedBack: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val vmKey = if (embedBack != null) {
        "ranking-embed-${rankingInitial?.metric}-${rankingInitial?.scope}"
    } else {
        "ranking-tab-main"
    }
    val rankingCtx = LocalContext.current
    var isPremium by remember { mutableStateOf(LiftrPreferences.isPremium(rankingCtx)) }
    LaunchedEffect(rankingCtx) {
        isPremium = LiftrPreferences.isPremium(rankingCtx)
    }
    val vm: RankingViewModel = viewModel(
        key = vmKey,
        factory = RankingViewModelFactory(supabase, rankingInitial)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var selectedWorkout by rememberSaveable { mutableStateOf<Long?>(null) }
    var selectedProfile by rememberSaveable { mutableStateOf<String?>(null) }

    if (selectedWorkout != null) {
        WorkoutDetailScreen(
            supabase = supabase,
            workoutId = selectedWorkout!!.toInt(),
            onBack = { selectedWorkout = null },
            onDuplicateToAdd = {
                onOpenAddWithPendingDuplicate()
                selectedWorkout = null
            },
            modifier = modifier
        )
        return
    }
    if (selectedProfile != null) {
        ProfileTabScreen(
            supabase = supabase,
            onSignOut = {},
            targetUserId = selectedProfile,
            showSignOutButton = false,
            onBack = { selectedProfile = null },
            modifier = modifier
        )
        return
    }

    val pull = rememberPullRefreshState(
        refreshing = ui.isRefreshing,
        onRefresh = { vm.refresh(false) }
    )
    val columnBase = if (embedBack != null) {
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
    } else {
        Modifier.fillMaxSize()
    }
    Box(modifier = modifier.fillMaxSize()) {
        Column(modifier = columnBase) {
            LazyColumn(
                modifier = Modifier
                    .weight(1f, fill = true)
                    .fillMaxWidth()
                    .pullRefresh(pull)
                    .padding(horizontal = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
        if (embedBack != null) {
            item {
                LiftrBackTopBar(
                    onBack = embedBack,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }
        item {
            Text(
                text = stringResource(R.string.ranking_title),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp)
            )
        }
        item {
            CompositionLocalProvider(LocalMinimumInteractiveComponentEnforcement provides false) {
                val scopes = RankingScope.entries
                val periods = RankingPeriod.entries
                val kinds = RankingKind.entries
                Column(verticalArrangement = Arrangement.spacedBy(RankingSegmentRowSpacing)) {
                    val metricsA = listOf(
                        RankingMetric.SCORE,
                        RankingMetric.CALORIES,
                        RankingMetric.LEVEL
                    )
                    val metricsB = listOf(
                        RankingMetric.BEST_WORKOUT,
                        RankingMetric.GOALS_COMPLETED,
                        RankingMetric.DUELS_WON
                    )
                    val showPeriodAndKind = when (ui.metric) {
                        RankingMetric.SCORE,
                        RankingMetric.CALORIES,
                        RankingMetric.BEST_WORKOUT -> true
                        else -> false
                    }
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        scopes.forEachIndexed { i, scope ->
                            SegmentedButton(
                                selected = ui.scope == scope,
                                onClick = { vm.setScope(scope) },
                                shape = SegmentedButtonDefaults.itemShape(i, scopes.size),
                                modifier = Modifier
                                    .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                    .height(RankingSegmentButtonHeight)
                            ) {
                                RankingSegmentLabel(
                                    if (scope == RankingScope.GLOBAL) {
                                        stringResource(R.string.ranking_scope_global)
                                    } else {
                                        stringResource(R.string.ranking_scope_friends)
                                    }
                                )
                            }
                        }
                    }
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        metricsA.forEachIndexed { i, metric ->
                            SegmentedButton(
                                selected = ui.metric == metric,
                                onClick = { vm.setMetric(metric) },
                                shape = SegmentedButtonDefaults.itemShape(i, metricsA.size),
                                modifier = Modifier
                                    .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                    .height(RankingSegmentButtonHeight)
                            ) {
                                RankingSegmentLabel(rankingMetricButtonLabel(metric))
                            }
                        }
                    }
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        metricsB.forEachIndexed { i, metric ->
                            SegmentedButton(
                                selected = ui.metric == metric,
                                onClick = { vm.setMetric(metric) },
                                shape = SegmentedButtonDefaults.itemShape(i, metricsB.size),
                                modifier = Modifier
                                    .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                    .height(RankingSegmentButtonHeight)
                            ) {
                                RankingSegmentLabel(rankingMetricButtonLabel(metric))
                            }
                        }
                    }
                    if (showPeriodAndKind) {
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            periods.forEachIndexed { i, period ->
                                SegmentedButton(
                                    selected = ui.period == period,
                                    onClick = { vm.setPeriod(period) },
                                    shape = SegmentedButtonDefaults.itemShape(i, periods.size),
                                    modifier = Modifier
                                        .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                        .height(RankingSegmentButtonHeight)
                                ) {
                                    RankingSegmentLabel(
                                        when (period) {
                                            RankingPeriod.DAY -> "Today"
                                            RankingPeriod.WEEK -> "This Week"
                                            RankingPeriod.MONTH -> "This Month"
                                            RankingPeriod.ALL -> "All-time"
                                        }
                                    )
                                }
                            }
                        }
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            kinds.forEachIndexed { i, kind ->
                                SegmentedButton(
                                    selected = ui.kind == kind,
                                    onClick = { vm.setKind(kind) },
                                    shape = SegmentedButtonDefaults.itemShape(i, kinds.size),
                                    modifier = Modifier
                                        .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                        .height(RankingSegmentButtonHeight)
                                ) {
                                    RankingSegmentLabel(
                                        when (kind) {
                                            RankingKind.ALL -> "All"
                                            RankingKind.STRENGTH -> "Strength"
                                            RankingKind.CARDIO -> "Cardio"
                                            RankingKind.SPORT -> "Sport"
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        if (ui.loading) {
            item { Text(stringResource(R.string.ranking_loading)) }
        }
        if (ui.error != null) {
            item {
                Text(
                    text = ui.error ?: "",
                    color = MaterialTheme.colorScheme.error
                )
            }
        }

        if (ui.workoutRows.isNotEmpty()) {
            items(ui.workoutRows, key = { "${it.workoutId}-${it.rank}" }) { row ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { selectedWorkout = row.workoutId }
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        LiftrAvatar(
                            imageUrl = row.avatarUrl,
                            displayName = row.username,
                            size = 40.dp
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                "#${row.rank}  ${row.username ?: row.userId}",
                                style = MaterialTheme.typography.titleSmall
                            )
                            Text(
                                "${row.kind ?: "-"} • ${row.title ?: "Workout ${row.workoutId}"}",
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Text("Score: ${row.score}", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        } else {
            items(ui.userRows, key = { "${it.userId}-${it.rank}" }) { row ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { selectedProfile = row.userId }
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        LiftrAvatar(
                            imageUrl = row.avatarUrl,
                            displayName = row.username,
                            size = 40.dp
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                "#${row.rank}  ${row.username ?: row.userId}",
                                style = MaterialTheme.typography.titleSmall
                            )
                            Text(row.primary, style = MaterialTheme.typography.bodyMedium)
                            Text(row.secondary, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
            }
            if (!isPremium) {
                AndroidView(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp),
                    factory = { ctx ->
                        AdView(ctx).apply {
                            setAdSize(AdSize.BANNER)
                            adUnitId = BuildConfig.AD_BANNER_UNIT_ID
                            loadAd(AdRequest.Builder().build())
                        }
                    }
                )
            }
        }
        PullRefreshIndicator(
            refreshing = ui.isRefreshing,
            state = pull,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }
}
