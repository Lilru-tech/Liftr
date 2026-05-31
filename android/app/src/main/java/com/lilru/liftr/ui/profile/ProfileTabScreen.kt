package com.lilru.liftr.ui.profile

import android.net.Uri
import com.lilru.liftr.domain.levelProgressRatio
import com.lilru.liftr.nutrition.NutritionMetabolism
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.clickable
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.SportsMartialArts
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.Surface
import androidx.compose.material3.TextButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.lilru.liftr.BuildConfig
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import android.app.Activity
import android.widget.Toast
import com.lilru.liftr.LiftrApplication
import com.lilru.liftr.R
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.SupabaseResponseDecoding
import com.lilru.liftr.data.PremiumStatusStore
import com.lilru.liftr.prefs.LiftrPreferences
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.territory.TerritoryMapScreen
import com.lilru.liftr.ui.territory.TerritoryProfileHubCard
import com.lilru.liftr.util.AvatarImageUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.lilru.liftr.ui.achievements.AchievementsScreen
import com.lilru.liftr.ui.feature.FeatureRequestsListScreen
import com.lilru.liftr.ui.goals.GoalsScreen
import com.lilru.liftr.ui.notifications.NotificationsScreen
import com.lilru.liftr.ui.competition.CreateCompetitionScreen
import com.lilru.liftr.ui.competition.CompetitionsHubScreen
import com.lilru.liftr.ui.profile.period.PeriodCompareScreen
import com.lilru.liftr.ui.profile.progress.ProfileProgressScreen
import com.lilru.liftr.ui.profile.NotificationSettingsScreen
import com.lilru.liftr.ui.ranking.RankingInitial
import com.lilru.liftr.ui.ranking.RankingMetric
import com.lilru.liftr.ui.ranking.RankingScope
import com.lilru.liftr.ui.ranking.RankingTabScreen
import com.lilru.liftr.ui.bodyweight.BodyWeightHistoryScreen
import com.lilru.liftr.ui.bodyweight.HealthConnectBodyWeightImportScreen
import com.lilru.liftr.ui.health.HealthConnectImportScreen
import com.lilru.liftr.ui.segment.SegmentDetailScreen
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.auth.auth
import java.text.DateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray

/** Pestañas alineadas con [Liftr.ProfileView.Tab] en iOS. */
private data class ProfileMySegmentRow(
    val id: String,
    val name: String,
    val bufferM: Double,
    val status: String
)

@Serializable
private data class ProfilePublishedSegmentWire(
    val id: String,
    val name: String,
    @SerialName("buffer_m") val bufferM: Double,
    val status: String
)

private enum class ProfileMainTab {
    Calendar,
    Prs,
    Progress,
    Segments,
    Settings
}

