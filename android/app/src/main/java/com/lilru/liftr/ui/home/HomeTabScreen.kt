package com.lilru.liftr.ui.home

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import com.lilru.liftr.prefs.HomeUiPreferences
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.active.ActiveCardioWorkoutScreen
import com.lilru.liftr.ui.active.ActiveSportWorkoutScreen
import com.lilru.liftr.ui.active.ActiveStrengthWorkoutScreen
import com.lilru.liftr.ui.add.AddCardioActivity
import com.lilru.liftr.ui.add.AddSportType
import com.lilru.liftr.ui.chat.MessagesFloatingButton
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

private enum class HomeQuickStartKind {
    STRENGTH,
    CARDIO,
    SPORT
}

private enum class HomeQuickDockEdge {
    LEFT,
    RIGHT,
    TOP,
    BOTTOM
}

private data class HomeQuickActiveWorkout(
    val workoutId: Int,
    val kind: HomeQuickStartKind
)

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
    val quickPrefs = remember(homeContext) {
        homeContext.getSharedPreferences("liftr_home_quick_actions", android.content.Context.MODE_PRIVATE)
    }
    val vm: HomeViewModel = viewModel(factory = HomeViewModelFactory(app, supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var selected by rememberSaveable { mutableStateOf<Int?>(null) }
    var guestDetailGate by remember { mutableStateOf(false) }
    var quickStartSignInGate by remember { mutableStateOf(false) }
    var showQuickActions by remember { mutableStateOf(false) }
    var showQuickCardioPicker by remember { mutableStateOf(false) }
    var showQuickSportPicker by remember { mutableStateOf(false) }
    var quickActionsHintDismissed by rememberSaveable {
        mutableStateOf(quickPrefs.getBoolean("hintDismissed", false))
    }
    var quickActionsEdgeRaw by rememberSaveable {
        mutableStateOf(quickPrefs.getString("edge", HomeQuickDockEdge.RIGHT.name) ?: HomeQuickDockEdge.RIGHT.name)
    }
    var quickActionsPosition by rememberSaveable {
        mutableStateOf(quickPrefs.getFloat("position", 0.64f))
    }
    var quickStartBusyKind by rememberSaveable { mutableStateOf<HomeQuickStartKind?>(null) }
    var quickStartError by remember { mutableStateOf<String?>(null) }
    var quickActiveWorkout by remember { mutableStateOf<HomeQuickActiveWorkout?>(null) }

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

    quickActiveWorkout?.let { active ->
        when (active.kind) {
            HomeQuickStartKind.STRENGTH -> {
                ActiveStrengthWorkoutScreen(
                    supabase = supabase,
                    workoutId = active.workoutId,
                    onClose = {
                        vm.onReturnFromWorkoutDetail(active.workoutId)
                        quickActiveWorkout = null
                    },
                    modifier = modifier
                )
            }
            HomeQuickStartKind.CARDIO -> {
                ActiveCardioWorkoutScreen(
                    supabase = supabase,
                    workoutId = active.workoutId,
                    onClose = {
                        vm.onReturnFromWorkoutDetail(active.workoutId)
                        quickActiveWorkout = null
                    },
                    modifier = modifier
                )
            }
            HomeQuickStartKind.SPORT -> {
                ActiveSportWorkoutScreen(
                    supabase = supabase,
                    workoutId = active.workoutId,
                    onClose = {
                        vm.onReturnFromWorkoutDetail(active.workoutId)
                        quickActiveWorkout = null
                    },
                    modifier = modifier
                )
            }
        }
        return
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
                HomeQuickActionsEdgeMenu(
                    busy = quickStartBusyKind != null,
                    showMenu = showQuickActions,
                    showHint = !quickActionsHintDismissed,
                    edgeRaw = quickActionsEdgeRaw,
                    position = quickActionsPosition,
                    onToggleMenu = {
                        if (quickStartBusyKind == null) {
                            if (me == null) {
                                quickStartSignInGate = true
                            } else {
                                quickActionsHintDismissed = true
                                quickPrefs.edit().putBoolean("hintDismissed", true).apply()
                                showQuickActions = !showQuickActions
                            }
                        }
                    },
                    onDismissMenu = { showQuickActions = false },
                    onDismissHint = {
                        quickActionsHintDismissed = true
                        quickPrefs.edit().putBoolean("hintDismissed", true).apply()
                    },
                    onDockChanged = { edge, pos ->
                        quickActionsEdgeRaw = edge.name
                        quickActionsPosition = pos
                        quickActionsHintDismissed = true
                        quickPrefs.edit()
                            .putString("edge", edge.name)
                            .putFloat("position", pos)
                            .putBoolean("hintDismissed", true)
                            .apply()
                    },
                    onStrength = {
                        showQuickActions = false
                        startHomeQuickWorkout(
                            scope = scope,
                            supabase = supabase,
                            userId = me,
                            kind = HomeQuickStartKind.STRENGTH,
                            setBusy = { quickStartBusyKind = it },
                            setError = { quickStartError = it },
                            setActive = { quickActiveWorkout = it }
                        )
                    },
                    onCardio = {
                        showQuickActions = false
                        showQuickCardioPicker = true
                    },
                    onSport = {
                        showQuickActions = false
                        showQuickSportPicker = true
                    },
                    modifier = Modifier.fillMaxSize()
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
                if (quickStartSignInGate) {
                    AlertDialog(
                        onDismissRequest = { quickStartSignInGate = false },
                        title = { Text(stringResource(R.string.home_guest_detail_title)) },
                        text = { Text(stringResource(R.string.home_quick_actions_sign_in_message)) },
                        confirmButton = {
                            TextButton(
                                onClick = {
                                    quickStartSignInGate = false
                                    onGoToProfileTab()
                                }
                            ) {
                                Text(stringResource(R.string.home_guest_detail_go_profile))
                            }
                        },
                        dismissButton = {
                            TextButton(onClick = { quickStartSignInGate = false }) {
                                Text(stringResource(R.string.home_guest_detail_cancel))
                            }
                        }
                    )
                }
                quickStartError?.let { message ->
                    AlertDialog(
                        onDismissRequest = { quickStartError = null },
                        title = { Text(stringResource(R.string.home_quick_actions_error_title)) },
                        text = { Text(message) },
                        confirmButton = {
                            TextButton(onClick = { quickStartError = null }) {
                                Text(stringResource(R.string.auth_ok))
                            }
                        }
                    )
                }
                if (showQuickCardioPicker) {
                    HomeQuickCardioPickerSheet(
                        onDismiss = { showQuickCardioPicker = false },
                        onPick = { activity ->
                            showQuickCardioPicker = false
                            startHomeQuickWorkout(
                                scope = scope,
                                supabase = supabase,
                                userId = me,
                                kind = HomeQuickStartKind.CARDIO,
                                cardioActivity = activity,
                                setBusy = { quickStartBusyKind = it },
                                setError = { quickStartError = it },
                                setActive = { quickActiveWorkout = it }
                            )
                        }
                    )
                }
                if (showQuickSportPicker) {
                    HomeQuickSportPickerSheet(
                        onDismiss = { showQuickSportPicker = false },
                        onPick = { sport ->
                            showQuickSportPicker = false
                            startHomeQuickWorkout(
                                scope = scope,
                                supabase = supabase,
                                userId = me,
                                kind = HomeQuickStartKind.SPORT,
                                sportType = sport,
                                setBusy = { quickStartBusyKind = it },
                                setError = { quickStartError = it },
                                setActive = { quickActiveWorkout = it }
                            )
                        }
                    )
                }
                if (me != null) {
                    MessagesFloatingButton(supabase = supabase)
                }
                if (quickStartBusyKind != null) {
                    HomeQuickStartLoadingOverlay()
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

@Composable
private fun HomeQuickStartLoadingOverlay() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.34f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = {}
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 28.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.82f))
                .border(0.8.dp, Color.White.copy(alpha = 0.22f), RoundedCornerShape(24.dp))
                .padding(horizontal = 22.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            CircularProgressIndicator(Modifier.size(36.dp))
            Text(
                text = stringResource(R.string.home_quick_actions_loading_title),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = stringResource(R.string.home_quick_actions_loading_message),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun HomeQuickActionsEdgeMenu(
    busy: Boolean,
    showMenu: Boolean,
    showHint: Boolean,
    edgeRaw: String,
    position: Float,
    onToggleMenu: () -> Unit,
    onDismissMenu: () -> Unit,
    onDismissHint: () -> Unit,
    onDockChanged: (HomeQuickDockEdge, Float) -> Unit,
    onStrength: () -> Unit,
    onCardio: () -> Unit,
    onSport: () -> Unit,
    modifier: Modifier = Modifier
) {
    BoxWithConstraints(modifier = modifier) {
        val density = LocalDensity.current
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        val tabSizePx = with(density) { 52.dp.toPx() }
        val edge = runCatching { HomeQuickDockEdge.valueOf(edgeRaw) }.getOrDefault(HomeQuickDockEdge.RIGHT)
        val anchor = homeQuickAnchor(edge, position, widthPx, heightPx, tabSizePx)

        if (showMenu) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(onClick = onDismissMenu)
            )
            HomeQuickActionsMenu(
                onStrength = onStrength,
                onCardio = onCardio,
                onSport = onSport,
                modifier = Modifier.offset {
                    homeQuickMenuOffset(anchor, edge, widthPx, heightPx, density)
                }
            )
        }

        if (showHint && !showMenu && !busy) {
            HomeQuickActionsTooltip(
                onDismiss = onDismissHint,
                modifier = Modifier.offset {
                    homeQuickTooltipOffset(anchor, edge, widthPx, heightPx, density)
                }
            )
        }

        FloatingActionButton(
            onClick = onToggleMenu,
            modifier = Modifier
                .offset {
                    IntOffset(
                        (anchor.x - tabSizePx / 2f).roundToInt(),
                        (anchor.y - tabSizePx / 2f).roundToInt()
                    )
                }
                .size(52.dp)
                .pointerInput(widthPx, heightPx, edgeRaw, position) {
                    var dragAnchor = anchor
                    detectDragGestures(
                        onDragStart = {
                            dragAnchor = anchor
                            onDismissMenu()
                        },
                        onDragEnd = {},
                        onDrag = { _, dragAmount ->
                            dragAnchor += dragAmount
                            val dock = homeQuickDock(dragAnchor, widthPx, heightPx, tabSizePx)
                            onDockChanged(dock.first, dock.second)
                        }
                    )
                }
        ) {
            if (busy) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp
                )
            } else {
                Text("⚡", style = MaterialTheme.typography.titleLarge)
            }
        }
    }
}

@Composable
private fun HomeQuickActionsMenu(
    onStrength: () -> Unit,
    onCardio: () -> Unit,
    onSport: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .width(158.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f))
            .border(0.8.dp, Color.White.copy(alpha = 0.22f), RoundedCornerShape(24.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = stringResource(R.string.home_quick_actions_title),
            style = MaterialTheme.typography.labelLarge
        )
        HomeQuickActionsMenuButton(
            text = stringResource(R.string.home_filter_strength),
            onClick = onStrength
        )
        HomeQuickActionsMenuButton(
            text = stringResource(R.string.home_filter_cardio),
            onClick = onCardio
        )
        HomeQuickActionsMenuButton(
            text = stringResource(R.string.home_filter_sport),
            onClick = onSport
        )
    }
}

