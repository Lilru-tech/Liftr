package com.lilru.liftr.ui.main

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBarDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.compose.ui.zIndex
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.UpdateAvailability
import com.lilru.liftr.R
import com.lilru.liftr.update.PlayStoreUpdatePrompt
import com.lilru.liftr.auth.AuthViewModel
import com.lilru.liftr.auth.PostLoginShellMessage
import com.lilru.liftr.ui.auth.ProfileAuthNavHost
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import com.lilru.liftr.data.loadProfileAvatarUrl
import com.lilru.liftr.ui.AppBannerEvent
import com.lilru.liftr.ui.AppSnackbar
import com.lilru.liftr.ui.notifications.NotificationUnreadSync
import com.lilru.liftr.ui.notifications.UnreadNotificationCounter
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import com.lilru.liftr.ui.achievements.AchievementsScreen
import com.lilru.liftr.ui.add.AddWorkoutTabScreen
import com.lilru.liftr.ui.competition.CompetitionDetailFromIdScreen
import com.lilru.liftr.ui.competition.CompetitionReviewsScreen
import com.lilru.liftr.ui.competition.CompetitionsHubScreen
import com.lilru.liftr.ui.goals.GoalsScreen
import com.lilru.liftr.ui.home.HomeFeedSync
import com.lilru.liftr.ui.home.HomeTabScreen
import com.lilru.liftr.ui.home.WorkoutDetailFromNotificationOverlay
import com.lilru.liftr.ui.home.WorkoutDetailScreen
import com.lilru.liftr.ui.profile.ProfileTabScreen
import com.lilru.liftr.ui.ranking.ChallengeWeeklyDetailScreen
import com.lilru.liftr.ui.ranking.RankingTabScreen
import com.lilru.liftr.ui.search.SearchTabScreen
import com.lilru.liftr.ui.segment.SegmentDetailScreen
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth

private enum class MainTab(
    val titleRes: Int,
    val shortRes: Int
) {
    Home(R.string.tab_home, R.string.tab_home_short),
    Search(R.string.tab_search, R.string.tab_search_short),
    Add(R.string.tab_add, R.string.tab_add_short),
    Ranking(R.string.tab_ranking, R.string.tab_ranking_short),
    Profile(R.string.tab_profile, R.string.tab_profile_short)
}

/**
 * Solo ajusta la pestaña para overlays que "pertenecen" a un tab.
 * **No** cambies la pestaña para modales reutilizables (goals, competición, entreno) desde
 * la Home: si fijas Profile al abrir Goals, el perfil se compone bajo un overlay
 * (y título "Profile") y el feed puede verse por transparencia en zonas vacías. Ver [RootView] en iOS.
 */
private fun selectTabForRootOverlay(overlay: MainOverlay): MainTab? = when (overlay) {
    is MainOverlay.FollowerProfile -> MainTab.Search
    is MainOverlay.SegmentDetail -> MainTab.Search
    is MainOverlay.ChallengeWeeklyDetail -> MainTab.Ranking
    else -> null
}

