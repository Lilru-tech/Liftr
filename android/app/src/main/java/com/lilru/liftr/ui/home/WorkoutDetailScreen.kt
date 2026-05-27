package com.lilru.liftr.ui.home

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.AppSnackbar
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.active.ActiveCardioWorkoutScreen
import com.lilru.liftr.ui.active.ActiveSportWorkoutScreen
import com.lilru.liftr.ui.active.ActiveStrengthWorkoutScreen
import com.lilru.liftr.ui.active.normalizeSportMatchResult
import com.lilru.liftr.ui.add.AddCardioActivity
import com.lilru.liftr.ui.add.AddSportType
import com.lilru.liftr.ui.add.duplicate.AddWorkoutDuplicateStore
import com.lilru.liftr.ui.add.duplicate.loadDuplicateForAdd
import com.lilru.liftr.ui.compare.CompareAverageScope
import com.lilru.liftr.ui.compare.CompareWorkoutCandidate
import com.lilru.liftr.ui.compare.CompareAverageOption
import com.lilru.liftr.ui.compare.CompareOtherTarget
import com.lilru.liftr.ui.compare.ComparePickerEntry
import com.lilru.liftr.ui.compare.ComparePickerState
import com.lilru.liftr.ui.compare.CompareWorkoutsScreen
import com.lilru.liftr.ui.profile.ProfileTabScreen
import com.lilru.liftr.ui.segment.SegmentDetailScreen
import io.github.jan.supabase.SupabaseClient
import java.util.UUID

private enum class PreActiveKind {
    Strength, Cardio, Sport
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkoutDetailScreen(
    supabase: SupabaseClient,
    workoutId: Int,
    onBack: () -> Unit,
    onDuplicateToAdd: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val vm: WorkoutDetailViewModel = viewModel(
        key = "workout-detail-$workoutId",
        factory = WorkoutDetailViewModelFactory(supabase = supabase, workoutId = workoutId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var duplicateBusy by rememberSaveable(workoutId) { mutableStateOf(false) }
    var duplicateError by rememberSaveable(workoutId) { mutableStateOf<String?>(null) }
    var commentDraft by rememberSaveable(workoutId, stateSaver = androidx.compose.ui.text.input.TextFieldValue.Saver) {
        mutableStateOf(androidx.compose.ui.text.input.TextFieldValue(""))
    }
    var trackedMentions by remember(workoutId) { mutableStateOf(listOf<TrackedMention>()) }
    var replyToCommentId by rememberSaveable(workoutId) { mutableStateOf<Int?>(null) }
    var selectedProfileUserId by rememberSaveable(workoutId) { mutableStateOf<String?>(null) }
    var showActiveStrength by rememberSaveable(workoutId) { mutableStateOf(false) }
    var showActiveCardio by rememberSaveable(workoutId) { mutableStateOf(false) }
    var showActiveSport by rememberSaveable(workoutId) { mutableStateOf(false) }
    var preActiveCountdown by remember { mutableStateOf<PreActiveKind?>(null) }
    var showEditMeta by rememberSaveable(workoutId) { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showLikersSheet by rememberSaveable(workoutId) { mutableStateOf(false) }
    var showCompare by rememberSaveable(workoutId) { mutableStateOf(false) }
    var showComparePicker by rememberSaveable(workoutId) { mutableStateOf(false) }
    var compareSearchQuery by remember { mutableStateOf("") }
    var compareOtherId by rememberSaveable(workoutId) { mutableStateOf<Int?>(null) }
    var compareAverageScope by rememberSaveable(workoutId) { mutableStateOf<String?>(null) }
    var compareAverageRightLabel by rememberSaveable(workoutId) { mutableStateOf<String?>(null) }
    var showDualStart by rememberSaveable(workoutId) { mutableStateOf(false) }
    var dualLinkedGuestWid by rememberSaveable(workoutId) { mutableStateOf<Int?>(null) }
    var dualLinkedGuest2Wid by rememberSaveable(workoutId) { mutableStateOf<Int?>(null) }
    var dualGuestAvatarUrl by rememberSaveable(workoutId) { mutableStateOf<String?>(null) }
    var dualGuest2AvatarUrl by rememberSaveable(workoutId) { mutableStateOf<String?>(null) }
    var dualHostAvatarUrl by rememberSaveable(workoutId) { mutableStateOf<String?>(null) }
    var segmentOverlayUuid by rememberSaveable(workoutId) { mutableStateOf<String?>(null) }
    var dualPrepareBusy by rememberSaveable(workoutId) { mutableStateOf(false) }
    var dualSheetSelectedIds by remember(workoutId) { mutableStateOf<Set<String>>(emptySet()) }
    var showCommentsSheet by rememberSaveable(workoutId) { mutableStateOf(false) }
    var menuExpanded by remember { mutableStateOf(false) }
    var startErrorMessage by remember { mutableStateOf<String?>(null) }
    var startFailureOffersSolo by remember { mutableStateOf(false) }
    var startFailureRetryAction by remember { mutableStateOf<(() -> Unit)?>(null) }
    val startCtx = LocalContext.current
    LaunchedEffect(showLikersSheet, ui.likeCount, ui.isLikedByMe, ui.likeBusy) {
        if (showLikersSheet && !ui.likeBusy) {
            vm.loadLikers()
        }
    }

    val openSegmentId = remember(segmentOverlayUuid) {
        segmentOverlayUuid?.let { runCatching { UUID.fromString(it) }.getOrNull() }
    }
    LaunchedEffect(segmentOverlayUuid) {
        val raw = segmentOverlayUuid ?: return@LaunchedEffect
        if (runCatching { UUID.fromString(raw) }.getOrNull() == null) {
            segmentOverlayUuid = null
        }
    }
    if (openSegmentId != null) {
        SegmentDetailScreen(
            supabase = supabase,
            segmentId = openSegmentId,
            onBack = { segmentOverlayUuid = null },
            modifier = modifier
        )
        return
    }

    if (preActiveCountdown != null) {
        val kind = preActiveCountdown!!
        StartWorkoutCountdownScreen(
            onFinished = {
                preActiveCountdown = null
                when (kind) {
                    PreActiveKind.Strength -> showActiveStrength = true
                    PreActiveKind.Cardio -> showActiveCardio = true
                    PreActiveKind.Sport -> showActiveSport = true
                }
            },
            modifier = modifier
        )
        return
    }

    if (showActiveStrength) {
        ActiveStrengthWorkoutScreen(
            supabase = supabase,
            workoutId = workoutId,
            dualGuestWorkoutId = dualLinkedGuestWid,
            dualGuest2WorkoutId = dualLinkedGuest2Wid,
            dualGuestAvatarUrl = dualGuestAvatarUrl,
            dualGuest2AvatarUrl = dualGuest2AvatarUrl,
            dualHostAvatarUrl = dualHostAvatarUrl,
            onClose = {
                showActiveStrength = false
                vm.refresh(showBlockingLoader = false)
            },
            modifier = modifier
        )
        return
    }
    if (showActiveCardio) {
        ActiveCardioWorkoutScreen(
            supabase = supabase,
            workoutId = workoutId,
            onClose = {
                showActiveCardio = false
                vm.refresh(showBlockingLoader = false)
            },
            modifier = modifier
        )
        return
    }
    if (showActiveSport) {
        ActiveSportWorkoutScreen(
            supabase = supabase,
            workoutId = workoutId,
            onClose = {
                showActiveSport = false
                vm.refresh(showBlockingLoader = false)
            },
            modifier = modifier
        )
        return
    }

    if (selectedProfileUserId != null) {
        ProfileTabScreen(
            supabase = supabase,
            onSignOut = {},
            targetUserId = selectedProfileUserId,
            showSignOutButton = false,
            onBack = { selectedProfileUserId = null },
            modifier = modifier
        )
        return
    }

    val compareTarget = remember(compareOtherId, compareAverageScope, ui.comparePicker) {
        resolveCompareTarget(compareOtherId, compareAverageScope, ui.comparePicker)
    }
    if (showCompare && compareTarget != null) {
        CompareWorkoutsScreen(
            supabase = supabase,
            currentWorkoutId = workoutId,
            other = compareTarget,
            averageRightLabel = compareAverageRightLabel,
            onClose = {
                showCompare = false
                compareOtherId = null
                compareAverageScope = null
                compareAverageRightLabel = null
            },
            modifier = modifier
        )
        return
    }

    LaunchedEffect(showComparePicker) {
        if (!showComparePicker) {
            compareSearchQuery = ""
        }
    }

    if (ui.loading) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .then(workoutDetailScreenGradientModifier())
        ) {
            Column(
                modifier = Modifier.fillMaxSize().padding(24.dp),
                verticalArrangement = Arrangement.Center
            ) {
                Text(stringResource(R.string.home_detail_loading))
            }
        }
        return
    }

    if (ui.error != null && ui.workout == null) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .then(workoutDetailScreenGradientModifier())
        ) {
            Column(
                modifier = Modifier.fillMaxSize().padding(24.dp),
                verticalArrangement = Arrangement.Center
            ) {
                Text(ui.error ?: "", color = MaterialTheme.colorScheme.error)
                Button(onClick = vm::refresh, modifier = Modifier.padding(top = 10.dp)) {
                    Text(stringResource(R.string.home_retry))
                }
            }
        }
        return
    }

