package com.lilru.liftr.ui.home

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.lilru.liftr.BuildConfig
import com.lilru.liftr.R
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import com.lilru.liftr.prefs.HomeUiPreferences
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun HomeTabScreen(
    supabase: SupabaseClient,
    onOpenAddWithPendingDuplicate: () -> Unit = {},
    homeRefreshNonce: Int = 0,
    homeFeedSyncNonce: Int = 0,
    homeFeedSyncWorkoutId: Int = 0,
    onGoToProfileTab: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val homeContext = LocalContext.current
    val app = homeContext.applicationContext as Application
    val vm: HomeViewModel = viewModel(factory = HomeViewModelFactory(app, supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var selected by rememberSaveable { mutableStateOf<Int?>(null) }
    var guestDetailGate by remember { mutableStateOf(false) }

    LaunchedEffect(homeRefreshNonce) {
        if (homeRefreshNonce > 0) {
            vm.refresh()
        }
    }

    LaunchedEffect(homeFeedSyncNonce) {
        if (homeFeedSyncNonce > 0) {
            vm.onReturnFromWorkoutDetail(homeFeedSyncWorkoutId)
        }
    }

    val selectedWorkout = ui.workouts.firstOrNull { it.id == selected }
    if (selectedWorkout != null) {
        val backId = selectedWorkout.id
        WorkoutDetailScreen(
            supabase = supabase,
            workoutId = selectedWorkout.id,
            onBack = {
                vm.onReturnFromWorkoutDetail(backId)
                selected = null
            },
            onDuplicateToAdd = {
                onOpenAddWithPendingDuplicate()
                selected = null
            },
            modifier = modifier
        )
        return
    }

    val me = supabase.auth.currentUserOrNull()?.id
    LaunchedEffect(me) {
        guestDetailGate = false
    }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val pull = rememberPullRefreshState(
        refreshing = ui.isRefreshing,
        onRefresh = { vm.refresh() }
    )
    val loadMore by remember {
        derivedStateOf {
            val l = listState.layoutInfo
            if (l.visibleItemsInfo.isEmpty() || !ui.canLoadMore || ui.isLoadingMore) {
                false
            } else {
                l.visibleItemsInfo.last().index >= l.totalItemsCount - 2
            }
        }
    }
    LaunchedEffect(loadMore) {
        if (loadMore) vm.loadMore()
    }
    val showScrollTop by remember {
        derivedStateOf {
            listState.firstVisibleItemIndex > 0 ||
                listState.firstVisibleItemScrollOffset > 120
        }
    }
    val collapse by HomeUiPreferences.collapseFlow(homeContext).collectAsStateWithLifecycle(
        initialValue = HomeUiPreferences.HomeCollapseState()
    )
    val hasDataModule = ui.todayCount > 0 ||
        ui.weekWorkouts > 0 ||
        ui.strongestWeekPtsMtd > 0 ||
        ui.bestSportScore > 0
    when {
        ui.error != null -> {
            Box(
                modifier = modifier
                    .fillMaxSize()
                    .pullRefresh(pull)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = ui.error ?: "",
                        color = MaterialTheme.colorScheme.error,
                        textAlign = TextAlign.Center
                    )
                    Button(onClick = { vm.refresh() }, modifier = Modifier.padding(top = 12.dp)) {
                        Text(stringResource(R.string.home_retry))
                    }
                }
                PullRefreshIndicator(
                    refreshing = ui.isRefreshing,
                    state = pull,
                    modifier = Modifier.align(Alignment.TopCenter)
                )
            }
        }
        ui.loading && !ui.isRefreshing -> {
            Column(
                modifier = modifier
                    .fillMaxSize()
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(stringResource(R.string.home_loading))
            }
        }
        else -> {
            Box(modifier.fillMaxSize()) {
                HomeContentColumn(
                    modifier = Modifier.fillMaxSize(),
                    listState = listState,
                    pull = pull,
                    showScrollTop = showScrollTop,
                    onScrollTop = {
                        scope.launch {
                            listState.scrollToItem(0)
                        }
                    },
                    vm = vm,
                    ui = ui,
                    homeContext = homeContext,
                    collapse = collapse,
                    hasDataModule = hasDataModule,
                    onSelectWorkout = { id ->
                        if (me == null) {
                            guestDetailGate = true
                        } else {
                            selected = id
                        }
                    },
                    me = me,
                    onOpenGoals = {
                        me?.let { u -> AppNavEvents.send(MainOverlay.Goals(u)) }
                    },
                    onOpenCompetitions = { AppNavEvents.send(MainOverlay.CompetitionsHub) },
                    onSetCollapse = { c ->
                        scope.launch {
                            HomeUiPreferences.setAllCollapsed(homeContext, c)
                        }
                    }
                )
                if (guestDetailGate) {
                    AlertDialog(
                        onDismissRequest = { guestDetailGate = false },
                        title = { Text(stringResource(R.string.home_guest_detail_title)) },
                        text = { Text(stringResource(R.string.home_guest_detail_message)) },
                        confirmButton = {
                            TextButton(
                                onClick = {
                                    guestDetailGate = false
                                    onGoToProfileTab()
                                }
                            ) {
                                Text(stringResource(R.string.home_guest_detail_go_profile))
                            }
                        },
                        dismissButton = {
                            TextButton(onClick = { guestDetailGate = false }) {
                                Text(stringResource(R.string.home_guest_detail_cancel))
                            }
                        }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterialApi::class)
@Composable
private fun HomeContentColumn(
    modifier: Modifier,
    listState: LazyListState,
    pull: androidx.compose.material.pullrefresh.PullRefreshState,
    showScrollTop: Boolean,
    onScrollTop: () -> Unit,
    vm: HomeViewModel,
    ui: HomeUiState,
    homeContext: android.content.Context,
    collapse: HomeUiPreferences.HomeCollapseState,
    hasDataModule: Boolean,
    onSelectWorkout: (Int) -> Unit,
    me: String?,
    onOpenGoals: () -> Unit,
    onOpenCompetitions: () -> Unit,
    onSetCollapse: (Boolean) -> Unit
) {
    val todayFeedLabel = stringResource(R.string.home_feed_today)
    val yesterdayFeedLabel = stringResource(R.string.home_feed_yesterday)
    val zone = remember { ZoneId.systemDefault() }
    val homeScope = rememberCoroutineScope()
    Column(
        modifier = modifier.fillMaxSize()
    ) {
        Box(
            Modifier
                .weight(1f)
                .fillMaxSize()
    ) {
        Box(Modifier
            .fillMaxSize()
            .pullRefresh(pull)
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                item {
                    val kindSegments = listOf(
                        HomeKindFilter.ALL,
                        HomeKindFilter.STRENGTH,
                        HomeKindFilter.CARDIO,
                        HomeKindFilter.SPORT
                    )
                    val kindLabels = listOf(
                        R.string.home_filter_all,
                        R.string.home_filter_strength,
                        R.string.home_filter_cardio,
                        R.string.home_filter_sport
                    )
                    SingleChoiceSegmentedButtonRow(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 6.dp)
                    ) {
                        kindSegments.forEachIndexed { i, f ->
                            SegmentedButton(
                                selected = ui.kindFilter == f,
                                onClick = { vm.setKindFilter(f) },
                                shape = SegmentedButtonDefaults.itemShape(
                                    index = i,
                                    count = kindSegments.size
                                )
                            ) {
                                Text(stringResource(kindLabels[i]))
                            }
                        }
                    }
                }
                if (hasDataModule) {
                    if (collapse.collapseModules) {
                        item {
                            Card(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable { onSetCollapse(false) }
                            ) {
                                Row(
                                    Modifier.padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                                    ) {
                                        Text("📊", style = MaterialTheme.typography.bodyLarge)
                                        Text(
                                            stringResource(R.string.home_data_title),
                                            style = MaterialTheme.typography.labelLarge
                                        )
                                    }
                                    Text(
                                        "▾",
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    } else {
                        item {
                            Card(Modifier.fillMaxWidth()) {
                                Row(
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(8.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        stringResource(R.string.home_data_title),
                                        style = MaterialTheme.typography.titleSmall
                                    )
                                    Text(
                                        "▲",
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier
                                            .clickable { onSetCollapse(true) }
                                            .padding(4.dp)
                                    )
                                }
                            }
                        }
                        if (ui.todayCount > 0) {
                            item {
                                HomeTodayCard(
                                    ui.todayCount,
                                    ui.todayMinutes,
                                    ui.todayPoints,
                                    ui.todayKcal
                                )
                            }
                        }
                        if (ui.weekWorkouts > 0) {
                            item {
                                HomeStreakCard(
                                    ui.streakDays,
                                    ui.weekWorkouts,
                                    ui.weekPoints,
                                    ui.weekKcal
                                )
                            }
                        }
                        if (ui.strongestWeekPtsMtd > 0 || ui.bestSportScore > 0) {
                            item {
                                HomeInsightsRow(
                                    bestWeekPts = ui.strongestWeekPtsMtd,
                                    bestWeekKcal = ui.strongestWeekKcalMtd,
                                    bestSportLabel = ui.bestSportLabel,
                                    bestSportScore = ui.bestSportScore
                                )
                            }
                        }
                    }
                }
                if (!collapse.collapseModules) {
                    ui.monthSummary?.let { ms ->
                        if (ms.workoutCount > 0) {
                            if (collapse.collapseMonthly) {
                                item {
                                    TextButton(
                                        onClick = {
                                            homeScope.launch {
                                                HomeUiPreferences.setCollapseMonthly(homeContext, false)
                                            }
                                        },
                                        modifier = Modifier.padding(horizontal = 4.dp)
                                    ) {
                                        Text(stringResource(R.string.home_expand_monthly))
                                    }
                                }
                            } else {
                                item {
                                    HomeMonthlySummaryCard(
                                        month = ms,
                                        onHide = {
                                            homeScope.launch {
                                                HomeUiPreferences.setCollapseMonthly(
                                                    homeContext,
                                                    true
                                                )
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                if (me != null) {
                    item {
                        HomeGoalsCompetitionsRow(
                            compact = collapse.collapseModules,
                            onGoals = onOpenGoals,
                            onCompetitions = onOpenCompetitions
                        )
                    }
                }
                if (ui.workouts.isEmpty()) {
                    item {
                        val emptyMsg = when {
                            ui.isGuestHomeFeed -> stringResource(R.string.home_empty_guest)
                            me != null && !ui.hasFollowees -> stringResource(R.string.home_empty_no_follows)
                            me != null && ui.hasFollowees -> stringResource(R.string.home_empty_follows_quiet)
                            else -> stringResource(R.string.home_empty)
                        }
                        Text(
                            emptyMsg,
                            textAlign = TextAlign.Center,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(24.dp)
                        )
                    }
                }
                val highlightsAt = 5
                itemsIndexed(
                    ui.workouts,
                    key = { _, w -> w.id }
                ) { i, w ->
                    val prev = ui.workouts.getOrNull(i - 1)
                    val firstOfDay = i == 0 || !homeFeedSameDay(prev?.startedAt, w.startedAt, zone)
                    val dayGroupLabel = if (firstOfDay) {
                        homeFeedDateLabelCompact(
                            w.startedAt,
                            zone,
                            todayFeedLabel,
                            yesterdayFeedLabel
                        )
                    } else {
                        null
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        HomeWorkoutFeedCard(
                            workout = w,
                            meUserId = me,
                            dayGroupLabel = dayGroupLabel,
                            onClick = { onSelectWorkout(w.id) }
                        )
                        if (i == highlightsAt &&
                            (ui.recentPrs.isNotEmpty() || ui.weeklyTop.isNotEmpty())
                        ) {
                            HomeHighlightsCard(
                                prs = ui.recentPrs,
                                weeklyTop = ui.weeklyTop
                            )
                        }
                    }
                }
                if (ui.isLoadingMore) {
                    item {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator(Modifier.size(32.dp))
                        }
                    }
                }
            }
            PullRefreshIndicator(
                refreshing = ui.isRefreshing,
                state = pull,
                modifier = Modifier.align(Alignment.TopCenter)
            )
        }
        if (showScrollTop) {
            FloatingActionButton(
                onClick = onScrollTop,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp)
                    .size(48.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.KeyboardArrowUp,
                    contentDescription = stringResource(R.string.home_scroll_to_top)
                )
            }
        }
    }
    if (!ui.isPremium) {
        AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp)
                .padding(horizontal = 12.dp, vertical = 4.dp),
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
}

/** Paridad con [Liftr.HomeView.sameDay] para cabeceras de feed. */
private fun homeFeedSameDay(a: String?, b: String?, zone: ZoneId): Boolean {
    val da = homeFeedLocalDateFromStartedAt(a, zone) ?: return false
    val db = homeFeedLocalDateFromStartedAt(b, zone) ?: return false
    return da == db
}

private fun homeFeedLocalDateFromStartedAt(iso: String?, zone: ZoneId): java.time.LocalDate? {
    if (iso.isNullOrBlank()) return null
    return runCatching { Instant.parse(iso).atZone(zone).toLocalDate() }.getOrNull()
}

/** [Liftr.HomeView.dateLabelCompact] */
private fun homeFeedDateLabelCompact(
    startedAt: String?,
    zone: ZoneId,
    today: String,
    yesterday: String
): String {
    val d = homeFeedLocalDateFromStartedAt(startedAt, zone)
    if (d == null) return "—"
    val now = java.time.LocalDate.now(zone)
    return when {
        d == now -> today
        d == now.minusDays(1) -> yesterday
        d.year == now.year -> d.format(
            DateTimeFormatter.ofPattern("d MMM", Locale.getDefault())
        )
        else -> d.format(
            DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.getDefault())
        )
    }
}