@Composable
private fun MainTabIcon(
    tab: MainTab,
    myAvatarUrl: String?,
    contentDescription: String,
    iconTint: Color? = null
) {
    val iconMod = Modifier.size(22.dp)
    val vectorTint = iconTint ?: Color.Unspecified
    when (tab) {
        MainTab.Home -> Icon(Icons.Filled.Home, contentDescription = contentDescription, modifier = iconMod, tint = vectorTint)
        MainTab.Search -> Icon(Icons.Filled.Search, contentDescription = contentDescription, modifier = iconMod, tint = vectorTint)
        MainTab.Add -> Icon(Icons.Filled.Add, contentDescription = contentDescription, modifier = iconMod, tint = vectorTint)
        MainTab.Ranking -> Icon(Icons.Filled.EmojiEvents, contentDescription = contentDescription, modifier = iconMod, tint = vectorTint)
        MainTab.Profile -> {
            val u = myAvatarUrl?.trim()?.takeIf { it.isNotEmpty() }
            if (u == null) {
                Icon(Icons.Filled.Person, contentDescription = contentDescription, modifier = iconMod, tint = vectorTint)
            } else {
                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .clip(CircleShape)
                ) {
                    AsyncImage(
                        model = u,
                        contentDescription = contentDescription,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
        }
    }
}

/** Barra de tabs compacta: mismos insets que Material [NavigationBar], altura fija (no ~80dp). */
@Composable
private fun LiftrMainBottomBar(
    selected: MainTab,
    onSelect: (MainTab) -> Unit,
    isAuthenticated: Boolean,
    tabUnread: Int,
    myAvatarUrl: String?
) {
    val container = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f)
    val pill = MaterialTheme.colorScheme.secondaryContainer
    val onSelected = MaterialTheme.colorScheme.onSecondaryContainer
    val onIdle = MaterialTheme.colorScheme.onSurfaceVariant
    Surface(
        color = container,
        contentColor = onIdle,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(NavigationBarDefaults.windowInsets)
                .height(58.dp)
                .selectableGroup(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            for (tab in MainTab.entries) {
                val desc = stringResource(tab.titleRes)
                val isSelected = selected == tab
                val iconTint = if (isSelected) onSelected else onIdle
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clickable(
                            role = Role.Tab,
                            onClick = { onSelect(tab) }
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .defaultMinSize(minWidth = 40.dp, minHeight = 32.dp)
                            .widthIn(max = 58.dp)
                            .clip(RoundedCornerShape(20.dp))
                            .then(
                                if (isSelected) Modifier.background(pill.copy(alpha = 0.55f))
                                else Modifier
                            )
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        if (isAuthenticated && tab == MainTab.Profile && tabUnread > 0) {
                            BadgedBox(
                                badge = { Badge { Text(tabUnread.toString()) } }
                            ) {
                                MainTabIcon(tab, myAvatarUrl, desc, iconTint = iconTint)
                            }
                        } else {
                            MainTabIcon(tab, myAvatarUrl, desc, iconTint = iconTint)
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainShellScreen(
    supabase: SupabaseClient,
    onSignOut: () -> Unit,
    isAuthenticated: Boolean = true,
    authViewModel: AuthViewModel
) {
    val context = LocalContext.current
    var backgroundTheme by remember { mutableStateOf(LiftrPreferences.backgroundTheme(context)) }
    var selected by rememberSaveable { mutableStateOf(MainTab.Home) }
    var homeRefreshNonce by remember { mutableIntStateOf(0) }
    var homeFeedSyncNonce by remember { mutableIntStateOf(0) }
    var homeFeedSyncWorkoutId by remember { mutableIntStateOf(0) }
    var duplicateApplyNonce by rememberSaveable { mutableStateOf(0) }
    var kindNudge by rememberSaveable { mutableStateOf<String?>(null) }
    var kindNudgeNonce by rememberSaveable { mutableStateOf(0) }
    var overlay by rememberSaveable { mutableStateOf<MainOverlay?>(null) }
    var tabUnread by rememberSaveable { mutableIntStateOf(0) }
    var myAvatarUrl by remember { mutableStateOf<String?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }
    var topBanner by remember { mutableStateOf<AppBannerEvent?>(null) }
    var topBannerHideJob by remember { mutableStateOf<Job?>(null) }
    val coroutineScope = rememberCoroutineScope()
    val updatePrefs = remember { PlayStoreUpdatePrompt.prefs(context) }
    var showUpdateBanner by remember { mutableStateOf(false) }

    LaunchedEffect(isAuthenticated) {
        if (isAuthenticated) {
            PostLoginShellMessage.take()?.let { m ->
                snackbarHostState.showSnackbar("✓ $m")
            }
        }
    }
    LaunchedEffect(Unit) {
        if (!PlayStoreUpdatePrompt.canCheck(updatePrefs)) return@LaunchedEffect
        val act = context as? Activity ?: return@LaunchedEffect
        PlayStoreUpdatePrompt.markCheckStart(updatePrefs)
        val manager = AppUpdateManagerFactory.create(act)
        manager.appUpdateInfo.addOnSuccessListener { info ->
            if (info.updateAvailability() != UpdateAvailability.UPDATE_AVAILABLE) return@addOnSuccessListener
            val v = info.availableVersionCode()
            if (PlayStoreUpdatePrompt.shouldShowPrompt(updatePrefs, v)) {
                PlayStoreUpdatePrompt.recordPromptShown(updatePrefs, v)
                showUpdateBanner = true
            }
        }
    }

    LaunchedEffect(supabase) {
        val me = supabase.auth.currentUserOrNull()?.id
        myAvatarUrl = if (me != null) loadProfileAvatarUrl(supabase, me) else null
    }
    LaunchedEffect(selected, supabase) {
        if (selected == MainTab.Profile) {
            val me = supabase.auth.currentUserOrNull()?.id
            myAvatarUrl = if (me != null) loadProfileAvatarUrl(supabase, me) else null
        }
    }
    LaunchedEffect(Unit) {
        AppSnackbar.events.collect { ev ->
            topBanner = ev
            topBannerHideJob?.cancel()
            topBannerHideJob = coroutineScope.launch {
                delay(4_200L)
                topBanner = null
            }
            // Éxito: solo banner superior (estilo iOS); error/info siguen con Snackbar.
            when (ev) {
                is AppBannerEvent.Success -> { }
                is AppBannerEvent.Error -> snackbarHostState.showSnackbar("✕ ${ev.message}")
                is AppBannerEvent.Info -> snackbarHostState.showSnackbar(ev.message)
            }
        }
    }
    LaunchedEffect(isAuthenticated, supabase) {
        if (!isAuthenticated) {
            tabUnread = 0
            return@LaunchedEffect
        }
        tabUnread = UnreadNotificationCounter.count(supabase)
        while (true) {
            delay(60_000L)
            tabUnread = UnreadNotificationCounter.count(supabase)
        }
    }
    LaunchedEffect(isAuthenticated, supabase) {
        if (!isAuthenticated) return@LaunchedEffect
        NotificationUnreadSync.events.collect {
            tabUnread = UnreadNotificationCounter.count(supabase)
        }
    }

    LaunchedEffect(Unit) {
        HomeFeedSync.events.collect { id ->
            homeFeedSyncWorkoutId = id
            homeFeedSyncNonce++
        }
    }

    LaunchedEffect(Unit) {
        AppNavEvents.events.collect { o ->
            when (o) {
                is MainOverlay.AddWorkoutDraftKind -> {
                    kindNudge = o.kind
                    kindNudgeNonce = kindNudgeNonce + 1
                    selected = MainTab.Add
                }
                else -> {
                    selectTabForRootOverlay(o)?.let { selected = it }
                    overlay = o
                }
            }
        }
    }

    fun clearOverlay() {
        overlay = null
    }

    Box(
        Modifier
            .fillMaxSize()
            .liftrAppBackgroundGradient(backgroundTheme)
    ) {
        val mainOverlay = overlay
        val showTabShell = mainOverlay == null
        Scaffold(
            containerColor = Color.Transparent,
            contentColor = MaterialTheme.colorScheme.onBackground,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {},
            bottomBar = {
                if (showTabShell) {
                LiftrMainBottomBar(
                    selected = selected,
                    onSelect = { selected = it },
                    isAuthenticated = isAuthenticated,
                    tabUnread = tabUnread,
                    myAvatarUrl = myAvatarUrl
                )
                }
            }
        ) { paddingValues ->
            if (showTabShell) {
                when (selected) {
                MainTab.Home -> {
                    HomeTabScreen(
                        supabase = supabase,
                        onOpenAddWithPendingDuplicate = {
                            duplicateApplyNonce++
                            selected = MainTab.Add
                        },
                        homeRefreshNonce = homeRefreshNonce,
                        homeFeedSyncNonce = homeFeedSyncNonce,
                        homeFeedSyncWorkoutId = homeFeedSyncWorkoutId,
                        onGoToProfileTab = { selected = MainTab.Profile },
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(paddingValues)
                    )
                }

                MainTab.Search -> {
                    SearchTabScreen(
                        supabase = supabase,
                        onOpenAddWithPendingDuplicate = {
                            duplicateApplyNonce++
                            selected = MainTab.Add
                        },
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(paddingValues)
                    )
                }

                MainTab.Add -> {
                    AddWorkoutTabScreen(
                        supabase = supabase,
                        duplicateApplyNonce = duplicateApplyNonce,
                        kindNudge = kindNudge,
                        kindNudgeNonce = kindNudgeNonce,
                        onWorkoutPublishedToHome = {
                            selected = MainTab.Home
                            homeRefreshNonce++
                        },
                        isSignedIn = isAuthenticated,
                        onGoToSignIn = { selected = MainTab.Profile },
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(paddingValues)
                    )
                }

                MainTab.Ranking -> {
                    RankingTabScreen(
                        supabase = supabase,
                        onOpenAddWithPendingDuplicate = {
                            duplicateApplyNonce++
                            selected = MainTab.Add
                        },
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(paddingValues)
                    )
                }

                MainTab.Profile -> {
                    if (isAuthenticated) {
                        ProfileTabScreen(
                            supabase = supabase,
                            onSignOut = onSignOut,
                            backgroundThemeId = backgroundTheme,
                            onBackgroundThemeChange = { id ->
                                LiftrPreferences.setBackgroundTheme(context, id)
                                backgroundTheme = id
                            },
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(paddingValues)
                        )
                    } else {
                        ProfileAuthNavHost(
                            viewModel = authViewModel,
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(paddingValues)
                        )
                    }
                }
                }
            } else {
                Box(Modifier.fillMaxSize().padding(paddingValues))
            }
        }

        if (mainOverlay != null) {
            val overlayNonNull = mainOverlay
            Box(
                Modifier
                    .fillMaxSize()
                    .zIndex(1f)
                    .liftrAppBackgroundGradient(backgroundTheme)
            ) {
                when (overlayNonNull) {
                    is MainOverlay.WorkoutDetail -> {
                if (overlayNonNull.ownerId == null) {
                    WorkoutDetailFromNotificationOverlay(
                        supabase = supabase,
                        workoutId = overlayNonNull.workoutId,
                        onBack = { clearOverlay() },
                        modifier = Modifier.fillMaxSize()
                    )
                } else {
                    WorkoutDetailScreen(
                        supabase = supabase,
                        workoutId = overlayNonNull.workoutId,
                        onBack = { clearOverlay() },
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
            is MainOverlay.FollowerProfile -> {
                ProfileTabScreen(
                    supabase = supabase,
                    onSignOut = {},
                    targetUserId = overlayNonNull.userId,
                    showSignOutButton = false,
                    onBack = { clearOverlay() },
                    modifier = Modifier.fillMaxSize()
                )
            }
            is MainOverlay.Goals -> {
                GoalsScreen(
                    supabase = supabase,
                    targetUserId = overlayNonNull.userId,
                    viewedUsername = "",
                    onBack = { clearOverlay() },
                    modifier = Modifier.fillMaxSize()
                )
            }
            is MainOverlay.Achievements -> {
                val me = supabase.auth.currentUserOrNull()?.id
                if (me != null) {
                    AchievementsScreen(
                        supabase = supabase,
                        targetUserId = me,
                        viewedUsername = "",
                        fromNotification = overlayNonNull.fromNotification,
                        onBack = { clearOverlay() },
                        modifier = Modifier.fillMaxSize()
                    )
                } else {
                    clearOverlay()
                }
            }
            is MainOverlay.CompetitionsHub -> {
                CompetitionsHubScreen(
                    supabase = supabase,
                    onBack = { clearOverlay() },
                    modifier = Modifier.fillMaxSize()
                )
            }
            is MainOverlay.CompetitionDetailById -> {
                CompetitionDetailFromIdScreen(
                    supabase = supabase,
                    competitionId = overlayNonNull.competitionId,
                    onBack = { clearOverlay() },
                    modifier = Modifier.fillMaxSize()
                )
            }
            is MainOverlay.CompetitionReviews -> {
                CompetitionReviewsScreen(
                    supabase = supabase,
                    onBack = { clearOverlay() },
                    modifier = Modifier.fillMaxSize()
                )
            }
            is MainOverlay.SegmentDetail -> {
                SegmentDetailScreen(
                    supabase = supabase,
                    segmentId = overlayNonNull.segmentId,
                    onBack = { clearOverlay() },
                    modifier = Modifier.fillMaxSize()
                )
            }
            is MainOverlay.ChallengeWeeklyDetail -> {
                ChallengeWeeklyDetailScreen(
                    supabase = supabase,
                    instanceId = overlayNonNull.instanceId,
                    onBack = { clearOverlay() },
                    modifier = Modifier.fillMaxSize()
                )
            }
            is MainOverlay.AddWorkoutDraftKind -> { }
                }
            }
        }

        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .zIndex(2f)
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            AnimatedVisibility(
                visible = showUpdateBanner,
                enter = fadeIn(),
                exit = fadeOut()
            ) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.95f)
                    )
                ) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            stringResource(R.string.app_update_banner_title),
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                        Text(
                            stringResource(R.string.app_update_banner_body),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.9f)
                        )
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            TextButton(onClick = { showUpdateBanner = false }) {
                                Text(stringResource(R.string.app_update_banner_later))
                            }
                            TextButton(
                                onClick = {
                                    val pkg = context.packageName
                                    try {
                                        context.startActivity(
                                            Intent(
                                                Intent.ACTION_VIEW,
                                                Uri.parse("market://details?id=$pkg")
                                            )
                                        )
                                    } catch (_: Exception) {
                                        context.startActivity(
                                            Intent(
                                                Intent.ACTION_VIEW,
                                                Uri.parse("https://play.google.com/store/apps/details?id=$pkg")
                                            )
                                        )
                                    }
                                }
                            ) {
                                Text(stringResource(R.string.app_update_banner_action))
                            }
                        }
                    }
                }
            }
            AnimatedVisibility(
                visible = topBanner != null,
                enter = fadeIn(),
                exit = fadeOut()
            ) {
                val b = topBanner ?: return@AnimatedVisibility
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = when (b) {
                            is AppBannerEvent.Success -> Color(0xFF2E7D32)
                            is AppBannerEvent.Error -> Color(0xFFC62828)
                            is AppBannerEvent.Info -> Color(0xFF1565C0)
                        }
                    )
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Icon(
                            imageVector = when (b) {
                                is AppBannerEvent.Success -> Icons.Filled.CheckCircle
                                is AppBannerEvent.Error -> Icons.Filled.Error
                                is AppBannerEvent.Info -> Icons.Filled.Info
                            },
                            contentDescription = null,
                            tint = Color.White
                        )
                        Text(
                            b.message,
                            color = Color.White,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
    }
}