@Composable
private fun HomeQuickActionsMenuButton(
    text: String,
    onClick: () -> Unit
) {
    TextButton(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.58f))
    ) {
        Text(text, color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun HomeQuickActionsTooltip(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.78f))
            .border(0.8.dp, Color.White.copy(alpha = 0.22f), CircleShape)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = stringResource(R.string.home_quick_actions_tooltip),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurface
        )
        TextButton(onClick = onDismiss) {
            Text(stringResource(R.string.home_quick_actions_tooltip_dismiss))
        }
    }
}

private fun homeQuickAnchor(
    edge: HomeQuickDockEdge,
    position: Float,
    widthPx: Float,
    heightPx: Float,
    tabSizePx: Float
): Offset {
    val minX = tabSizePx / 2f
    val maxX = (widthPx - tabSizePx / 2f).coerceAtLeast(minX)
    val minY = tabSizePx / 2f + 10f
    val maxY = (heightPx - tabSizePx / 2f - 72f).coerceAtLeast(minY)
    val p = position.coerceIn(0f, 1f)

    return when (edge) {
        HomeQuickDockEdge.LEFT -> Offset(minX, minY + (maxY - minY) * p)
        HomeQuickDockEdge.RIGHT -> Offset(maxX, minY + (maxY - minY) * p)
        HomeQuickDockEdge.TOP -> Offset(minX + (maxX - minX) * p, minY)
        HomeQuickDockEdge.BOTTOM -> Offset(minX + (maxX - minX) * p, maxY)
    }
}