@Composable
private fun ProfileIosStyleHeader(
    ui: ProfileUiState,
    profileUserId: String?,
    meId: String?,
    bioExpanded: Boolean,
    onBioExpandedToggle: () -> Unit,
    onOpenBioSheet: () -> Unit,
    onPickAvatar: () -> Unit,
    listMode: (FollowListMode) -> Unit,
    onLevelClick: () -> Unit,
    onShowCreateCompetition: () -> Unit,
    profileMenuExpanded: Boolean,
    onProfileMenuExpandedChange: (Boolean) -> Unit,
    onMenuNotifications: () -> Unit,
    onMenuAchievements: () -> Unit,
    onMenuGoals: () -> Unit,
    onMenuCompetitions: () -> Unit,
    onOpenRanking: () -> Unit,
    showUsernameInCard: Boolean = true,
    toggleFollow: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.38f)
        ),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(0.8.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .then(
                        if (ui.isOwnProfile && !ui.uploadAvatarBusy) {
                            Modifier.clickable(onClick = onPickAvatar)
                        } else {
                            Modifier
                        }
                    )
            ) {
                LiftrAvatar(
                    imageUrl = ui.avatarUrl,
                    displayName = ui.displayName ?: ui.username,
                    size = 80.dp
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (showUsernameInCard) {
                    Text(
                        text = (ui.displayName ?: ui.username)?.let { "@$it" }
                            ?: stringResource(R.string.profile_unknown_username),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                if (!ui.email.isNullOrBlank() && ui.isOwnProfile) {
                    Text(
                        ui.email!!,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Surface(
                        onClick = { listMode(FollowListMode.FOLLOWERS) },
                        shape = RoundedCornerShape(50),
                        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.55f),
                        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                    ) {
                        Row(
                            Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(Icons.Filled.Groups, contentDescription = null, modifier = Modifier.padding(0.dp))
                            Text(
                                "${ui.followers}",
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                    Surface(
                        onClick = { listMode(FollowListMode.FOLLOWING) },
                        shape = RoundedCornerShape(50),
                        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.55f),
                        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                    ) {
                        Row(
                            Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.Send,
                                contentDescription = null,
                                modifier = Modifier.padding(0.dp)
                            )
                            Text(
                                "${ui.following}",
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }
                if (profileUserId != null) {
                    val xpStr = java.text.NumberFormat.getIntegerInstance().format(ui.xp)
                    val pr = levelProgressRatio(ui.xp, ui.currentLevelXp, ui.nextLevelXp).toFloat()
                    Column(
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.clickable(onClick = onLevelClick)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Surface(
                                shape = RoundedCornerShape(50),
                                color = Color(0xFFFFC107).copy(alpha = 0.25f),
                                border = BorderStroke(0.5.dp, Color.White.copy(alpha = 0.18f))
                            ) {
                                Text(
                                    "LV ${ui.level}",
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = FontWeight.Black,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                                )
                            }
                            Text(
                                stringResource(R.string.profile_level_xp_line, ui.level, xpStr),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        LinearProgressIndicator(
                            progress = { pr },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(6.dp),
                            color = Color(0xFF4CAF50).copy(alpha = 0.55f),
                            trackColor = Color.White.copy(alpha = 0.12f)
                        )
                    }
                }
                val bioText = ui.bio?.trim().orEmpty()
                if (bioText.isNotEmpty()) {
                    Text(
                        text = bioText,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = if (bioExpanded) Int.MAX_VALUE else 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (ui.isOwnProfile) {
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            TextButton(onClick = onBioExpandedToggle) {
                                Text(
                                    if (bioExpanded) {
                                        stringResource(R.string.profile_bio_show_less)
                                    } else {
                                        stringResource(R.string.profile_bio_read_more)
                                    }
                                )
                            }
                            TextButton(onClick = onOpenBioSheet) {
                                Text(stringResource(R.string.profile_edit_bio))
                            }
                        }
                    }
                } else if (ui.isOwnProfile) {
                    TextButton(onClick = onOpenBioSheet) {
                        Text(stringResource(R.string.profile_add_bio))
                    }
                }
                if (profileUserId != null &&
                    (ui.weeklyGoalsTotal > 0 || ui.achievementsTotal > 0)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 2.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (ui.weeklyGoalsTotal > 0) {
                            Text(
                                text = stringResource(
                                    R.string.profile_header_goals_snippet,
                                    ui.weeklyGoalsDone,
                                    ui.weeklyGoalsTotal
                                ),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.clickable(onClick = onMenuGoals)
                            )
                        }
                        if (ui.weeklyGoalsTotal > 0 && ui.achievementsTotal > 0) {
                            Text(
                                " · ",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f)
                            )
                        }
                        if (ui.achievementsTotal > 0) {
                            Text(
                                text = stringResource(
                                    R.string.profile_header_achievements_snippet,
                                    ui.achievementsUnlocked,
                                    ui.achievementsTotal
                                ),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.clickable(onClick = onMenuAchievements)
                            )
                        }
                    }
                }
                if (!ui.isOwnProfile) {
                    val canInteract = meId != null && profileUserId != null && meId != profileUserId
                    val btnH = Modifier.heightIn(min = 32.dp, max = 40.dp)
                    if (canInteract) {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                if (ui.isFollowing) {
                                    OutlinedButton(
                                        onClick = toggleFollow,
                                        enabled = !ui.followBusy,
                                        modifier = Modifier
                                            .weight(1f, fill = true)
                                            .then(btnH),
                                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp)
                                    ) {
                                        Text(
                                            if (ui.followBusy) {
                                                stringResource(R.string.profile_follow_busy)
                                            } else {
                                                stringResource(R.string.profile_unfollow)
                                            },
                                            style = MaterialTheme.typography.labelMedium,
                                            fontWeight = FontWeight.SemiBold,
                                            maxLines = 1
                                        )
                                    }
                                } else {
                                    Button(
                                        onClick = toggleFollow,
                                        enabled = !ui.followBusy,
                                        modifier = Modifier
                                            .weight(1f, fill = true)
                                            .then(btnH),
                                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp)
                                    ) {
                                        Text(
                                            if (ui.followBusy) {
                                                stringResource(R.string.profile_follow_busy)
                                            } else {
                                                stringResource(R.string.profile_follow)
                                            },
                                            style = MaterialTheme.typography.labelMedium,
                                            fontWeight = FontWeight.SemiBold,
                                            maxLines = 1
                                        )
                                    }
                                }
                                Button(
                                    onClick = onShowCreateCompetition,
                                    enabled = !ui.followBusy && !ui.loading,
                                    modifier = Modifier
                                        .weight(1f, fill = true)
                                        .then(btnH),
                                    contentPadding = PaddingValues(horizontal = 6.dp, vertical = 6.dp)
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.Center,
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        Icon(
                                            Icons.Filled.SportsMartialArts,
                                            contentDescription = null,
                                            modifier = Modifier.size(14.dp)
                                        )
                                        Spacer(Modifier.width(4.dp))
                                        Text(
                                            stringResource(R.string.profile_challenge_button),
                                            style = MaterialTheme.typography.labelMedium,
                                            fontWeight = FontWeight.SemiBold,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                    }
                                }
                            }
                            if (bioText.isNotEmpty()) {
                                TextButton(
                                    onClick = onBioExpandedToggle,
                                    contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp)
                                ) {
                                    Text(
                                        if (bioExpanded) {
                                            stringResource(R.string.profile_bio_show_less)
                                        } else {
                                            stringResource(R.string.profile_bio_read_more)
                                        },
                                        style = MaterialTheme.typography.labelSmall,
                                        maxLines = 1
                                    )
                                }
                            }
                        }
                    }
                }
            }
            Box {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onOpenRanking) {
                        Icon(
                            Icons.Filled.EmojiEvents,
                            contentDescription = stringResource(R.string.profile_menu_ranking)
                        )
                    }
                    IconButton(onClick = { onProfileMenuExpandedChange(true) }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = null)
                    }
                }
                if (ui.isOwnProfile && ui.unreadNotifications > 0) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(top = 4.dp, end = 6.dp)
                            .size(8.dp)
                            .background(MaterialTheme.colorScheme.error, CircleShape)
                    )
                }
                DropdownMenu(
                    expanded = profileMenuExpanded,
                    onDismissRequest = { onProfileMenuExpandedChange(false) }
                ) {
                    if (ui.isOwnProfile) {
                        DropdownMenuItem(
                            text = {
                                Text(
                                    stringResource(
                                        R.string.profile_notifications_button,
                                        ui.unreadNotifications
                                    )
                                )
                            },
                            onClick = {
                                onProfileMenuExpandedChange(false)
                                onMenuNotifications()
                            },
                            leadingIcon = {
                                Icon(
                                    Icons.Filled.Notifications,
                                    contentDescription = null,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.profile_menu_achievements)) },
                        onClick = {
                            onProfileMenuExpandedChange(false)
                            onMenuAchievements()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Filled.Star,
                                contentDescription = null,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.profile_menu_goals)) },
                        onClick = {
                            onProfileMenuExpandedChange(false)
                            onMenuGoals()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Filled.Flag,
                                contentDescription = null,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    )
                    if (ui.isOwnProfile) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.profile_menu_competitions)) },
                            onClick = {
                                onProfileMenuExpandedChange(false)
                                onMenuCompetitions()
                            },
                            leadingIcon = {
                                Icon(
                                    Icons.Filled.SportsMartialArts,
                                    contentDescription = null,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterialApi::class, ExperimentalMaterial3Api::class)
@Composable
fun ProfileTabScreen(
    supabase: SupabaseClient,
    onSignOut: () -> Unit,
    targetUserId: String? = null,
    showSignOutButton: Boolean = true,
    onBack: (() -> Unit)? = null,
    /**
     * Si no es null, se muestra el selector de fondo (paridad iOS `backgroundTheme`) y
     * [onBackgroundThemeChange] guarda y actualiza el shell.
     */
    backgroundThemeId: String? = null,
    onBackgroundThemeChange: ((String) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val vm: ProfileViewModel = viewModel(
        key = "profile-${targetUserId ?: "me"}",
        factory = ProfileViewModelFactory(supabase, targetUserId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val profileUserId = ui.userId
    var listMode by rememberSaveable { mutableStateOf<FollowListMode?>(null) }
    var showComparePrs by rememberSaveable(targetUserId) { mutableStateOf(false) }
    var showPeriodCompare by rememberSaveable(targetUserId) { mutableStateOf(false) }
    var showLevelDetail by rememberSaveable(targetUserId) { mutableStateOf(false) }
    var showNotifications by rememberSaveable { mutableStateOf(false) }
    var showContactSupport by rememberSaveable { mutableStateOf(false) }
    var showFeatureRequests by rememberSaveable { mutableStateOf(false) }
    var showFaqs by rememberSaveable { mutableStateOf(false) }
    var showHealthConnect by rememberSaveable { mutableStateOf(false) }
    var showBodyWeightHistory by rememberSaveable { mutableStateOf(false) }
    var showHealthConnectWeight by rememberSaveable { mutableStateOf(false) }
    var showGoals by rememberSaveable { mutableStateOf(false) }
    var showAchievements by rememberSaveable { mutableStateOf(false) }
    var showDeleteAccountDialog by rememberSaveable { mutableStateOf(false) }
    var showCompetitions by rememberSaveable { mutableStateOf(false) }
    var showRanking by rememberSaveable { mutableStateOf(false) }
    var showTerritoryMap by rememberSaveable { mutableStateOf(false) }
    var showCreateCompetition by rememberSaveable { mutableStateOf(false) }
    var showNotificationSettings by rememberSaveable { mutableStateOf(false) }
    var competitionsHubContextOpponent by rememberSaveable { mutableStateOf<String?>(null) }
    var bioDraft by remember { mutableStateOf("") }
    var bioExpanded by rememberSaveable { mutableStateOf(false) }
    var showBioSheet by rememberSaveable { mutableStateOf(false) }
    var profileMenuExpanded by remember { mutableStateOf(false) }
    var tabIndex by rememberSaveable(profileUserId) { mutableIntStateOf(0) }
    var segmentDetailId by rememberSaveable(profileUserId) { mutableStateOf<String?>(null) }
    LaunchedEffect(ui.bio) {
        bioDraft = ui.bio.orEmpty()
    }
    LaunchedEffect(profileUserId) {
        tabIndex = 0
    }
    val meId = supabase.auth.currentUserOrNull()?.id
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pickAvatar = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val raw = withContext(Dispatchers.IO) {
                context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            } ?: run {
                vm.setUserVisibleError(context.getString(R.string.profile_avatar_unreadable))
                return@launch
            }
            val jpeg = withContext(Dispatchers.Default) { AvatarImageUtils.rawToAvatarJpeg(raw) }
            if (jpeg == null) {
                vm.setUserVisibleError(context.getString(R.string.profile_avatar_unreadable))
            } else {
                vm.setUserVisibleError(null)
                vm.uploadAvatarJpeg(jpeg)
            }
        }
    }
    val pullState = rememberPullRefreshState(
        refreshing = ui.isRefreshing,
        onRefresh = { vm.refresh(false) }
    )

    val openMySegmentId = remember(segmentDetailId) {
        segmentDetailId?.let { runCatching { UUID.fromString(it) }.getOrNull() }
    }
    LaunchedEffect(segmentDetailId) {
        val raw = segmentDetailId ?: return@LaunchedEffect
        if (runCatching { UUID.fromString(raw) }.getOrNull() == null) {
            segmentDetailId = null
        }
    }
    if (openMySegmentId != null) {
        SegmentDetailScreen(
            supabase = supabase,
            segmentId = openMySegmentId,
            onBack = { segmentDetailId = null },
            modifier = modifier
        )
        return
    }

    if (showRanking) {
        RankingTabScreen(
            supabase = supabase,
            onOpenAddWithPendingDuplicate = {},
            rankingInitial = RankingInitial(
                metric = RankingMetric.LEVEL,
                scope = RankingScope.GLOBAL
            ),
            embedBack = { showRanking = false },
            modifier = modifier
        )
        return
    }

    if (showTerritoryMap) {
        Column(modifier = modifier.fillMaxSize()) {
            LiftrBackTopBar(
                title = "Territory map",
                onBack = { showTerritoryMap = false }
            )
            TerritoryMapScreen(
                supabase = supabase,
                modifier = Modifier.fillMaxSize()
            )
        }
        return
    }

    if (showNotifications) {
        NotificationsScreen(
            supabase = supabase,
            onBack = {
                showNotifications = false
                vm.refresh(false)
            },
            modifier = modifier
        )
        return
    }

    if (showNotificationSettings) {
        NotificationSettingsScreen(
            supabase = supabase,
            onBack = { showNotificationSettings = false },
            modifier = modifier
        )
        return
    }

    if (showContactSupport) {
        ContactSupportScreen(
            supabase = supabase,
            onBack = { showContactSupport = false },
            modifier = modifier
        )
        return
    }

    if (showFeatureRequests) {
        FeatureRequestsListScreen(
            supabase = supabase,
            onBack = { showFeatureRequests = false },
            modifier = modifier
        )
        return
    }

    if (showFaqs) {
        FaqsScreen(
            onBack = { showFaqs = false },
            modifier = modifier
        )
        return
    }

    if (showHealthConnectWeight) {
        HealthConnectBodyWeightImportScreen(
            supabase = supabase,
            onBack = { showHealthConnectWeight = false },
            modifier = modifier
        )
        return
    }

    if (showBodyWeightHistory) {
        BodyWeightHistoryScreen(
            supabase = supabase,
            onBack = { showBodyWeightHistory = false },
            modifier = modifier
        )
        return
    }

    if (showHealthConnect) {
        HealthConnectImportScreen(
            supabase = supabase,
            onBack = { showHealthConnect = false },
            modifier = modifier
        )
        return
    }

    if (showGoals && profileUserId != null) {
        val uname = ui.displayName?.trim().orEmpty()
            .ifEmpty { ui.username?.trim().orEmpty() }
            .ifEmpty { profileUserId.take(8) }
        GoalsScreen(
            supabase = supabase,
            targetUserId = profileUserId,
            viewedUsername = uname,
            onBack = { showGoals = false },
            modifier = modifier
        )
        return
    }

    if (showAchievements && profileUserId != null) {
        val uname = ui.displayName?.trim().orEmpty()
            .ifEmpty { ui.username?.trim().orEmpty() }
            .ifEmpty { profileUserId.take(8) }
        AchievementsScreen(
            supabase = supabase,
            targetUserId = profileUserId,
            viewedUsername = uname,
            onBack = { showAchievements = false },
            modifier = modifier
        )
        return
    }

    if (showCreateCompetition && profileUserId != null && meId != null && meId != profileUserId) {
        CreateCompetitionScreen(
            supabase = supabase,
            opponentUserId = profileUserId,
            onDismiss = { showCreateCompetition = false },
            onViewCompetitions = { oid ->
                showCreateCompetition = false
                competitionsHubContextOpponent = oid
                showCompetitions = true
            },
            modifier = modifier
        )
        return
    }

    if (showCompetitions && (ui.isOwnProfile || competitionsHubContextOpponent != null)) {
        CompetitionsHubScreen(
            supabase = supabase,
            onBack = {
                showCompetitions = false
                competitionsHubContextOpponent = null
            },
            contextOpponentId = competitionsHubContextOpponent,
            modifier = modifier
        )
        return
    }

    if (showComparePrs && meId != null && profileUserId != null && meId != profileUserId) {
        ComparePrsScreen(
            supabase = supabase,
            myUserId = meId,
            otherUserId = profileUserId,
            otherUsername = ui.displayName?.trim()?.takeIf { it.isNotEmpty() }
                ?: ui.username?.trim()?.takeIf { it.isNotEmpty() }
                ?: profileUserId.take(8),
            onBack = { showComparePrs = false },
            modifier = modifier
        )
        return
    }

    if (showPeriodCompare && meId != null && profileUserId != null && meId == profileUserId) {
        PeriodCompareScreen(
            supabase = supabase,
            viewerUserId = meId,
            onBack = { showPeriodCompare = false },
            modifier = modifier
        )
        return
    }

    if (showLevelDetail && profileUserId != null) {
        UserLevelDetailScreen(
            supabase = supabase,
            userId = profileUserId,
            onBack = { showLevelDetail = false },
            onOpenAddWithPendingDuplicate = {},
            modifier = modifier
        )
        return
    }

    if (listMode != null && profileUserId != null) {
        FollowersListScreen(
            supabase = supabase,
            userId = profileUserId,
            mode = listMode!!,
            onBack = { listMode = null },
            modifier = modifier
        )
        return
    }

    val tabEntries = remember(ui.isOwnProfile, profileUserId) {
        buildList {
            add(ProfileMainTab.Calendar)
            add(ProfileMainTab.Prs)
            add(ProfileMainTab.Progress)
            if (profileUserId != null) add(ProfileMainTab.Segments)
            if (ui.isOwnProfile) add(ProfileMainTab.Settings)
        }
    }
    LaunchedEffect(tabEntries.size, profileUserId) {
        if (tabIndex >= tabEntries.size) tabIndex = 0
    }
    val safeTabIndex = tabIndex.coerceIn(0, maxOf(tabEntries.lastIndex, 0))
    val selectedMainTab = tabEntries[safeTabIndex]

    Box(modifier = modifier.fillMaxSize()) {
        val profileNoAds by PremiumStatusStore.isPremium.collectAsStateWithLifecycle()
        Column(
            modifier = Modifier
                .fillMaxSize()
                .then(if (onBack != null) Modifier.statusBarsPadding() else Modifier)
                .pullRefresh(pullState)
                .padding(horizontal = 12.dp)
                .padding(
                    top = if (onBack == null) 8.dp else 0.dp,
                    bottom = 8.dp
                )
        ) {
            if (onBack != null) {
                val barTitle = (ui.displayName ?: ui.username)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { "@$it" }
                val canCompare = meId != null && profileUserId != null && meId != profileUserId
                LiftrBackTopBar(
                    onBack = onBack,
                    title = barTitle,
                    actions = {
                        if (canCompare) {
                            IconButton(
                                onClick = { showComparePrs = true },
                                enabled = !ui.loading
                            ) {
                                Icon(
                                    Icons.Filled.SwapHoriz,
                                    contentDescription = stringResource(R.string.profile_compare_prs)
                                )
                            }
                        }
                    }
                )
            }
            ProfileIosStyleHeader(
                ui = ui,
                profileUserId = profileUserId,
                meId = meId,
                bioExpanded = bioExpanded,
                onBioExpandedToggle = { bioExpanded = !bioExpanded },
                onOpenBioSheet = { showBioSheet = true },
                onPickAvatar = {
                    pickAvatar.launch(
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                    )
                },
                listMode = { listMode = it },
                onLevelClick = { if (profileUserId != null) showLevelDetail = true },
                onShowCreateCompetition = { showCreateCompetition = true },
                profileMenuExpanded = profileMenuExpanded,
                onProfileMenuExpandedChange = { profileMenuExpanded = it },
                onMenuNotifications = { showNotifications = true },
                onMenuAchievements = { if (profileUserId != null) showAchievements = true },
                onMenuGoals = { if (profileUserId != null) showGoals = true },
                onMenuCompetitions = {
                    competitionsHubContextOpponent = null
                    showCompetitions = true
                },
                onOpenRanking = { showRanking = true },
                showUsernameInCard = onBack == null,
                toggleFollow = vm::toggleFollow
            )
            SecondaryTabRow(selectedTabIndex = safeTabIndex) {
                tabEntries.forEachIndexed { i, tab ->
                    Tab(
                        selected = safeTabIndex == i,
                        onClick = { tabIndex = i },
                        text = {
                            Text(
                                stringResource(
                                    when (tab) {
                                        ProfileMainTab.Calendar -> R.string.profile_tab_calendar
                                        ProfileMainTab.Prs -> R.string.profile_tab_prs
                                        ProfileMainTab.Progress -> R.string.profile_tab_progress
                                        ProfileMainTab.Segments -> R.string.profile_tab_explore
                                        ProfileMainTab.Settings -> R.string.profile_tab_settings
                                    }
                                ),
                                style = MaterialTheme.typography.labelSmall,
                                maxLines = 1
                            )
                        }
                    )
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                when (selectedMainTab) {
                    ProfileMainTab.Calendar -> {
                        val calScroll = rememberScrollState()
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(calScroll),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            if (profileUserId != null) {
                                ProfileCalendarCard(
                                    supabase = supabase,
                                    profileUserId = profileUserId
                                )
                            }
                        }
                    }
                    ProfileMainTab.Prs -> {
                        if (profileUserId != null) {
                            val uname = ui.displayName?.trim().orEmpty()
                                .ifEmpty { ui.username?.trim().orEmpty() }
                            ProfilePrsListScreen(
                                supabase = supabase,
                                userId = profileUserId,
                                username = uname,
                                showCompare = meId != null && meId != profileUserId,
                                onCompare = if (meId != null && meId != profileUserId) {
                                    { showComparePrs = true }
                                } else {
                                    null
                                },
                                onBack = {},
                                modifier = Modifier.fillMaxSize(),
                                embedded = true
                            )
                        }
                    }
                    ProfileMainTab.Progress -> {
                        if (profileUserId != null) {
                            ProfileProgressScreen(
                                supabase = supabase,
                                userId = profileUserId,
                                onBack = {},
                                modifier = Modifier.fillMaxSize(),
                                embedded = true,
                                onPeriodCompare = if (meId != null && meId == profileUserId) {
                                    { showPeriodCompare = true }
                                } else {
                                    null
                                }
                            )
                        }
                    }
                    ProfileMainTab.Segments -> {
                        if (profileUserId != null) {
                            var rows by remember(profileUserId, ui.isOwnProfile) { mutableStateOf<List<ProfileMySegmentRow>>(emptyList()) }
                            var busy by remember { mutableStateOf(true) }
                            var loadErr by remember { mutableStateOf<String?>(null) }
                            LaunchedEffect(profileUserId, ui.isOwnProfile) {
                                busy = true
                                loadErr = null
                                runCatching {
                                    rows = if (ui.isOwnProfile) {
                                        val res = supabase.postgrest.rpc(
                                            BackendContracts.Rpc.LIST_MY_SEGMENTS_V1,
                                            buildJsonObject { put("p_limit", 100) }
                                        ) { }
                                        val arr = JSONArray(res.data)
                                        val out = ArrayList<ProfileMySegmentRow>(arr.length())
                                        for (i in 0 until arr.length()) {
                                            val o = arr.optJSONObject(i) ?: continue
                                            out.add(
                                                ProfileMySegmentRow(
                                                    id = o.optString("id"),
                                                    name = o.optString("name"),
                                                    bufferM = o.optDouble("buffer_m"),
                                                    status = o.optString("status")
                                                )
                                            )
                                        }
                                        out
                                    } else {
                                        supabase.from(BackendContracts.Tables.SEGMENTS)
                                            .select(columns = Columns.raw("id, name, buffer_m, status")) {
                                                filter {
                                                    eq("created_by", profileUserId)
                                                    eq("status", "published")
                                                }
                                                order("created_at", Order.DESCENDING)
                                                limit(100)
                                            }
                                            .let { res ->
                                                SupabaseResponseDecoding.decodeListOrObject<ProfilePublishedSegmentWire>(res.data)
                                            }
                                            .map {
                                                ProfileMySegmentRow(
                                                    id = it.id,
                                                    name = it.name,
                                                    bufferM = it.bufferM,
                                                    status = it.status
                                                )
                                            }
                                    }
                                }.onFailure { loadErr = it.message }
                                busy = false
                            }
                            Column(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .verticalScroll(rememberScrollState())
                                    .padding(vertical = 8.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                TerritoryProfileHubCard(
                                    supabase = supabase,
                                    profileUserId = profileUserId,
                                    isOwnProfile = ui.isOwnProfile,
                                    onOpenMap = { showTerritoryMap = true },
                                    modifier = Modifier.fillMaxWidth()
                                )
                                Text(
                                    text = stringResource(
                                        if (ui.isOwnProfile) {
                                            R.string.profile_your_segments
                                        } else {
                                            R.string.profile_tab_segments
                                        }
                                    ),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                                if (busy && rows.isEmpty()) {
                                    LinearProgressIndicator(Modifier.fillMaxWidth())
                                }
                                loadErr?.let { err ->
                                    Text(
                                        text = err,
                                        color = MaterialTheme.colorScheme.error,
                                        style = MaterialTheme.typography.bodyMedium
                                    )
                                }
                                if (!busy && rows.isEmpty() && loadErr == null) {
                                    Text(
                                        text = stringResource(
                                            if (ui.isOwnProfile) {
                                                R.string.profile_my_segments_empty
                                            } else {
                                                R.string.profile_other_segments_empty
                                            }
                                        ),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                rows.forEach { row ->
                                    Card(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable { segmentDetailId = row.id }
                                    ) {
                                        Column(
                                            modifier = Modifier.padding(14.dp),
                                            verticalArrangement = Arrangement.spacedBy(4.dp)
                                        ) {
                                            Text(
                                                text = row.name,
                                                style = MaterialTheme.typography.titleSmall,
                                                fontWeight = FontWeight.SemiBold
                                            )
                                            Text(
                                                text = buildString {
                                                    append(row.status)
                                                    append(" · ")
                                                    append(
                                                        context.getString(
                                                            R.string.profile_my_segments_buffer,
                                                            row.bufferM.toInt()
                                                        )
                                                    )
                                                },
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    ProfileMainTab.Settings -> {
                        val settingsScroll = rememberScrollState()
                        val billing = (context.applicationContext as? LiftrApplication)?.playBilling
                        val isPrem by PremiumStatusStore.isPremium.collectAsStateWithLifecycle()
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(settingsScroll),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            // Orden alineado con [Liftr/ProfileView.swift] `settingsView`: Premium → Account →
                            // Health → Appearance → Support → Feedback → FAQs → Personal information → …
                            Card(modifier = Modifier.fillMaxWidth()) {
                                Column(
                                    modifier = Modifier.padding(14.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Text(
                                        stringResource(R.string.profile_premium_title),
                                        style = MaterialTheme.typography.titleMedium
                                    )
                                    Text(
                                        stringResource(R.string.profile_premium_sub),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    if (isPrem) {
                                        Text(
                                            stringResource(R.string.profile_premium_active),
                                            color = MaterialTheme.colorScheme.primary
                                        )
                                    } else {
                                        FilledTonalButton(
                                            onClick = {
                                                val act = context as? Activity
                                                if (act != null && billing != null) {
                                                    billing.launchSubscriptionFlow(act) { msg ->
                                                        Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                                                    }
                                                    scope.launch {
                                                        delay(2000L)
                                                        billing.refreshPremiumFromPlay()
                                                        PremiumStatusStore.refresh(supabase)
                                                    }
                                                } else {
                                                    Toast.makeText(
                                                        context,
                                                        R.string.billing_not_ready,
                                                        Toast.LENGTH_LONG
                                                    ).show()
                                                }
                                            },
                                            modifier = Modifier.fillMaxWidth()
                                        ) { Text(stringResource(R.string.profile_premium_cta)) }
                                        OutlinedButton(
                                            onClick = {
                                                billing?.refreshPremiumFromPlay()
                                                scope.launch {
                                                    delay(1500L)
                                                    PremiumStatusStore.refresh(supabase)
                                                    Toast.makeText(
                                                        context,
                                                        if (PremiumStatusStore.isPremium.value) {
                                                            context.getString(R.string.profile_premium_active)
                                                        } else {
                                                            context.getString(R.string.profile_premium_restore_done)
                                                        },
                                                        Toast.LENGTH_SHORT
                                                    ).show()
                                                }
                                            },
                                            modifier = Modifier.fillMaxWidth()
                                        ) { Text(stringResource(R.string.profile_premium_restore)) }
                                    }
                                }
                            }
                            if (ui.isOwnProfile) {
                                Card(modifier = Modifier.fillMaxWidth()) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(14.dp),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text(
                                            stringResource(R.string.profile_settings_email),
                                            style = MaterialTheme.typography.bodyLarge,
                                            fontWeight = FontWeight.SemiBold
                                        )
                                        Text(
                                            text = ui.email ?: "—",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 1,
                                            modifier = Modifier.weight(1f, fill = false)
                                        )
                                    }
                                }
                            }
                            OutlinedButton(
                                onClick = { showHealthConnect = true },
                                enabled = !ui.loading,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(stringResource(R.string.profile_health_connect))
                            }
                            OutlinedButton(
                                onClick = { showNotificationSettings = true },
                                enabled = !ui.loading,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(stringResource(R.string.notifications_settings_button))
                            }
                            if (backgroundThemeId != null && onBackgroundThemeChange != null) {
                                ProfileBackgroundThemeMenu(
                                    selectedId = backgroundThemeId,
                                    onSelect = onBackgroundThemeChange
                                )
                            }
                            OutlinedButton(
                                onClick = { showContactSupport = true },
                                enabled = !ui.loading,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(stringResource(R.string.contact_support_button))
                            }
                            OutlinedButton(
                                onClick = { showFeatureRequests = true },
                                enabled = !ui.loading,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(stringResource(R.string.feature_requests_title))
                            }
                            OutlinedButton(
                                onClick = { showFaqs = true },
                                enabled = !ui.loading,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(stringResource(R.string.faqs_button))
                            }
                            ProfilePersonalInformationCard(
                                ui = ui,
                                vm = vm,
                                onOpenBodyWeightHistory = { showBodyWeightHistory = true },
                                onOpenHealthConnectWeight = { showHealthConnectWeight = true },
                                onSaved = {
                                    Toast.makeText(
                                        context,
                                        R.string.profile_personal_saved,
                                        Toast.LENGTH_SHORT
                                    ).show()
                                }
                            )
                            var skipCountdown by remember {
                                mutableStateOf(LiftrPreferences.skipStartCountdown(context))
                            }
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    stringResource(R.string.profile_skip_start_countdown),
                                    style = MaterialTheme.typography.bodyLarge,
                                    modifier = Modifier
                                        .weight(1f)
                                        .padding(end = 8.dp)
                                )
                                Switch(
                                    checked = skipCountdown,
                                    onCheckedChange = { v ->
                                        skipCountdown = v
                                        LiftrPreferences.setSkipStartCountdown(context, v)
                                    }
                                )
                            }
                            if (ui.loading) {
                                Text(stringResource(R.string.profile_loading))
                            }
                            if (ui.error != null) {
                                Text(
                                    text = ui.error ?: "",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.error
                                )
                            }
                            if (showSignOutButton && ui.isOwnProfile) {
                                OutlinedButton(
                                    onClick = { if (!ui.deleteAccountBusy) showDeleteAccountDialog = true },
                                    enabled = !ui.deleteAccountBusy,
                                    modifier = Modifier.fillMaxWidth(),
                                    colors = ButtonDefaults.outlinedButtonColors(
                                        contentColor = MaterialTheme.colorScheme.error
                                    )
                                ) {
                                    Text(
                                        if (ui.deleteAccountBusy) {
                                            stringResource(R.string.profile_delete_account_busy)
                                        } else {
                                            stringResource(R.string.profile_delete_account)
                                        }
                                    )
                                }
                            }
                            if (showSignOutButton) {
                                FilledTonalButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) {
                                    Text(stringResource(R.string.home_sign_out))
                                }
                            }
                        }
                    }
                }
            }
            if (!profileNoAds) {
                AndroidView(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp)
                        .padding(top = 4.dp, bottom = 4.dp),
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
            state = pullState,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }

    if (showDeleteAccountDialog && ui.isOwnProfile) {
        AlertDialog(
            onDismissRequest = { if (!ui.deleteAccountBusy) showDeleteAccountDialog = false },
            title = { Text(stringResource(R.string.profile_delete_account_title)) },
            text = { Text(stringResource(R.string.profile_delete_account_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteAccountDialog = false
                        vm.deleteAccount { edgeOk ->
                            Toast.makeText(
                                context,
                                if (edgeOk) {
                                    context.getString(R.string.profile_delete_account_toast_ok)
                                } else {
                                    context.getString(R.string.profile_delete_account_toast_edge_fail)
                                },
                                Toast.LENGTH_LONG
                            ).show()
                            onSignOut()
                        }
                    },
                    enabled = !ui.deleteAccountBusy,
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text(stringResource(R.string.profile_delete_account_confirm))
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showDeleteAccountDialog = false },
                    enabled = !ui.deleteAccountBusy
                ) {
                    Text(stringResource(R.string.profile_delete_account_cancel))
                }
            }
        )
    }

    if (showBioSheet && ui.isOwnProfile) {
        ModalBottomSheet(onDismissRequest = { showBioSheet = false }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    stringResource(R.string.profile_bio_label),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                OutlinedTextField(
                    value = bioDraft,
                    onValueChange = { bioDraft = it },
                    label = { Text(stringResource(R.string.profile_bio_label)) },
                    minLines = 3,
                    maxLines = 8,
                    enabled = !ui.saveBioBusy && !ui.uploadAvatarBusy,
                    modifier = Modifier.fillMaxWidth()
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = { showBioSheet = false },
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(stringResource(R.string.goals_delete_cancel))
                    }
                    Button(
                        onClick = {
                            vm.updateBio(bioDraft)
                            showBioSheet = false
                        },
                        enabled = !ui.saveBioBusy && !ui.uploadAvatarBusy,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            if (ui.saveBioBusy) {
                                stringResource(R.string.profile_follow_busy)
                            } else {
                                stringResource(R.string.profile_bio_save)
                            }
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfilePersonalInformationCard(
    ui: ProfileUiState,
    vm: ProfileViewModel,
    onOpenBodyWeightHistory: () -> Unit,
    onOpenHealthConnectWeight: () -> Unit,
    onSaved: () -> Unit
) {
    var showDobPicker by remember { mutableStateOf(false) }
    var editingPersonalInfo by remember { mutableStateOf(false) }
    val defaultDobMillis = remember {
        val cal = java.util.Calendar.getInstance()
        cal.add(java.util.Calendar.YEAR, -20)
        cal.timeInMillis
    }
    val dobLabel = ui.birthDateMillis?.let { ms ->
        DateFormat.getDateInstance(DateFormat.MEDIUM, Locale.getDefault()).format(Date(ms))
    }
    val ageYears: Int? = ui.birthDateMillis?.let { ms ->
        val birth = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).toLocalDate()
        val now = LocalDate.now(ZoneId.systemDefault())
        ChronoUnit.YEARS.between(birth, now).toInt()
    }
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                stringResource(R.string.profile_personal_info_section),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f)
            )
            IconButton(
                onClick = { editingPersonalInfo = !editingPersonalInfo },
                enabled = !ui.saveProfileMetricsBusy
            ) {
                Icon(
                    imageVector = if (editingPersonalInfo) Icons.Filled.Check else Icons.Filled.Edit,
                    contentDescription = stringResource(R.string.workout_detail_menu_edit)
                )
            }
        }
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (editingPersonalInfo) {
                    OutlinedTextField(
                        value = ui.heightCmDraft,
                        onValueChange = vm::setHeightCmDraft,
                        label = { Text(stringResource(R.string.profile_height_cm)) },
                        singleLine = true,
                        enabled = !ui.saveProfileMetricsBusy,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            stringResource(R.string.profile_height_cm),
                            style = MaterialTheme.typography.bodyLarge
                        )
                        Text(
                            text = ui.heightCmDraft.ifBlank { stringResource(R.string.profile_age_emdash) },
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        stringResource(R.string.profile_weight_kg),
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Text(
                        text = ui.weightKgDraft.ifBlank { stringResource(R.string.profile_age_emdash) },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
                if (editingPersonalInfo) {
                    OutlinedTextField(
                        value = ui.baseCaloriesTargetDraft,
                        onValueChange = vm::setBaseCaloriesTargetDraft,
                        label = { Text(stringResource(R.string.profile_base_calories_target)) },
                        singleLine = true,
                        enabled = !ui.saveProfileMetricsBusy,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            stringResource(R.string.profile_base_calories_target),
                            style = MaterialTheme.typography.bodyLarge
                        )
                        Text(
                            text = ui.baseCaloriesTargetDraft.ifBlank {
                                NutritionMetabolism.demographicFallbackKcal(ui.profileSex).toString()
                            },
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
                OutlinedButton(
                    onClick = onOpenBodyWeightHistory,
                    enabled = !ui.saveProfileMetricsBusy,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.profile_body_weight_history))
                }
                OutlinedButton(
                    onClick = onOpenHealthConnectWeight,
                    enabled = !ui.saveProfileMetricsBusy,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.profile_health_connect_weight))
                }
                if (editingPersonalInfo) {
                    HorizontalDivider()
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            stringResource(R.string.profile_show_birth_date),
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.weight(1f)
                        )
                        Switch(
                            checked = ui.hasBirthDate,
                            onCheckedChange = vm::setHasBirthDate,
                            enabled = !ui.saveProfileMetricsBusy
                        )
                    }
                    if (ui.hasBirthDate) {
                        OutlinedButton(
                            onClick = { showDobPicker = true },
                            enabled = !ui.saveProfileMetricsBusy,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                if (dobLabel != null) {
                                    dobLabel
                                } else {
                                    stringResource(R.string.profile_pick_birth_date)
                                }
                            )
                        }
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(stringResource(R.string.profile_age))
                    Text(
                        text = ageYears?.toString()
                            ?: stringResource(R.string.profile_age_emdash),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
                if (editingPersonalInfo) {
                    FilledTonalButton(
                        onClick = { vm.saveProfileMetrics(onSaved) },
                        enabled = !ui.saveProfileMetricsBusy &&
                            !ui.uploadAvatarBusy && !ui.saveBioBusy,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            if (ui.saveProfileMetricsBusy) {
                                stringResource(R.string.profile_saving)
                            } else {
                                stringResource(R.string.profile_save_personal)
                            }
                        )
                    }
                }
            }
        }
    }
    if (showDobPicker && editingPersonalInfo && ui.hasBirthDate) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = ui.birthDateMillis ?: defaultDobMillis
        )
        DatePickerDialog(
            onDismissRequest = { showDobPicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        state.selectedDateMillis?.let { vm.setBirthDateMillis(it) }
                        showDobPicker = false
                    }
                ) { Text(stringResource(R.string.auth_ok)) }
            },
            dismissButton = {
                TextButton(onClick = { showDobPicker = false }) {
                    Text(stringResource(R.string.goals_delete_cancel))
                }
            }
        ) {
            DatePicker(state = state)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileBackgroundThemeMenu(
    selectedId: String,
    onSelect: (String) -> Unit
) {
    val options = listOf(
        "mintBlue" to R.string.background_theme_mint_blue,
        "sunset" to R.string.background_theme_sunset,
        "forest" to R.string.background_theme_forest,
        "midnight" to R.string.background_theme_midnight,
        "lavender" to R.string.background_theme_lavender,
        "ocean" to R.string.background_theme_ocean,
        "rose" to R.string.background_theme_rose,
        "desert" to R.string.background_theme_desert,
        "berry" to R.string.background_theme_berry,
        "mono" to R.string.background_theme_mono
    )
    var expanded by remember { mutableStateOf(false) }
    val labelRes = options.find { it.first == selectedId }?.second
        ?: R.string.background_theme_mint_blue
    val label = stringResource(labelRes)
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                stringResource(R.string.profile_appearance_section),
                style = MaterialTheme.typography.titleMedium
            )
            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = it }
            ) {
                OutlinedTextField(
                    value = label,
                    onValueChange = {},
                    readOnly = true,
                    singleLine = true,
                    label = { Text(stringResource(R.string.profile_background_label)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                    modifier = Modifier
                        .menuAnchor(type = MenuAnchorType.PrimaryNotEditable, enabled = true)
                        .fillMaxWidth()
                )
                ExposedDropdownMenu(
                    expanded = expanded,
                    onDismissRequest = { expanded = false }
                ) {
                    options.forEach { (id, resId) ->
                        DropdownMenuItem(
                            text = { Text(stringResource(resId)) },
                            onClick = {
                                onSelect(id)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }
    }
}
