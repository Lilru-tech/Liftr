package com.lilru.liftr.ui.ranking

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.items
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.LocalMinimumInteractiveComponentEnforcement
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.TextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import com.lilru.liftr.ui.segment.SegmentDetailScreen
import com.lilru.liftr.territory.TerritoryCaptureClient
import io.github.jan.supabase.SupabaseClient
import java.util.UUID

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
    RankingMetric.STRENGTH_VOLUME -> stringResource(R.string.ranking_metric_strength_volume)
    RankingMetric.STRENGTH_REPS -> stringResource(R.string.ranking_metric_strength_reps)
    RankingMetric.STRENGTH_SETS -> stringResource(R.string.ranking_metric_strength_sets)
    RankingMetric.STRENGTH_MAX_SET_WEIGHT -> stringResource(R.string.ranking_metric_strength_max_weight)
    RankingMetric.CARDIO_DISTANCE -> stringResource(R.string.ranking_metric_cardio_distance)
    RankingMetric.CARDIO_ELEVATION -> stringResource(R.string.ranking_metric_cardio_elevation)
    RankingMetric.CARDIO_DURATION -> stringResource(R.string.ranking_metric_cardio_duration)
    RankingMetric.CARDIO_BEST_PACE -> stringResource(R.string.ranking_metric_cardio_best_pace)
    RankingMetric.TERRITORY_SHARE -> stringResource(R.string.ranking_metric_territory_share)
    RankingMetric.SPORT_MATCH_WINS -> stringResource(R.string.ranking_metric_sport_wins)
    RankingMetric.SPORT_WIN_RATE -> stringResource(R.string.ranking_metric_sport_win_rate)
    RankingMetric.SPORT_DURATION -> stringResource(R.string.ranking_metric_sport_duration)
    RankingMetric.LIKES_RECEIVED -> stringResource(R.string.ranking_metric_likes_received)
    RankingMetric.COMMENTS_RECEIVED -> stringResource(R.string.ranking_metric_comments_received)
    RankingMetric.GROUP_SESSIONS -> stringResource(R.string.ranking_metric_group_sessions)
    RankingMetric.ACHIEVEMENTS -> stringResource(R.string.ranking_metric_achievements)
    RankingMetric.CHALLENGE_PODIUMS -> stringResource(R.string.ranking_metric_challenge_podiums)
    RankingMetric.HYROX_BEST_TIME -> stringResource(R.string.ranking_metric_hyrox_best_time)
    RankingMetric.FOOTBALL_GOALS -> stringResource(R.string.ranking_metric_football_goals)
    RankingMetric.SKI_DISTANCE_KPI -> stringResource(R.string.ranking_metric_ski_km)
    RankingMetric.SEGMENT_POPULARITY -> stringResource(R.string.ranking_metric_segment_popularity)
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
    val challengesVm: WeeklyChallengesViewModel = viewModel(
        key = "weekly-challenges-$vmKey",
        factory = WeeklyChallengesViewModelFactory(supabase)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val chUi by challengesVm.state.collectAsStateWithLifecycle()
    var selectedWorkout by rememberSaveable { mutableStateOf<Long?>(null) }
    var selectedProfile by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedSegmentId by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedChallengeInstanceId by rememberSaveable { mutableStateOf<String?>(null) }
    var challengesHubOpen by rememberSaveable { mutableStateOf(false) }
    var metricSheetOpen by remember { mutableStateOf(false) }
    val metricSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    val openChallengeId = remember(selectedChallengeInstanceId) {
        selectedChallengeInstanceId?.let { runCatching { UUID.fromString(it) }.getOrNull() }
    }
    if (openChallengeId != null) {
        ChallengeWeeklyDetailScreen(
            supabase = supabase,
            instanceId = openChallengeId,
            onBack = { selectedChallengeInstanceId = null },
            modifier = modifier
        )
        return
    }

    if (challengesHubOpen) {
        WeeklyChallengesHubScreen(
            supabase = supabase,
            viewModelKey = vmKey,
            onOpenChallenge = { selectedChallengeInstanceId = it },
            onClose = { challengesHubOpen = false },
            modifier = modifier
        )
        return
    }

    val openSegmentId = remember(selectedSegmentId) {
        selectedSegmentId?.let { runCatching { UUID.fromString(it) }.getOrNull() }
    }
    if (openSegmentId != null) {
        SegmentDetailScreen(
            supabase = supabase,
            segmentId = openSegmentId,
            onBack = { selectedSegmentId = null },
            modifier = modifier
        )
        return
    }

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

    LaunchedEffect(vmKey, supabase) {
        challengesVm.refresh()
    }
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
                    val showScope = ui.metric != RankingMetric.SEGMENT_POPULARITY
                    val showPeriod = when (ui.metric) {
                        RankingMetric.LEVEL,
                        RankingMetric.GOALS_COMPLETED,
                        RankingMetric.DUELS_WON,
                        RankingMetric.TERRITORY_SHARE -> false
                        else -> true
                    }
                    val showKind = when (ui.metric) {
                        RankingMetric.LEVEL,
                        RankingMetric.GOALS_COMPLETED,
                        RankingMetric.DUELS_WON,
                        RankingMetric.CHALLENGE_PODIUMS,
                        RankingMetric.SEGMENT_POPULARITY,
                        RankingMetric.TERRITORY_SHARE -> false
                        else -> true
                    }
                    if (showScope) {
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
                    }
                    OutlinedButton(
                        onClick = { metricSheetOpen = true },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.Center
                            ) {
                                Text(
                                    text = stringResource(R.string.ranking_metric_picker_title),
                                    style = MaterialTheme.typography.labelSmall,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = rankingMetricButtonLabel(ui.metric),
                                    style = MaterialTheme.typography.titleSmall,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            Icon(
                                imageVector = Icons.Filled.UnfoldMore,
                                contentDescription = stringResource(R.string.ranking_metric_picker_hint)
                            )
                        }
                    }
                    if (ui.metric == RankingMetric.TERRITORY_SHARE) {
                        if (ui.territoryCities.size > 1) {
                            var cityMenuExpanded by remember { mutableStateOf(false) }
                            val selectedCity = ui.territoryCities.firstOrNull { it.cityKey == ui.territoryCityKey }
                            ExposedDropdownMenuBox(
                                expanded = cityMenuExpanded,
                                onExpandedChange = { cityMenuExpanded = it },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                TextField(
                                    value = selectedCity?.let(TerritoryCaptureClient::citySummaryLabel) ?: "City",
                                    onValueChange = {},
                                    readOnly = true,
                                    label = { Text("City") },
                                    trailingIcon = {
                                        ExposedDropdownMenuDefaults.TrailingIcon(expanded = cityMenuExpanded)
                                    },
                                    modifier = Modifier
                                        .menuAnchor()
                                        .fillMaxWidth()
                                )
                                ExposedDropdownMenu(
                                    expanded = cityMenuExpanded,
                                    onDismissRequest = { cityMenuExpanded = false }
                                ) {
                                    ui.territoryCities.forEach { city ->
                                        DropdownMenuItem(
                                            text = { Text(TerritoryCaptureClient.citySummaryLabel(city)) },
                                            onClick = {
                                                city.cityKey?.let(vm::setTerritoryCityKey)
                                                cityMenuExpanded = false
                                            }
                                        )
                                    }
                                }
                            }
                        } else {
                            ui.territoryCities.firstOrNull()?.let { city ->
                                Text(
                                    text = TerritoryCaptureClient.citySummaryLabel(city),
                                    style = MaterialTheme.typography.titleSmall
                                )
                            }
                        }
                    }
                    if (showPeriod) {
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
                    }
                    if (showKind) {
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

        if (ui.segmentRows.isNotEmpty()) {
            items(ui.segmentRows, key = { "${it.segmentId}-${it.rank}" }) { row ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { selectedSegmentId = row.segmentId }
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                "#${row.rank}  ${row.name}",
                                style = MaterialTheme.typography.titleSmall
                            )
                            Text(
                                stringResource(
                                    R.string.ranking_segment_efforts_in_period,
                                    row.effortsCount.toString()
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        } else if (ui.workoutRows.isNotEmpty()) {
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
        FloatingActionButton(
            onClick = { challengesHubOpen = true },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = 12.dp, bottom = if (isPremium) 8.dp else 64.dp)
        ) {
            BadgedBox(
                badge = {
                    if (!chUi.loading && chUi.items.isNotEmpty()) {
                        Badge {
                            Text(
                                text = "${chUi.items.size}",
                                style = MaterialTheme.typography.labelSmall
                            )
                        }
                    }
                }
            ) {
                Icon(
                    imageVector = Icons.Filled.Flag,
                    contentDescription = stringResource(R.string.ranking_challenges_fab_a11y)
                )
            }
        }
        PullRefreshIndicator(
            refreshing = ui.isRefreshing,
            state = pull,
            modifier = Modifier.align(Alignment.TopCenter)
        )
        if (metricSheetOpen) {
            ModalBottomSheet(
                onDismissRequest = { metricSheetOpen = false },
                sheetState = metricSheetState
            ) {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 24.dp)
                ) {
                    rankingMetricSheetSections(ui.kind).forEach { section ->
                        item(key = "h-${section.title}") {
                            Text(
                                text = section.title,
                                style = MaterialTheme.typography.titleSmall,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                            )
                        }
                        items(section.metrics, key = { it.name }) { metric ->
                            ListItem(
                                headlineContent = {
                                    Text(
                                        text = rankingMetricButtonLabel(metric),
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                },
                                trailingContent = {
                                    if (ui.metric == metric) {
                                        Icon(
                                            imageVector = Icons.Filled.Check,
                                            contentDescription = null
                                        )
                                    }
                                },
                                modifier = Modifier.clickable {
                                    vm.setMetric(metric)
                                    metricSheetOpen = false
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