private fun homeQuickDock(
    point: Offset,
    widthPx: Float,
    heightPx: Float,
    tabSizePx: Float
): Pair<HomeQuickDockEdge, Float> {
    val minX = tabSizePx / 2f
    val maxX = (widthPx - tabSizePx / 2f).coerceAtLeast(minX)
    val minY = tabSizePx / 2f + 10f
    val maxY = (heightPx - tabSizePx / 2f - 72f).coerceAtLeast(minY)
    val edge = listOf(
        HomeQuickDockEdge.LEFT to abs(point.x - minX),
        HomeQuickDockEdge.RIGHT to abs(point.x - maxX),
        HomeQuickDockEdge.TOP to abs(point.y - minY),
        HomeQuickDockEdge.BOTTOM to abs(point.y - maxY)
    ).minBy { it.second }.first

    val pos = when (edge) {
        HomeQuickDockEdge.LEFT, HomeQuickDockEdge.RIGHT ->
            ((point.y - minY) / (maxY - minY).coerceAtLeast(1f)).coerceIn(0f, 1f)
        HomeQuickDockEdge.TOP, HomeQuickDockEdge.BOTTOM ->
            ((point.x - minX) / (maxX - minX).coerceAtLeast(1f)).coerceIn(0f, 1f)
    }

    return edge to pos
}