    val workout = ui.workout ?: return
    val canStartStrength = remember(workout, ui.meUserId, ui.participants) {
        val me = ui.meUserId ?: return@remember false
        if (workout.kind?.lowercase() != "strength") return@remember false
        if (workout.state?.lowercase() != "planned") return@remember false
        val isOwner = workout.userId == me
        val isParticipant = ui.participants.any { it.userId == me }
        isOwner || isParticipant
    }
    val canStartCardio = remember(workout, ui.meUserId, ui.participants) {
        val me = ui.meUserId ?: return@remember false
        if (workout.kind?.lowercase() != "cardio") return@remember false
        if (workout.state?.lowercase() != "planned") return@remember false
        val isOwner = workout.userId == me
        val isParticipant = ui.participants.any { it.userId == me }
        isOwner || isParticipant
    }
    val canStartSport = remember(workout, ui.meUserId, ui.participants) {
        val me = ui.meUserId ?: return@remember false
        if (workout.kind?.lowercase() != "sport") return@remember false
        if (workout.state?.lowercase() != "planned") return@remember false
        val isOwner = workout.userId == me
        val isParticipant = ui.participants.any { it.userId == me }
        isOwner || isParticipant
    }
    val isOwner = remember(workout, ui.meUserId) {
        ui.meUserId != null && workout.userId == ui.meUserId
    }
    val canEditMeta = isOwner && when (workout.kind?.lowercase()) {
        "strength", "cardio" -> true
        "sport" -> ui.sportSession != null
        else -> false
    }
    val canPublish = isOwner && workout.state?.lowercase() == "planned"
    val canDelete = isOwner
    val canDuplicate = onDuplicateToAdd != null && (
        isOwner || (ui.meUserId != null && ui.participants.any { it.userId == ui.meUserId })
        )
    val canCompare = remember(ui.compareReady, workout) {
        ui.compareReady && workout.state?.lowercase() != "planned"
    }
    val duplicateLoadErrorText = stringResource(R.string.home_detail_duplicate_error)
    val showStartBar = (canStartStrength || canStartCardio || canStartSport) &&
        workout.state?.lowercase() == "planned"
    val topBarTitle = workout.title?.takeIf { it.isNotBlank() }
        ?: workoutKindLabel(workout.kind)
    LaunchedEffect(showDualStart, ui.participants.joinToString { it.userId }) {
        if (showDualStart && ui.participants.isNotEmpty()) {
            val allowed = ui.participants.map { it.userId }.toSet()
            var next = dualSheetSelectedIds.filter { allowed.contains(it) }.toSet()
            if (next.isEmpty()) next = setOf(ui.participants.first().userId)
            dualSheetSelectedIds = next
        }
    }
    Box(
        modifier = modifier
            .fillMaxSize()
            .then(workoutDetailScreenGradientModifier())
    ) {
    Scaffold(
        containerColor = Color.Transparent,
        contentColor = MaterialTheme.colorScheme.onBackground,
        topBar = {
            TopAppBar(
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
                title = { Text(topBarTitle, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.home_back)
                        )
                    }
                },
                actions = {
                    if (canPublish && isOwner) {
                        TextButton(
                            onClick = { vm.publishPlannedWorkout() },
                            enabled = !ui.publishBusy
                        ) {
                            Text(
                                if (ui.publishBusy) {
                                    stringResource(R.string.home_detail_publishing)
                                } else {
                                    stringResource(R.string.home_detail_publish)
                                }
                            )
                        }
                    }
                    val showOverflow = canEditMeta || canDuplicate || canDelete || canCompare
                    if (showOverflow) {
                        Box {
                            IconButton(onClick = { menuExpanded = true }) {
                                Icon(Icons.Filled.MoreVert, contentDescription = null)
                            }
                            DropdownMenu(
                                expanded = menuExpanded,
                                onDismissRequest = { menuExpanded = false }
                            ) {
                                if (canCompare) {
                                    DropdownMenuItem(
                                        text = {
                                            Text(
                                                if (shouldShowComparePicker(ui.comparePicker)) {
                                                    stringResource(R.string.home_detail_compare_ellipsis)
                                                } else {
                                                    stringResource(R.string.home_detail_compare)
                                                }
                                            )
                                        },
                                        onClick = {
                                            menuExpanded = false
                                            if (shouldShowComparePicker(ui.comparePicker)) {
                                                showComparePicker = true
                                            } else {
                                                val only = singleCompareTarget(ui.comparePicker)
                                                if (only != null) {
                                                    applyCompareTarget(
                                                        only,
                                                        context,
                                                        onWorkoutId = { compareOtherId = it },
                                                        onAverageScope = { compareAverageScope = it },
                                                        onAverageLabel = { compareAverageRightLabel = it }
                                                    )
                                                    showCompare = true
                                                }
                                            }
                                        }
                                    )
                                }
                                if (canEditMeta) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.workout_detail_menu_edit)) },
                                        onClick = {
                                            menuExpanded = false
                                            showEditMeta = true
                                        }
                                    )
                                }
                                if (canDuplicate) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.home_detail_duplicate)) },
                                        onClick = {
                                            menuExpanded = false
                                            duplicateError = null
                                            if (!duplicateBusy) {
                                                scope.launch {
                                                    duplicateBusy = true
                                                    val payload = runCatching {
                                                        loadDuplicateForAdd(
                                                            supabase = supabase,
                                                            workoutId = workoutId,
                                                            currentUserId = ui.meUserId
                                                        )
                                                    }.getOrNull()
                                                    duplicateBusy = false
                                                    if (payload == null) {
                                                        duplicateError = duplicateLoadErrorText
                                                    } else {
                                                        AddWorkoutDuplicateStore.set(payload)
                                                        onDuplicateToAdd!!()
                                                    }
                                                }
                                            }
                                        }
                                    )
                                }
                                if (canDelete) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.workout_detail_menu_delete_workout)) },
                                        onClick = {
                                            menuExpanded = false
                                            showDeleteConfirm = true
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            )
        },
        bottomBar = {
            if (showStartBar) {
                Surface(
                    shadowElevation = 6.dp,
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f)
                ) {
                    Button(
                        onClick = {
                            val planned = workout.state?.lowercase() == "planned"
                            if (planned && canStartStrength && ui.participants.isNotEmpty()) {
                                if (dualLinkedGuestWid != null || dualLinkedGuest2Wid != null) {
                                    openStrengthActiveWithCountdownPolicy(
                                        startCtx,
                                        { showActiveStrength = it },
                                        { preActiveCountdown = it }
                                    )
                                    return@Button
                                }
                                showDualStart = true
                                return@Button
                            }
                            if (planned && canStartStrength) {
                                com.lilru.liftr.workout.WorkoutStartSync.enqueueStart(startCtx, workoutId)
                            }
                            openPreActiveOrActive(
                                canStartStrength = canStartStrength,
                                canStartCardio = canStartCardio,
                                canStartSport = canStartSport,
                                skipCountdown = LiftrPreferences.skipStartCountdown(startCtx),
                                setPreActive = { preActiveCountdown = it },
                                setShowStrength = { showActiveStrength = it },
                                setShowCardio = { showActiveCardio = it },
                                setShowSport = { showActiveSport = it }
                            )
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp)
                    ) {
                        Text(stringResource(R.string.home_detail_start_workout))
                    }
                }
            }
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 4.dp)
                .padding(bottom = if (showStartBar) 8.dp else 0.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
        if (duplicateError != null) {
            item {
                Text(
                    text = duplicateError!!,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        item {
            WorkoutDetailHeaderCard(
                workout = workout,
                ownerUsername = ui.owner?.username,
                ownerAvatarUrl = ui.owner?.avatarUrl,
                totalScore = ui.totalScore,
                caloriesKcal = workout.caloriesKcal,
                participantsCount = ui.participants.size,
                onOwnerClick = { selectedProfileUserId = workout.userId }
            )
        }
        if (ui.participants.isNotEmpty()) {
            item {
                WorkoutDetailParticipantsCard(
                    participants = ui.participants,
                    onOpenProfile = { selectedProfileUserId = it }
                )
            }
        }
        if (!workout.notes.isNullOrBlank()) {
            item {
                WorkoutDetailNotesCard(workout.notes!!.trim())
            }
        }
        when (workout.kind?.lowercase()) {
            "strength" -> item {
                WorkoutDetailStrengthReadonlySection(ui.strengthReadonly)
            }
            "cardio" -> {
                val cFull = ui.cardioSession
                if (cFull != null) {
                    item {
                        CardioDetailSection(
                            detail = cFull,
                            workoutId = workoutId,
                            workoutState = workout.state,
                            isOwner = isOwner,
                            supabase = supabase,
                            onSegmentCreated = { id -> segmentOverlayUuid = id.toString() },
                            onDuplicateSegment = { id -> segmentOverlayUuid = id.toString() },
                            onOpenProfile = { selectedProfileUserId = it }
                        )
                    }
                } else {
                    val c = workout.cardioSessions?.firstOrNull()
                    if (c != null) {
                        if (c.distanceKm != null) {
                            item {
                                Text(
                                    text = stringResource(R.string.home_detail_cardio_distance_km, c.distanceKm),
                                    style = MaterialTheme.typography.bodySmall
                                )
                            }
                        }
                        if (c.durationSec != null && c.durationSec > 0) {
                            item {
                                Text(
                                    text = stringResource(
                                        R.string.home_detail_cardio_duration,
                                        formatDurationFromSec(c.durationSec)
                                    ),
                                    style = MaterialTheme.typography.bodySmall
                                )
                            }
                        }
                    } else {
                        item {
                            Text(
                                stringResource(R.string.home_detail_cardio_no_session),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
            "sport" -> item {
                WorkoutDetailSportDetailSection(
                    session = ui.sportSession,
                    stats = ui.sportDetailStats
                )
            }
        }
        item {
            WorkoutDetailFeedbackRow(
                isLiked = ui.isLikedByMe,
                likeCount = ui.likeCount,
                commentCount = ui.commentCount,
                likeBusy = ui.likeBusy,
                onToggleLike = { vm.toggleLike() },
                onShowLikers = { showLikersSheet = true },
                onOpenComments = { showCommentsSheet = true }
            )
        }
        if (ui.error != null) {
            item {
                Text(
                    text = ui.error ?: "",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        }
    }
    }
    if (showDualStart && ui.participants.isNotEmpty()) {
        val multiInvite = ui.participants.size > 1
        val showsAsGroup = dualSheetSelectedIds.size > 1
        val solePick = ui.participants.singleOrNull { dualSheetSelectedIds.contains(it.userId) }
        ModalBottomSheet(
            onDismissRequest = { if (!dualPrepareBusy) showDualStart = false }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    if (showsAsGroup) {
                        stringResource(R.string.workout_detail_sheet_group_title)
                    } else {
                        stringResource(R.string.workout_detail_sheet_dual_title)
                    },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                if (multiInvite) {
                    Text(
                        stringResource(R.string.workout_detail_sheet_pick_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    ui.participants.forEach { p ->
                        val sel = dualSheetSelectedIds.contains(p.userId)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(
                                    if (sel) MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)
                                    else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.04f)
                                )
                                .clickable(enabled = !dualPrepareBusy) {
                                    val next = dualSheetSelectedIds.toMutableSet()
                                    if (next.contains(p.userId)) {
                                        if (next.size > 1) next.remove(p.userId)
                                    } else {
                                        if (next.size >= 2) return@clickable
                                        next.add(p.userId)
                                    }
                                    dualSheetSelectedIds = next
                                }
                                .padding(vertical = 8.dp, horizontal = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Icon(
                                if (sel) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                                contentDescription = null,
                                tint = if (sel) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            LiftrAvatar(
                                imageUrl = p.avatarUrl,
                                displayName = p.username,
                                size = 44.dp
                            )
                            Text(
                                "@${p.username?.takeIf { it.isNotBlank() } ?: "user"}",
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1
                            )
                        }
                    }
                } else {
                    val p = ui.participants.first()
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        LiftrAvatar(
                            imageUrl = p.avatarUrl,
                            displayName = p.username,
                            size = 56.dp
                        )
                        Text(
                            "@${p.username?.takeIf { it.isNotBlank() } ?: "user"}",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1
                        )
                    }
                    Text(
                        stringResource(R.string.workout_detail_sheet_single_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedButton(
                        onClick = {
                            if (dualPrepareBusy) return@OutlinedButton
                            dualPrepareBusy = true
                            vm.preparePlannedStrengthAndLinkedGuest(null) { r ->
                                dualPrepareBusy = false
                                r.fold(
                                    onSuccess = {
                                        showDualStart = false
                                        dualLinkedGuestWid = null
                                        dualLinkedGuest2Wid = null
                                        dualGuestAvatarUrl = null
                                        dualGuest2AvatarUrl = null
                                        dualHostAvatarUrl = ui.owner?.avatarUrl
                                        vm.refresh(showBlockingLoader = false)
                                        openStrengthActiveWithCountdownPolicy(
                                            startCtx,
                                            { showActiveStrength = it },
                                            { preActiveCountdown = it }
                                        )
                                    },
                                    onFailure = { e ->
                                        startFailureOffersSolo = true
                                        startFailureRetryAction = {
                                            dualPrepareBusy = true
                                            vm.preparePlannedStrengthAndLinkedGuest(null) { r ->
                                                dualPrepareBusy = false
                                                r.fold(
                                                    onSuccess = {
                                                        showDualStart = false
                                                        dualLinkedGuestWid = null
                                                        dualLinkedGuest2Wid = null
                                                        dualGuestAvatarUrl = null
                                                        dualGuest2AvatarUrl = null
                                                        dualHostAvatarUrl = ui.owner?.avatarUrl
                                                        vm.refresh(showBlockingLoader = false)
                                                        openStrengthActiveWithCountdownPolicy(
                                                            startCtx,
                                                            { showActiveStrength = it },
                                                            { preActiveCountdown = it }
                                                        )
                                                    },
                                                    onFailure = { err ->
                                                        startFailureOffersSolo = true
                                                        startErrorMessage = com.lilru.liftr.workout.WorkoutStartSync.userFacingMessage(err)
                                                    }
                                                )
                                            }
                                        }
                                        startErrorMessage = com.lilru.liftr.workout.WorkoutStartSync.userFacingMessage(e)
                                    }
                                )
                            }
                        },
                        enabled = !dualPrepareBusy,
                        modifier = Modifier.weight(1f)
                    ) { Text(stringResource(R.string.workout_detail_dual_solo)) }
                    Button(
                        onClick = {
                            if (dualPrepareBusy) return@Button
                            if (showsAsGroup) {
                                val picks = ui.participants.filter { dualSheetSelectedIds.contains(it.userId) }
                                if (picks.size < 2) return@Button
                                val a = picks[0]
                                val b = picks[1]
                                dualPrepareBusy = true
                                vm.preparePlannedStrengthTrio(a.userId, b.userId) { r ->
                                    dualPrepareBusy = false
                                    r.fold(
                                        onSuccess = { pair ->
                                            showDualStart = false
                                            dualLinkedGuestWid = pair.first
                                            dualLinkedGuest2Wid = pair.second
                                            dualGuestAvatarUrl = a.avatarUrl
                                            dualGuest2AvatarUrl = b.avatarUrl
                                            dualHostAvatarUrl = ui.owner?.avatarUrl
                                            AppSnackbar.showSuccess(
                                                startCtx.getString(
                                                    R.string.workout_detail_dual_linked_ok,
                                                    pair.first
                                                )
                                            )
                                            vm.refresh(showBlockingLoader = false)
                                            openStrengthActiveWithCountdownPolicy(
                                                startCtx,
                                                { showActiveStrength = it },
                                                { preActiveCountdown = it }
                                            )
                                        },
                                        onFailure = { e ->
                                            startFailureOffersSolo = true
                                            startFailureRetryAction = {
                                                dualPrepareBusy = true
                                                vm.preparePlannedStrengthTrio(a.userId, b.userId) { r2 ->
                                                    dualPrepareBusy = false
                                                    r2.fold(
                                                        onSuccess = { pair ->
                                                            showDualStart = false
                                                            dualLinkedGuestWid = pair.first
                                                            dualLinkedGuest2Wid = pair.second
                                                            dualGuestAvatarUrl = a.avatarUrl
                                                            dualGuest2AvatarUrl = b.avatarUrl
                                                            dualHostAvatarUrl = ui.owner?.avatarUrl
                                                            vm.refresh(showBlockingLoader = false)
                                                            openStrengthActiveWithCountdownPolicy(
                                                                startCtx,
                                                                { showActiveStrength = it },
                                                                { preActiveCountdown = it }
                                                            )
                                                        },
                                                        onFailure = { err ->
                                                            startFailureOffersSolo = true
                                                            startErrorMessage =
                                                                com.lilru.liftr.workout.WorkoutStartSync.userFacingMessage(err)
                                                        }
                                                    )
                                                }
                                            }
                                            startErrorMessage =
                                                com.lilru.liftr.workout.WorkoutStartSync.userFacingMessage(e)
                                        }
                                    )
                                }
                            } else {
                                val pick = solePick ?: return@Button
                                dualPrepareBusy = true
                                vm.preparePlannedStrengthAndLinkedGuest(pick.userId) { r ->
                                    dualPrepareBusy = false
                                    r.fold(
                                        onSuccess = { guestWid ->
                                            showDualStart = false
                                            dualLinkedGuestWid = guestWid
                                            dualLinkedGuest2Wid = null
                                            dualGuestAvatarUrl = pick.avatarUrl
                                            dualGuest2AvatarUrl = null
                                            dualHostAvatarUrl = ui.owner?.avatarUrl
                                            guestWid?.let {
                                                AppSnackbar.showSuccess(
                                                    startCtx.getString(
                                                        R.string.workout_detail_dual_linked_ok,
                                                        it
                                                    )
                                                )
                                            }
                                            vm.refresh(showBlockingLoader = false)
                                            openStrengthActiveWithCountdownPolicy(
                                                startCtx,
                                                { showActiveStrength = it },
                                                { preActiveCountdown = it }
                                            )
                                        },
                                        onFailure = { e ->
                                            startFailureOffersSolo = true
                                            startFailureRetryAction = {
                                                dualPrepareBusy = true
                                                vm.preparePlannedStrengthAndLinkedGuest(pick.userId) { r2 ->
                                                    dualPrepareBusy = false
                                                    r2.fold(
                                                        onSuccess = { guestWid ->
                                                            showDualStart = false
                                                            dualLinkedGuestWid = guestWid
                                                            dualLinkedGuest2Wid = null
                                                            dualGuestAvatarUrl = pick.avatarUrl
                                                            dualGuest2AvatarUrl = null
                                                            dualHostAvatarUrl = ui.owner?.avatarUrl
                                                            vm.refresh(showBlockingLoader = false)
                                                            openStrengthActiveWithCountdownPolicy(
                                                                startCtx,
                                                                { showActiveStrength = it },
                                                                { preActiveCountdown = it }
                                                            )
                                                        },
                                                        onFailure = { err ->
                                                            startFailureOffersSolo = true
                                                            startErrorMessage =
                                                                com.lilru.liftr.workout.WorkoutStartSync.userFacingMessage(err)
                                                        }
                                                    )
                                                }
                                            }
                                            startErrorMessage =
                                                com.lilru.liftr.workout.WorkoutStartSync.userFacingMessage(e)
                                        }
                                    )
                                }
                            }
                        },
                        enabled = !dualPrepareBusy &&
                            (if (showsAsGroup) {
                                ui.participants.count { dualSheetSelectedIds.contains(it.userId) } >= 2
                            } else {
                                solePick != null
                            }),
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            if (showsAsGroup) {
                                stringResource(R.string.workout_detail_sheet_btn_group)
                            } else {
                                stringResource(R.string.workout_detail_sheet_btn_dual)
                            }
                        )
                    }
                }
            }
        }
    }
    if (startErrorMessage != null) {
        AlertDialog(
            onDismissRequest = {
                startErrorMessage = null
                startFailureOffersSolo = false
                startFailureRetryAction = null
            },
            title = { Text(stringResource(R.string.workout_detail_start_failed_title)) },
            text = { Text(startErrorMessage ?: "") },
            confirmButton = {
                if (startFailureOffersSolo) {
                    TextButton(
                        onClick = {
                            startErrorMessage = null
                            startFailureOffersSolo = false
                            startFailureRetryAction = null
                            showDualStart = false
                            dualLinkedGuestWid = null
                            dualLinkedGuest2Wid = null
                            dualGuestAvatarUrl = null
                            dualGuest2AvatarUrl = null
                            com.lilru.liftr.workout.WorkoutStartSync.enqueueStart(startCtx, workoutId)
                            openStrengthActiveWithCountdownPolicy(
                                startCtx,
                                { showActiveStrength = it },
                                { preActiveCountdown = it }
                            )
                        }
                    ) {
                        Text(stringResource(R.string.workout_detail_start_failed_solo))
                    }
                }
                TextButton(
                    onClick = {
                        val retry = startFailureRetryAction
                        startErrorMessage = null
                        startFailureOffersSolo = false
                        startFailureRetryAction = null
                        retry?.invoke()
                    }
                ) {
                    Text(stringResource(R.string.home_retry))
                }
                TextButton(
                    onClick = {
                        startErrorMessage = null
                        startFailureOffersSolo = false
                        startFailureRetryAction = null
                        showDualStart = false
                        dualLinkedGuestWid = null
                        dualLinkedGuest2Wid = null
                        dualGuestAvatarUrl = null
                        dualGuest2AvatarUrl = null
                        com.lilru.liftr.workout.WorkoutStartSync.enqueueStart(startCtx, workoutId)
                        openStrengthActiveWithCountdownPolicy(
                            startCtx,
                            { showActiveStrength = it },
                            { preActiveCountdown = it }
                        )
                    }
                ) {
                    Text(stringResource(R.string.workout_detail_start_failed_offline))
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        startErrorMessage = null
                        startFailureOffersSolo = false
                        startFailureRetryAction = null
                    }
                ) {
                    Text(stringResource(R.string.workout_detail_start_failed_ok))
                }
            }
        )
    }
    if (showCommentsSheet) {
        LaunchedEffect(Unit) { vm.loadCommentFolloweesIfNeeded() }
        ModalBottomSheet(onDismissRequest = { showCommentsSheet = false }) {
            WorkoutDetailCommentsSheetContent(
                comments = ui.comments,
                commentDraft = commentDraft,
                onCommentDraftChange = { commentDraft = it },
                trackedMentions = trackedMentions,
                onTrackedMentionsChange = { trackedMentions = it },
                followees = ui.commentFollowees,
                onRequestFollowees = { vm.loadCommentFolloweesIfNeeded() },
                replyToCommentId = replyToCommentId,
                onCancelReply = { replyToCommentId = null },
                commentBusy = ui.commentBusy,
                onSendComment = {
                    val body = commentDraft.text
                    val mentionIds = CommentMentionSupport.resolvedMentionIds(body, trackedMentions)
                    vm.sendComment(body, parentId = replyToCommentId, mentionedUserIds = mentionIds) {
                        commentDraft = androidx.compose.ui.text.input.TextFieldValue("")
                        trackedMentions = emptyList()
                        replyToCommentId = null
                    }
                },
                commentsCanLoadMore = ui.commentsCanLoadMore,
                commentsLoadingMore = ui.commentsLoadingMore,
                onLoadMore = { vm.loadMoreComments() },
                onToggleLike = { vm.toggleCommentLike(it) },
                onReply = { replyToCommentId = it },
                onDelete = { vm.deleteComment(it) },
                onToggleReplies = { vm.toggleReplies(it) },
                onOpenProfile = { uid ->
                    selectedProfileUserId = uid
                    showCommentsSheet = false
                },
                modifier = Modifier.padding(bottom = 24.dp)
            )
        }
    }
    if (showEditMeta) {
        val wk = ui.workout
        if (wk != null) {
            when (wk.kind?.lowercase()) {
                "cardio" -> {
                    val card = ui.cardioSession
                    if (card == null) {
                        ModalBottomSheet(
                            onDismissRequest = { if (!ui.saveMetaBusy) showEditMeta = false }
                        ) {
                            var title by remember(wk.id, showEditMeta) { mutableStateOf(wk.title.orEmpty()) }
                            var notes by remember(wk.id, showEditMeta) { mutableStateOf(wk.notes.orEmpty()) }
                            var started by remember(wk.id, showEditMeta) { mutableStateOf(wk.startedAt.orEmpty()) }
                            var endedE by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt != null) }
                            var ended by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt.orEmpty()) }
                            var inten by remember(wk.id, showEditMeta) {
                                mutableStateOf(intensityFromServerOrDefault(wk.perceivedIntensity))
                            }
                            EditWorkoutMetaSheetContent(
                                title = title,
                                onTitleChange = { title = it },
                                notes = notes,
                                onNotesChange = { notes = it },
                                startedAtIso = started,
                                onStartedAtChange = { started = it },
                                endedAtEnabled = endedE,
                                onEndedAtEnabledChange = { endedE = it },
                                endedAtIso = ended,
                                onEndedAtChange = { ended = it },
                                intensity = inten,
                                onIntensityChange = { inten = it },
                                saveLabel = stringResource(R.string.edit_workout_meta_save),
                                saving = ui.saveMetaBusy,
                                onSave = {
                                    vm.updateWorkoutMetaCommon(
                                        title = title,
                                        notes = notes,
                                        startedAtIso = started,
                                        endedAtIso = ended,
                                        endedAtEnabled = endedE,
                                        intensity = inten
                                    ) { e -> if (e == null) showEditMeta = false }
                                }
                            )
                        }
                    } else {
                        val sessionKey = card.id
                        val dSec = card.durationSec
                        val dh = dSec?.let { it / 3600 }?.toString().orEmpty()
                        val dm = dSec?.let { (it % 3600) / 60 }?.toString().orEmpty()
                        val ds = dSec?.let { it % 60 }?.toString().orEmpty()
                        val ex = card.extras
                        val actWire = card.activityCode?.ifBlank { null } ?: card.modality?.ifBlank { null } ?: "run"
                        val act0 = AddCardioActivity.entries.firstOrNull { it.wire == actWire } ?: AddCardioActivity.RUN
                        ModalBottomSheet(
                            onDismissRequest = { if (!ui.saveMetaBusy) showEditMeta = false }
                        ) {
                            var title by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.title.orEmpty()) }
                            var notes by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.notes.orEmpty()) }
                            var started by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.startedAt.orEmpty()) }
                            var endedE by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.endedAt != null) }
                            var ended by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.endedAt.orEmpty()) }
                            var inten by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(intensityFromServerOrDefault(wk.perceivedIntensity))
                            }
                            var activity by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(act0) }
                            var dist by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(card.distanceKm?.toString() ?: "")
                            }
                            var durH by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(dh) }
                            var durM by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(dm) }
                            var durS by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(ds) }
                            var avgH by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(card.avgHr?.toString() ?: "") }
                            var maxH by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(card.maxHr?.toString() ?: "") }
                            var pace by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(card.avgPaceSecPerKm?.toString() ?: "")
                            }
                            var elev by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(card.elevationGainM?.toString() ?: "")
                            }
                            var cad by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(ex?.cadenceRpm?.toString() ?: "")
                            }
                            var wat by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(ex?.wattsAvg?.toString() ?: "")
                            }
                            var inc by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(ex?.inclinePct?.toString() ?: "")
                            }
                            var sp500 by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(ex?.splitSecPer500m?.toString() ?: "")
                            }
                            var kmSp by remember(wk.id, sessionKey, showEditMeta) {
                                val arr = ex?.kmSplitPaceSec
                                mutableStateOf(
                                    if (arr != null && arr.isNotEmpty()) arr.joinToString(",") else ""
                                )
                            }
                            var sLap by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(ex?.swimLaps?.toString() ?: "") }
                            var pool by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(ex?.poolLengthM?.toString() ?: "") }
                            var sty by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(ex?.swimStyle.orEmpty()) }
                            EditCardioWorkoutMetaSheetContent(
                                title = title,
                                onTitleChange = { title = it },
                                notes = notes,
                                onNotesChange = { notes = it },
                                startedAtIso = started,
                                onStartedAtChange = { started = it },
                                endedAtEnabled = endedE,
                                onEndedAtEnabledChange = { endedE = it },
                                endedAtIso = ended,
                                onEndedAtChange = { ended = it },
                                intensity = inten,
                                onIntensityChange = { inten = it },
                                activity = activity,
                                onActivityChange = { activity = it },
                                distanceKm = dist,
                                onDistanceKmChange = { dist = it },
                                durH = durH,
                                durM = durM,
                                durS = durS,
                                onDurHChange = { durH = it },
                                onDurMChange = { durM = it },
                                onDurSChange = { durS = it },
                                avgHr = avgH,
                                onAvgHrChange = { avgH = it },
                                maxHr = maxH,
                                onMaxHrChange = { maxH = it },
                                avgPaceSecPerKm = pace,
                                onAvgPaceSecPerKmChange = { pace = it },
                                elevationM = elev,
                                onElevationMChange = { elev = it },
                                cadenceRpm = cad,
                                onCadenceRpmChange = { cad = it },
                                wattsAvg = wat,
                                onWattsAvgChange = { wat = it },
                                inclinePct = inc,
                                onInclinePctChange = { inc = it },
                                splitSecPer500m = sp500,
                                onSplitSecPer500mChange = { sp500 = it },
                                kmSplitsPaceText = kmSp,
                                onKmSplitsPaceTextChange = { kmSp = it },
                                swimLaps = sLap,
                                onSwimLapsChange = { sLap = it },
                                poolLengthM = pool,
                                onPoolLengthMChange = { pool = it },
                                swimStyle = sty,
                                onSwimStyleChange = { sty = it },
                                saveLabel = stringResource(R.string.edit_workout_meta_save),
                                saving = ui.saveMetaBusy,
                                onSave = {
                                    vm.updateCardioWorkoutMeta(
                                        title = title,
                                        notes = notes,
                                        startedAtIso = started,
                                        endedAtIso = ended,
                                        endedAtEnabled = endedE,
                                        intensity = inten,
                                        activity = activity,
                                        distanceKm = dist,
                                        durH = durH,
                                        durM = durM,
                                        durS = durS,
                                        avgHr = avgH,
                                        maxHr = maxH,
                                        avgPaceSecPerKm = pace,
                                        elevationM = elev,
                                        cadenceRpm = cad,
                                        wattsAvg = wat,
                                        inclinePct = inc,
                                        splitSecPer500m = sp500,
                                        kmSplitsPaceText = kmSp,
                                        swimLaps = sLap,
                                        poolLengthM = pool,
                                        swimStyle = sty
                                    ) { e -> if (e == null) showEditMeta = false }
                                }
                            )
                        }
                    }
                }
                "strength" -> {
                    ModalBottomSheet(
                        onDismissRequest = { if (!ui.saveMetaBusy) showEditMeta = false }
                    ) {
                        if (ui.strengthEditExercises.isEmpty()) {
                            var title by remember(wk.id, showEditMeta) { mutableStateOf(wk.title.orEmpty()) }
                            var notes by remember(wk.id, showEditMeta) { mutableStateOf(wk.notes.orEmpty()) }
                            var started by remember(wk.id, showEditMeta) { mutableStateOf(wk.startedAt.orEmpty()) }
                            var endedE by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt != null) }
                            var ended by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt.orEmpty()) }
                            var inten by remember(wk.id, showEditMeta) {
                                mutableStateOf(
                                    intensityFromServerOrDefault(wk.perceivedIntensity)
                                )
                            }
                            EditWorkoutMetaSheetContent(
                                title = title,
                                onTitleChange = { title = it },
                                notes = notes,
                                onNotesChange = { notes = it },
                                startedAtIso = started,
                                onStartedAtChange = { started = it },
                                endedAtEnabled = endedE,
                                onEndedAtEnabledChange = { endedE = it },
                                endedAtIso = ended,
                                onEndedAtChange = { ended = it },
                                intensity = inten,
                                onIntensityChange = { inten = it },
                                saveLabel = stringResource(R.string.edit_workout_meta_save),
                                saving = ui.saveMetaBusy,
                                onSave = {
                                    vm.updateWorkoutMetaCommon(
                                        title = title,
                                        notes = notes,
                                        startedAtIso = started,
                                        endedAtIso = ended,
                                        endedAtEnabled = endedE,
                                        intensity = inten
                                    ) { e -> if (e == null) showEditMeta = false }
                                }
                            )
                        } else {
                            var strengthEx by remember(wk.id, showEditMeta) { mutableStateOf(ui.strengthEditExercises) }
                            var title by remember(wk.id, showEditMeta) { mutableStateOf(wk.title.orEmpty()) }
                            var notes by remember(wk.id, showEditMeta) { mutableStateOf(wk.notes.orEmpty()) }
                            var started by remember(wk.id, showEditMeta) { mutableStateOf(wk.startedAt.orEmpty()) }
                            var endedE by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt != null) }
                            var ended by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt.orEmpty()) }
                            var inten by remember(wk.id, showEditMeta) {
                                mutableStateOf(
                                    intensityFromServerOrDefault(wk.perceivedIntensity)
                                )
                            }
                            EditStrengthWorkoutMetaSheetContent(
                                title = title,
                                onTitleChange = { title = it },
                                notes = notes,
                                onNotesChange = { notes = it },
                                startedAtIso = started,
                                onStartedAtChange = { started = it },
                                endedAtEnabled = endedE,
                                onEndedAtEnabledChange = { endedE = it },
                                endedAtIso = ended,
                                onEndedAtChange = { ended = it },
                                intensity = inten,
                                onIntensityChange = { inten = it },
                                exercises = strengthEx,
                                onExercisesChange = { strengthEx = it },
                                saveLabel = stringResource(R.string.edit_workout_meta_save),
                                saving = ui.saveMetaBusy,
                                onSave = {
                                    vm.saveStrengthWorkoutWithExercises(
                                        title = title,
                                        notes = notes,
                                        startedAtIso = started,
                                        endedAtIso = ended,
                                        endedAtEnabled = endedE,
                                        intensity = inten,
                                        exercises = strengthEx
                                    ) { e -> if (e == null) showEditMeta = false }
                                }
                            )
                        }
                    }
                }
                "sport" -> {
                    val sp = ui.sportSession
                    if (sp == null) {
                        ModalBottomSheet(
                            onDismissRequest = { if (!ui.saveMetaBusy) showEditMeta = false }
                        ) {
                            var title by remember(wk.id, showEditMeta) { mutableStateOf(wk.title.orEmpty()) }
                            var notes by remember(wk.id, showEditMeta) { mutableStateOf(wk.notes.orEmpty()) }
                            var started by remember(wk.id, showEditMeta) { mutableStateOf(wk.startedAt.orEmpty()) }
                            var endedE by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt != null) }
                            var ended by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt.orEmpty()) }
                            var inten by remember(wk.id, showEditMeta) {
                                mutableStateOf(
                                    intensityFromServerOrDefault(wk.perceivedIntensity)
                                )
                            }
                            EditWorkoutMetaSheetContent(
                                title = title,
                                onTitleChange = { title = it },
                                notes = notes,
                                onNotesChange = { notes = it },
                                startedAtIso = started,
                                onStartedAtChange = { started = it },
                                endedAtEnabled = endedE,
                                onEndedAtEnabledChange = { endedE = it },
                                endedAtIso = ended,
                                onEndedAtChange = { ended = it },
                                intensity = inten,
                                onIntensityChange = { inten = it },
                                saveLabel = stringResource(R.string.edit_workout_meta_save),
                                saving = ui.saveMetaBusy,
                                onSave = {
                                    vm.updateWorkoutMetaCommon(
                                        title = title,
                                        notes = notes,
                                        startedAtIso = started,
                                        endedAtIso = ended,
                                        endedAtEnabled = endedE,
                                        intensity = inten
                                    ) { e -> if (e == null) showEditMeta = false }
                                }
                            )
                        }
                    } else {
                        val showMatch = addSportTypeFromWire(sp.sport) != AddSportType.SKI
                        val sessionKey = sp.id
                        ModalBottomSheet(
                            onDismissRequest = { if (!ui.saveMetaBusy) showEditMeta = false }
                        ) {
                            var title by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.title.orEmpty()) }
                            var notes by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.notes.orEmpty()) }
                            var started by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.startedAt.orEmpty()) }
                            var endedE by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.endedAt != null) }
                            var ended by remember(wk.id, sessionKey, showEditMeta) { mutableStateOf(wk.endedAt.orEmpty()) }
                            var inten by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(intensityFromServerOrDefault(wk.perceivedIntensity))
                            }
                            var dur by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(
                                    if (sp.durationSec != null && sp.durationSec > 0) {
                                        ((sp.durationSec + 59) / 60).toString()
                                    } else {
                                        ""
                                    }
                                )
                            }
                            var sFor by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(sp.scoreFor?.toString() ?: "")
                            }
                            var sAga by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(sp.scoreAgainst?.toString() ?: "")
                            }
                            var mRes by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(normalizeSportMatchResult(sp.matchResult))
                            }
                            var mLine by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(sp.matchScoreText.orEmpty())
                            }
                            var loc by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(sp.location.orEmpty())
                            }
                            var sNotes by remember(wk.id, sessionKey, showEditMeta) {
                                mutableStateOf(sp.notes.orEmpty())
                            }
                            EditSportWorkoutMetaSheetContent(
                                sportTypeLabel = formatActivityCodeForDisplay(sp.sport.trim().ifEmpty { "sport" }),
                                showMatchResult = showMatch,
                                title = title,
                                onTitleChange = { title = it },
                                notes = notes,
                                onNotesChange = { notes = it },
                                startedAtIso = started,
                                onStartedAtChange = { started = it },
                                endedAtEnabled = endedE,
                                onEndedAtEnabledChange = { endedE = it },
                                endedAtIso = ended,
                                onEndedAtChange = { ended = it },
                                intensity = inten,
                                onIntensityChange = { inten = it },
                                durationMin = dur,
                                onDurationMinChange = { dur = it },
                                scoreFor = sFor,
                                onScoreForChange = { sFor = it },
                                scoreAgainst = sAga,
                                onScoreAgainstChange = { sAga = it },
                                matchResultRaw = mRes,
                                onMatchResultRawChange = { mRes = it },
                                matchScoreText = mLine,
                                onMatchScoreTextChange = { mLine = it },
                                location = loc,
                                onLocationChange = { loc = it },
                                sessionNotes = sNotes,
                                onSessionNotesChange = { sNotes = it },
                                saveLabel = stringResource(R.string.edit_workout_meta_save),
                                saving = ui.saveMetaBusy,
                                onSave = {
                                    vm.updateSportWorkoutMeta(
                                        title = title,
                                        notes = notes,
                                        startedAtIso = started,
                                        endedAtIso = ended,
                                        endedAtEnabled = endedE,
                                        intensity = inten,
                                        durationMinText = dur,
                                        scoreForText = sFor,
                                        scoreAgainstText = sAga,
                                        matchResultRaw = mRes,
                                        matchScoreText = mLine,
                                        location = loc,
                                        sessionNotes = sNotes
                                    ) { e -> if (e == null) showEditMeta = false }
                                }
                            )
                        }
                    }
                }
                else -> {
                    ModalBottomSheet(
                        onDismissRequest = { if (!ui.saveMetaBusy) showEditMeta = false }
                    ) {
                        var title by remember(wk.id, showEditMeta) { mutableStateOf(wk.title.orEmpty()) }
                        var notes by remember(wk.id, showEditMeta) { mutableStateOf(wk.notes.orEmpty()) }
                        var started by remember(wk.id, showEditMeta) { mutableStateOf(wk.startedAt.orEmpty()) }
                        var endedE by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt != null) }
                        var ended by remember(wk.id, showEditMeta) { mutableStateOf(wk.endedAt.orEmpty()) }
                        var inten by remember(wk.id, showEditMeta) {
                            mutableStateOf(
                                intensityFromServerOrDefault(wk.perceivedIntensity)
                            )
                        }
                        EditWorkoutMetaSheetContent(
                            title = title,
                            onTitleChange = { title = it },
                            notes = notes,
                            onNotesChange = { notes = it },
                            startedAtIso = started,
                            onStartedAtChange = { started = it },
                            endedAtEnabled = endedE,
                            onEndedAtEnabledChange = { endedE = it },
                            endedAtIso = ended,
                            onEndedAtChange = { ended = it },
                            intensity = inten,
                            onIntensityChange = { inten = it },
                            saveLabel = stringResource(R.string.edit_workout_meta_save),
                            saving = ui.saveMetaBusy,
                            onSave = {
                                vm.updateWorkoutMetaCommon(
                                    title = title,
                                    notes = notes,
                                    startedAtIso = started,
                                    endedAtIso = ended,
                                    endedAtEnabled = endedE,
                                    intensity = inten
                                ) { e -> if (e == null) showEditMeta = false }
                            }
                        )
                    }
                }
            }
        }
    }
    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { if (!ui.deleteBusy) showDeleteConfirm = false },
            title = { Text(stringResource(R.string.home_detail_delete_title)) },
            text = { Text(stringResource(R.string.home_detail_delete_message)) },
            confirmButton = {
                TextButton(
                    onClick = { vm.deleteWorkoutAsOwner { onBack() } },
                    enabled = !ui.deleteBusy
                ) { Text(stringResource(R.string.home_detail_delete)) }
            },
            dismissButton = {
                TextButton(
                    onClick = { showDeleteConfirm = false },
                    enabled = !ui.deleteBusy
                ) { Text(stringResource(R.string.add_routine_dialog_cancel)) }
            }
        )
    }
    if (showLikersSheet) {
        ModalBottomSheet(
            onDismissRequest = { showLikersSheet = false }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        stringResource(R.string.home_detail_likes_sheet_title),
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        "${ui.likeCount}",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (ui.likersLoading) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 24.dp),
                        horizontalArrangement = Arrangement.Center
                    ) {
                        CircularProgressIndicator()
                    }
                } else if (ui.likers.isEmpty()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 28.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            stringResource(R.string.home_detail_likes_empty),
                            style = MaterialTheme.typography.titleSmall
                        )
                        Text(
                            stringResource(R.string.home_detail_likes_empty_hint),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                    }
                } else {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(ui.likers, key = { it.userId }) { p ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        selectedProfileUserId = p.userId
                                        showLikersSheet = false
                                    }
                                    .padding(vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                LiftrAvatar(
                                    imageUrl = p.avatarUrl,
                                    displayName = p.username,
                                    size = 36.dp
                                )
                                Text(
                                    p.username?.takeIf { it.isNotBlank() }?.let { "@$it" } ?: p.userId,
                                    style = MaterialTheme.typography.bodyLarge
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    if (showComparePicker) {
        val picker = ui.comparePicker
        val filteredSessions = remember(picker, compareSearchQuery) {
            filterComparePickerSessions(picker, compareSearchQuery)
        }
        val visibleMyAverage = remember(picker, compareSearchQuery, context) {
            picker.myAverage?.takeIf { compareAverageMatchesSearch(it, compareSearchQuery, context) }
        }
        val visibleGlobalAverage = remember(picker, compareSearchQuery, context) {
            picker.globalAverage?.takeIf { compareAverageMatchesSearch(it, compareSearchQuery, context) }
        }
        val showAverageCtas = visibleMyAverage != null || visibleGlobalAverage != null
        val showEmptySearch = compareSearchQuery.isNotBlank() && !showAverageCtas && filteredSessions.isEmpty()
        ModalBottomSheet(
            onDismissRequest = { showComparePicker = false }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp)
            ) {
                Text(
                    stringResource(R.string.home_detail_compare_picker_title),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(bottom = 12.dp)
                )
                if (showAverageCtas) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        visibleMyAverage?.let { option ->
                            CompareAverageCtaCard(
                                option = option,
                                modifier = Modifier.weight(1f),
                                onClick = {
                                    applyCompareTarget(
                                        CompareOtherTarget.Average(
                                            option.scope,
                                            option.workoutIds,
                                            option.sampleCount
                                        ),
                                        context,
                                        onWorkoutId = {
                                            compareOtherId = it
                                            compareAverageScope = null
                                        },
                                        onAverageScope = { compareAverageScope = it },
                                        onAverageLabel = { compareAverageRightLabel = it }
                                    )
                                    showComparePicker = false
                                    showCompare = true
                                }
                            )
                        }
                        visibleGlobalAverage?.let { option ->
                            CompareAverageCtaCard(
                                option = option,
                                modifier = Modifier.weight(1f),
                                onClick = {
                                    applyCompareTarget(
                                        CompareOtherTarget.Average(
                                            option.scope,
                                            option.workoutIds,
                                            option.sampleCount
                                        ),
                                        context,
                                        onWorkoutId = {
                                            compareOtherId = it
                                            compareAverageScope = null
                                        },
                                        onAverageScope = { compareAverageScope = it },
                                        onAverageLabel = { compareAverageRightLabel = it }
                                    )
                                    showComparePicker = false
                                    showCompare = true
                                }
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = compareSearchQuery,
                    onValueChange = { compareSearchQuery = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 8.dp),
                    singleLine = true,
                    label = { Text(stringResource(R.string.home_detail_compare_search_hint)) },
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        imeAction = ImeAction.Search
                    )
                )
                if (showEmptySearch) {
                    Text(
                        stringResource(R.string.home_detail_compare_search_no_matches),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 16.dp)
                    )
                } else {
                    if (filteredSessions.isNotEmpty()) {
                        Text(
                            stringResource(R.string.compare_average_picker_sessions),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(bottom = 6.dp)
                        )
                    }
                    LazyColumn(
                        modifier = Modifier.weight(1f, fill = false),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        items(filteredSessions, key = { it.id }) { c ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        compareOtherId = c.id
                                        compareAverageScope = null
                                        compareAverageRightLabel = null
                                        showComparePicker = false
                                        showCompare = true
                                    }
                                    .padding(vertical = 8.dp, horizontal = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        c.displayTitle,
                                        style = MaterialTheme.typography.bodyLarge
                                    )
                                    val sub = c.ownerUsername?.let { "@$it" }
                                    if (sub != null) {
                                        Text(
                                            sub,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CompareAverageCtaCard(
    option: CompareAverageOption,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val title = averagePickerTitle(option, context)
    val icon = when (option.scope) {
        CompareAverageScope.MINE -> Icons.Filled.Person
        CompareAverageScope.GLOBAL -> Icons.Filled.Public
    }
    Surface(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
        tonalElevation = 2.dp
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    modifier = Modifier.padding(top = 1.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Text(
                    title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1
                )
            }
            Text(
                option.typeLabel,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1
            )
            Text(
                stringResource(R.string.compare_average_sample_short, option.sampleCount),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            )
        }
    }
}

private fun shouldShowComparePicker(picker: ComparePickerState): Boolean {
    val avgCount = (if (picker.myAverage != null) 1 else 0) +
        (if (picker.globalAverage != null) 1 else 0)
    return picker.sessions.size + avgCount > 1
}

private fun singleCompareTarget(picker: ComparePickerState): CompareOtherTarget? {
    val options = buildList {
        picker.myAverage?.let {
            add(CompareOtherTarget.Average(it.scope, it.workoutIds, it.sampleCount))
        }
        picker.globalAverage?.let {
            add(CompareOtherTarget.Average(it.scope, it.workoutIds, it.sampleCount))
        }
        picker.sessions.forEach { add(CompareOtherTarget.Workout(it.id)) }
    }
    return options.singleOrNull()
}

private fun resolveCompareTarget(
    workoutId: Int?,
    averageScope: String?,
    picker: ComparePickerState
): CompareOtherTarget? {
    if (averageScope != null) {
        val opt = when (averageScope) {
            "mine" -> picker.myAverage
            "global" -> picker.globalAverage
            else -> null
        }
        return opt?.let {
            CompareOtherTarget.Average(it.scope, it.workoutIds, it.sampleCount)
        }
    }
    return workoutId?.let { CompareOtherTarget.Workout(it) }
}

private fun applyCompareTarget(
    target: CompareOtherTarget,
    context: Context,
    onWorkoutId: (Int) -> Unit,
    onAverageScope: (String) -> Unit,
    onAverageLabel: (String) -> Unit
) {
    when (target) {
        is CompareOtherTarget.Workout -> onWorkoutId(target.id)
        is CompareOtherTarget.Average -> {
            onAverageScope(
                when (target.scope) {
                    CompareAverageScope.MINE -> "mine"
                    CompareAverageScope.GLOBAL -> "global"
                }
            )
            onAverageLabel(averageCompareRightLabel(context, target))
        }
    }
}

private fun averageCompareRightLabel(
    context: Context,
    target: CompareOtherTarget.Average
): String {
    val title = when (target.scope) {
        CompareAverageScope.MINE -> context.getString(R.string.compare_average_mine)
        CompareAverageScope.GLOBAL -> context.getString(R.string.compare_average_global)
    }
    return "$title (${target.sampleCount})"
}

private fun averagePickerTitle(option: CompareAverageOption, context: Context): String =
    when (option.scope) {
        CompareAverageScope.MINE -> context.getString(R.string.compare_average_mine)
        CompareAverageScope.GLOBAL -> context.getString(R.string.compare_average_global)
    }

private fun compareAverageMatchesSearch(
    option: CompareAverageOption,
    query: String,
    context: Context
): Boolean {
    val q = query.trim()
    if (q.isEmpty()) return true
    return averagePickerTitle(option, context).contains(q, ignoreCase = true) ||
        option.typeLabel.contains(q, ignoreCase = true)
}

private fun filterComparePickerSessions(
    picker: ComparePickerState,
    query: String
): List<CompareWorkoutCandidate> {
    val q = query.trim()
    if (q.isEmpty()) return picker.sessions
    return picker.sessions.filter { c ->
        c.displayTitle.contains(q, ignoreCase = true) ||
            c.ownerUsername?.contains(q, ignoreCase = true) == true ||
            c.startedAtIso.contains(q, ignoreCase = true)
    }
}

/**
 * Abre [ActiveStrengthWorkoutScreen] con la misma regla de cuenta atrás que el resto de entradas
 * (p. ej. *planned* dual tras `preparePlannedStrengthAndLinkedGuest` — ver `ADD_WORKOUT_PARITY.md`
 * sección *Cuenta atrás*).
 */
private fun openStrengthActiveWithCountdownPolicy(
    context: Context,
    setShowStrength: (Boolean) -> Unit,
    setPreActive: (PreActiveKind?) -> Unit
) {
    if (LiftrPreferences.skipStartCountdown(context)) {
        setShowStrength(true)
    } else {
        setPreActive(PreActiveKind.Strength)
    }
}

/**
 * Entradas a la cuenta atrás (mapa; todas en [WorkoutDetailScreen]):
 * - **Start** principal (`canStartStrength|Cardio|Sport` → [PreActiveKind] → [StartWorkoutCountdownScreen]).
 * - **Planned + dual** (diálogo): fuerza, misma política vía [openStrengthActiveWithCountdownPolicy].
 *
 * Ninguna otra pantalla compone [Active*WorkoutScreen] directamente; reanudar desde FGS/overlay vuelve al
 * detalle y el usuario pulsa *Start* otra vez (nueva cuenta atrás salvo [LiftrPreferences.skipStartCountdown]).
 */
private fun openPreActiveOrActive(
    canStartStrength: Boolean,
    canStartCardio: Boolean,
    canStartSport: Boolean,
    skipCountdown: Boolean,
    setPreActive: (PreActiveKind?) -> Unit,
    setShowStrength: (Boolean) -> Unit,
    setShowCardio: (Boolean) -> Unit,
    setShowSport: (Boolean) -> Unit
) {
    if (skipCountdown) {
        when {
            canStartStrength -> setShowStrength(true)
            canStartCardio -> setShowCardio(true)
            canStartSport -> setShowSport(true)
        }
    } else {
        setPreActive(
            when {
                canStartStrength -> PreActiveKind.Strength
                canStartCardio -> PreActiveKind.Cardio
                canStartSport -> PreActiveKind.Sport
                else -> null
            }
        )
    }
}