private fun homeQuickMenuOffset(
    anchor: Offset,
    edge: HomeQuickDockEdge,
    widthPx: Float,
    heightPx: Float,
    density: androidx.compose.ui.unit.Density
): IntOffset {
    val menuWidth = with(density) { 158.dp.toPx() }
    val menuHeight = with(density) { 188.dp.toPx() }
    val spacing = with(density) { 92.dp.toPx() }
    val raw = when (edge) {
        HomeQuickDockEdge.LEFT -> Offset(anchor.x + spacing, anchor.y)
        HomeQuickDockEdge.RIGHT -> Offset(anchor.x - spacing, anchor.y)
        HomeQuickDockEdge.TOP -> Offset(anchor.x, anchor.y + spacing)
        HomeQuickDockEdge.BOTTOM -> Offset(anchor.x, anchor.y - spacing)
    }

    return IntOffset(
        (raw.x - menuWidth / 2f).coerceIn(12f, widthPx - menuWidth - 12f).roundToInt(),
        (raw.y - menuHeight / 2f).coerceIn(12f, heightPx - menuHeight - 12f).roundToInt()
    )
}

private fun homeQuickTooltipOffset(
    anchor: Offset,
    edge: HomeQuickDockEdge,
    widthPx: Float,
    heightPx: Float,
    density: androidx.compose.ui.unit.Density
): IntOffset {
    val tooltipWidth = with(density) { 228.dp.toPx() }
    val tooltipHeight = with(density) { 48.dp.toPx() }
    val spacing = with(density) { 142.dp.toPx() }
    val verticalSpacing = with(density) { 58.dp.toPx() }
    val raw = when (edge) {
        HomeQuickDockEdge.LEFT -> Offset(anchor.x + spacing, anchor.y)
        HomeQuickDockEdge.RIGHT -> Offset(anchor.x - spacing, anchor.y)
        HomeQuickDockEdge.TOP -> Offset(anchor.x, anchor.y + verticalSpacing)
        HomeQuickDockEdge.BOTTOM -> Offset(anchor.x, anchor.y - verticalSpacing)
    }

    return IntOffset(
        (raw.x - tooltipWidth / 2f).coerceIn(12f, widthPx - tooltipWidth - 12f).roundToInt(),
        (raw.y - tooltipHeight / 2f).coerceIn(12f, heightPx - tooltipHeight - 12f).roundToInt()
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeQuickCardioPickerSheet(
    onDismiss: () -> Unit,
    onPick: (AddCardioActivity) -> Unit
) {
    val context = LocalContext.current
    val theme = remember(context) { LiftrPreferences.backgroundTheme(context) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color.Transparent
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .liftrAppBackgroundGradient(theme)
                .padding(bottom = 24.dp)
        ) {
            Text(
                text = stringResource(R.string.home_quick_actions_choose_cardio),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)
            )
            LazyColumn {
                items(AddCardioActivity.values()) { activity ->
                    TextButton(
                        onClick = { onPick(activity) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 2.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.46f))
                    ) {
                        Text(homeQuickLabel(activity.wire), color = MaterialTheme.colorScheme.onSurface)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeQuickSportPickerSheet(
    onDismiss: () -> Unit,
    onPick: (AddSportType) -> Unit
) {
    val context = LocalContext.current
    val theme = remember(context) { LiftrPreferences.backgroundTheme(context) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color.Transparent
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .liftrAppBackgroundGradient(theme)
                .padding(bottom = 24.dp)
        ) {
            Text(
                text = stringResource(R.string.home_quick_actions_choose_sport),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)
            )
            LazyColumn {
                items(AddSportType.values()) { sport ->
                    TextButton(
                        onClick = { onPick(sport) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 2.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.46f))
                    ) {
                        Text(homeQuickLabel(sport.wire), color = MaterialTheme.colorScheme.onSurface)
                    }
                }
            }
        }
    }
}

private fun startHomeQuickWorkout(
    scope: CoroutineScope,
    supabase: SupabaseClient,
    userId: String?,
    kind: HomeQuickStartKind,
    cardioActivity: AddCardioActivity? = null,
    sportType: AddSportType? = null,
    setBusy: (HomeQuickStartKind?) -> Unit,
    setError: (String?) -> Unit,
    setActive: (HomeQuickActiveWorkout) -> Unit
) {
    val uid = userId ?: return
    setBusy(kind)
    setError(null)
    scope.launch {
        runCatching {
            createHomeQuickStartWorkout(
                supabase = supabase,
                kind = kind,
                userId = uid,
                cardioActivity = cardioActivity,
                sportType = sportType
            )
        }.onSuccess { workoutId ->
            setBusy(null)
            setActive(HomeQuickActiveWorkout(workoutId = workoutId, kind = kind))
        }.onFailure { e ->
            setBusy(null)
            setError(e.message?.take(240) ?: e::class.java.simpleName)
        }
    }
}

private fun homeQuickLabel(raw: String): String =
    raw.split("_").joinToString(" ") { part ->
        part.replaceFirstChar { c -> c.titlecase(Locale.getDefault()) }
    }

private suspend fun createHomeQuickStartWorkout(
    supabase: SupabaseClient,
    kind: HomeQuickStartKind,
    userId: String,
    cardioActivity: AddCardioActivity? = null,
    sportType: AddSportType? = null
): Int {
    val startedAt = Instant.now().toString()
    return when (kind) {
        HomeQuickStartKind.STRENGTH -> createHomeQuickStrength(supabase, userId, startedAt)
        HomeQuickStartKind.CARDIO -> createHomeQuickCardio(
            supabase,
            userId,
            startedAt,
            cardioActivity ?: AddCardioActivity.RUN
        )
        HomeQuickStartKind.SPORT -> createHomeQuickSport(
            supabase,
            userId,
            startedAt,
            sportType ?: AddSportType.PADEL
        )
    }
}

private suspend fun createHomeQuickStrength(
    supabase: SupabaseClient,
    userId: String,
    startedAt: String
): Int {
    val params = buildJsonObject {
        put("p_user_id", userId)
        put("p_items", buildJsonArray { })
        put("p_started_at", startedAt)
        put("p_perceived_intensity", "moderate")
        put("p_state", "planned")
    }
    val res = supabase.postgrest.rpc(BackendContracts.Rpc.CREATE_STRENGTH_WORKOUT, params) { }
    return parseHomeQuickWorkoutId(res.data)
        ?: fetchHomeQuickLastWorkoutId(supabase, userId, "strength")
}

private suspend fun createHomeQuickCardio(
    supabase: SupabaseClient,
    userId: String,
    startedAt: String,
    activity: AddCardioActivity
): Int {
    val p = buildJsonObject {
        put("p_user_id", userId)
        put("p_activity_code", activity.wire)
        put("p_started_at", startedAt)
        put("p_perceived_intensity", "moderate")
        put("p_state", "planned")
        put("p_stats", buildJsonObject { })
    }
    val wrapper = buildJsonObject { put("p", p) }
    val res = supabase.postgrest.rpc(BackendContracts.Rpc.CREATE_CARDIO_WORKOUT_V2, wrapper) { }
    return parseHomeQuickWorkoutId(res.data)
        ?: fetchHomeQuickLastWorkoutId(supabase, userId, "cardio")
}

private suspend fun createHomeQuickSport(
    supabase: SupabaseClient,
    userId: String,
    startedAt: String,
    sport: AddSportType
): Int {
    val p = buildJsonObject {
        put("p_user_id", userId)
        put("p_sport", sport.wire)
        put("p_started_at", startedAt)
        put("p_match_result", "unfinished")
        put("p_perceived_intensity", "moderate")
        put("p_state", "planned")
    }
    val wrapper = buildJsonObject {
        put("p", p)
        put("p_stats", buildJsonObject { })
    }
    val res = supabase.postgrest.rpc(BackendContracts.Rpc.CREATE_SPORT_WORKOUT_V2, wrapper) { }
    return parseHomeQuickWorkoutId(res.data)
        ?: fetchHomeQuickLastWorkoutId(supabase, userId, "sport")
}

private fun parseHomeQuickWorkoutId(raw: String): Int? {
    val trimmed = raw.trim()
    trimmed.toIntOrNull()?.let { return it }
    return runCatching {
        val root = Json.parseToJsonElement(trimmed)
        when {
            root is kotlinx.serialization.json.JsonPrimitive -> root.intOrNull
            root is kotlinx.serialization.json.JsonArray -> root.firstOrNull()?.jsonPrimitive?.intOrNull
            root is kotlinx.serialization.json.JsonObject -> root["id"]?.jsonPrimitive?.intOrNull
            else -> null
        }
    }.getOrNull()
}

private suspend fun fetchHomeQuickLastWorkoutId(
    supabase: SupabaseClient,
    userId: String,
    kind: String
): Int {
    val res = supabase.from(BackendContracts.Tables.WORKOUTS)
        .select(columns = Columns.raw("id")) {
            filter {
                eq("user_id", userId)
                eq("kind", kind)
            }
            order("id", Order.DESCENDING)
            limit(1)
        }
    return Json.parseToJsonElement(res.data)
        .jsonArray
        .firstOrNull()
        ?.jsonObject
        ?.get("id")
        ?.jsonPrimitive
        ?.intOrNull
        ?: error("Could not find the created workout.")
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

