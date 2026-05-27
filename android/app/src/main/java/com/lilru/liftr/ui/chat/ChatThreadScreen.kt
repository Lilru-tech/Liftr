package com.lilru.liftr.ui.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Reply
import androidx.compose.material.icons.filled.Send
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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.filled.Check
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.launch
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import com.lilru.liftr.ui.achievements.AchievementsScreen
import com.lilru.liftr.ui.segment.SegmentDetailScreen
import android.text.format.DateUtils
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ChatThreadScreen(
    supabase: SupabaseClient,
    conversationId: Long,
    otherProfile: ProfileLite?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val viewModel: ChatThreadViewModel = viewModel(
        factory = ChatThreadViewModelFactory(supabase, conversationId)
    )
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val meId = remember { supabase.auth.currentUserOrNull()?.id }
    val ctx = LocalContext.current
    var showMenu by remember { mutableStateOf(false) }
    var showClearConfirm by remember { mutableStateOf(false) }
    var sharedRoutine by remember { mutableStateOf<RoutineShareSnapshot?>(null) }
    var sharedAchievementCode by remember { mutableStateOf<String?>(null) }
    var sharedSegmentId by remember { mutableStateOf<UUID?>(null) }
    var sharedIngredientDetail by remember { mutableStateOf<SharedIngredientSnapshot?>(null) }
    var sharedRecipeDetail by remember { mutableStateOf<SharedRecipeSnapshot?>(null) }
    var sharedDetailSaving by remember { mutableStateOf(false) }

    LaunchedEffect(conversationId) {
        viewModel.loadInitial()
        viewModel.startRealtime()
    }

    LaunchedEffect(state.messages.size) {
        if (state.messages.isNotEmpty()) {
            listState.animateScrollToItem(state.messages.size - 1)
        }
    }

    LaunchedEffect(state.error) {
        val msg = state.error ?: return@LaunchedEffect
        scope.launch {
            snackbar.showSnackbar(msg)
            viewModel.clearError()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
    Scaffold(
        modifier = Modifier.fillMaxSize(),
        containerColor = Color.Transparent,
        topBar = {
            TopAppBar(
                title = {
                    Text(otherProfile?.let { "@${it.username}" } ?: "Conversation")
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.setMuted(!state.muted) }) {
                        Icon(
                            if (state.muted) Icons.Filled.NotificationsOff
                            else Icons.Filled.Notifications,
                            contentDescription = if (state.muted) "Unmute" else "Mute"
                        )
                    }
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "More")
                    }
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("Clear conversation") },
                            onClick = {
                                showMenu = false
                                showClearConfirm = true
                            },
                            leadingIcon = {
                                Icon(Icons.Filled.Delete, contentDescription = null)
                            }
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent
                )
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            ChatComposer(
                draft = state.draft,
                onDraftChange = viewModel::setDraft,
                replyingTo = state.replyingTo,
                editingMessage = state.editingMessage,
                onCancelReply = viewModel::cancelReply,
                onCancelEdit = viewModel::cancelEdit,
                onSend = viewModel::send,
                onSave = viewModel::submitEdit
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            if (state.loading && state.messages.isEmpty()) {
                CircularProgressIndicator(Modifier.align(Alignment.Center))
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (state.hasMore) {
                        item("loadOlder") {
                            LaunchedEffect(state.messages.firstOrNull()?.id) {
                                viewModel.loadOlderIfNeeded()
                            }
                            Box(
                                modifier = Modifier.fillMaxWidth(),
                                contentAlignment = Alignment.Center
                            ) {
                                if (state.loadingOlder) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.padding(8.dp)
                                    )
                                }
                            }
                        }
                    }

                    val items = buildThreadItems(state, meId)
                    items.forEach { item ->
                        when (item) {
                            is ThreadItem.Day -> item("day-${item.label}-${item.afterMessageId}") {
                                DaySeparator(text = item.label)
                            }
                            is ThreadItem.Message -> item(item.message.id) {
                                MessageRow(
                                    msg = item.message,
                                    mine = item.message.userId == meId,
                                    isLastSeenMine = item.isLastSeenMine,
                                    reactions = state.reactionsByMessageId[item.message.id].orEmpty(),
                                    replyTarget = item.message.replyToMessageId
                                        ?.let { state.replyTargetsById[it] },
                                    myUserId = meId,
                                    onDoubleTap = {
                                        if (item.message.id > 0 && item.message.deletedAt == null) {
                                            viewModel.toggleReaction(item.message.id, ReactionEmoji.HEART)
                                        }
                                    },
                                    onLongPress = {
                                        if (item.message.id > 0 && item.message.deletedAt == null) {
                                            viewModel.showActionSheet(item.message)
                                        }
                                    },
                                    onReactionTap = { e ->
                                        viewModel.toggleReaction(item.message.id, e)
                                    },
                                    onOpenRoutineShare = { snap -> sharedRoutine = snap },
                                    onOpenWorkoutShare = { w ->
                                        AppNavEvents.send(
                                            MainOverlay.WorkoutDetail(
                                                w.workoutId.toInt(),
                                                w.ownerUserId
                                            )
                                        )
                                    },
                                    onOpenAchievementShare = { code ->
                                        sharedAchievementCode = code
                                    },
                                    onOpenSegmentShare = { segmentUuid ->
                                        sharedSegmentId = segmentUuid
                                    },
                                    onSaveSharedIngredient = { snap ->
                                        sharedIngredientDetail = snap
                                    },
                                    onSaveSharedRecipe = { snap ->
                                        sharedRecipeDetail = snap
                                    }
                                )
                            }
                        }
                    }
                    if (state.typingUserIds.isNotEmpty()) {
                        item("typing") {
                            Text(
                                text = "${otherProfile?.let { "@${it.username}" } ?: "User"} is typing…",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(start = 8.dp, top = 4.dp)
                            )
                        }
                    }
                }
            }
        }
    }

    state.actionSheetMessage?.let { target ->
        MessageActionSheet(
            message = target,
            mine = target.userId == meId,
            onDismiss = viewModel::dismissActionSheet,
            onReact = { e -> viewModel.toggleReaction(target.id, e) },
            onReply = { viewModel.startReply(target) },
            onCopy = {
                copyToClipboard(ctx, target.clipboardTextForCopy())
            },
            onEdit = { viewModel.startEdit(target) },
            onDelete = { viewModel.deleteMessage(target.id) }
        )
    }

    if (showClearConfirm) {
        AlertDialog(
            onDismissRequest = { showClearConfirm = false },
            confirmButton = {
                TextButton(onClick = {
                    showClearConfirm = false
                    viewModel.clearConversation { onBack() }
                }) { Text("Clear") }
            },
            dismissButton = {
                TextButton(onClick = { showClearConfirm = false }) { Text("Cancel") }
            },
            title = { Text("Clear conversation?") },
            text = {
                Text(
                    "This will hide all messages so far for you. New messages will still arrive."
                )
            }
        )
    }

        sharedRoutine?.let { snap ->
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = MaterialTheme.colorScheme.surface
            ) {
                SharedRoutineFromChatScreen(
                    supabase = supabase,
                    snapshot = snap,
                    onBack = { sharedRoutine = null },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }

        val achievementCode = sharedAchievementCode
        val meForAchievement = supabase.auth.currentUserOrNull()?.id
        if (achievementCode != null && meForAchievement != null) {
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = MaterialTheme.colorScheme.surface
            ) {
                AchievementsScreen(
                    supabase = supabase,
                    targetUserId = meForAchievement,
                    viewedUsername = "",
                    fromNotification = false,
                    initialOpenAchievementCode = achievementCode,
                    onBack = { sharedAchievementCode = null },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }

        sharedSegmentId?.let { sid ->
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = MaterialTheme.colorScheme.surface
            ) {
                SegmentDetailScreen(
                    supabase = supabase,
                    segmentId = sid,
                    onBack = { sharedSegmentId = null },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }

        if (sharedIngredientDetail != null || sharedRecipeDetail != null) {
            val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
            ModalBottomSheet(
                onDismissRequest = {
                    if (!sharedDetailSaving) {
                        sharedIngredientDetail = null
                        sharedRecipeDetail = null
                    }
                },
                sheetState = sheetState
            ) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    sharedIngredientDetail?.let { snap ->
                        Text("Ingredient", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text(snap.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                        Text(
                            "${snap.caloriesPer100g.roundToInt()} kcal · P ${snap.proteinPer100g.roundToInt()}g · C ${snap.carbsPer100g.roundToInt()}g · F ${snap.fatPer100g.roundToInt()}g (per 100g)",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        SharedNutritionDetailFacts(
                            lines = listOf(
                                "Calories" to "${snap.caloriesPer100g}",
                                "Protein (g)" to "${snap.proteinPer100g}",
                                "Carbs (g)" to "${snap.carbsPer100g}",
                                "Fat (g)" to "${snap.fatPer100g}",
                                "Saturated fat (g)" to "${snap.saturatedFatPer100g}",
                                "Sugars (g)" to "${snap.sugarsPer100g}",
                                "Fiber (g)" to "${snap.fiberPer100g}",
                                "Sodium (mg)" to "${snap.sodiumMgPer100g}"
                            )
                        )
                        Button(
                            onClick = {
                                if (sharedDetailSaving) return@Button
                                sharedDetailSaving = true
                                scope.launch {
                                    runCatching { viewModel.cloneSharedIngredient(snap) }
                                        .onSuccess {
                                            snackbar.showSnackbar("Saved to your ingredients")
                                            sharedIngredientDetail = null
                                            sharedRecipeDetail = null
                                        }
                                        .onFailure { e ->
                                            snackbar.showSnackbar(e.message ?: "Couldn't save")
                                        }
                                    sharedDetailSaving = false
                                }
                            },
                            enabled = !sharedDetailSaving,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            if (sharedDetailSaving) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            else Text("Save to My Ingredients")
                        }
                    }

                    sharedRecipeDetail?.let { snap ->
                        Text("Recipe", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text(snap.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                        snap.description?.takeIf { it.isNotBlank() }?.let { d ->
                            Text(d, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        val profile = snap.profilePer100g
                        val line = if (profile != null) {
                            "${profile.calories.roundToInt()} kcal · P ${profile.protein.roundToInt()}g · C ${profile.carbs.roundToInt()}g · F ${profile.fat.roundToInt()}g (per 100g)"
                        } else {
                            "${snap.ingredients.size} ingredients"
                        }
                        Text(line, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Button(
                            onClick = {
                                if (sharedDetailSaving) return@Button
                                sharedDetailSaving = true
                                scope.launch {
                                    runCatching { viewModel.cloneSharedRecipe(snap) }
                                        .onSuccess {
                                            snackbar.showSnackbar("Saved to your recipes")
                                            sharedIngredientDetail = null
                                            sharedRecipeDetail = null
                                        }
                                        .onFailure { e ->
                                            snackbar.showSnackbar(e.message ?: "Couldn't save")
                                        }
                                    sharedDetailSaving = false
                                }
                            },
                            enabled = !sharedDetailSaving,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            if (sharedDetailSaving) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            else Text("Save to My Recipes")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SharedNutritionDetailFacts(lines: List<Pair<String, String>>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        lines.forEach { (k, v) ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(k, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(v, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

// MARK: - Items / day separators

private sealed interface ThreadItem {
    data class Day(val label: String, val afterMessageId: Long?) : ThreadItem
    data class Message(
        val message: ChatMessageWire,
        val isLastSeenMine: Boolean
    ) : ThreadItem
}

private fun buildThreadItems(state: ChatThreadUiState, meId: String?): List<ThreadItem> {
    if (state.messages.isEmpty()) return emptyList()
    val out = mutableListOf<ThreadItem>()
    var prevDay: LocalDate? = null
    val peerLast = state.peerLastReadMessageId
    val lastSeenMineId: Long? = if (meId != null && peerLast != null) {
        state.messages
            .filter { it.userId == meId && it.id > 0 && it.id <= peerLast }
            .maxByOrNull { it.id }?.id
    } else null

    for (msg in state.messages) {
        val day = parseDate(msg.createdAt)
        if (day != null && prevDay != day) {
            out.add(ThreadItem.Day(daySeparatorText(day), msg.id))
            prevDay = day
        }
        out.add(ThreadItem.Message(msg, isLastSeenMine = msg.id == lastSeenMineId))
    }
    return out
}

private fun parseDate(iso: String): LocalDate? = runCatching {
    OffsetDateTime.parse(iso, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toLocalDate()
}.getOrNull()

private fun daySeparatorText(date: LocalDate): String {
    val today = LocalDate.now()
    return when {
        date == today -> "Today"
        date == today.minusDays(1) -> "Yesterday"
        date.year == today.year -> date.format(DateTimeFormatter.ofPattern("d MMM"))
        else -> date.format(DateTimeFormatter.ofPattern("d MMM yyyy"))
    }
}

@Composable
private fun DaySeparator(text: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.5f), CircleShape)
                .padding(horizontal = 12.dp, vertical = 4.dp)
        )
    }
}

private fun routineShareUpdatedRelativeLabel(iso: String?): String? {
    if (iso.isNullOrBlank()) return null
    val ms = runCatching {
        OffsetDateTime.parse(iso, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
            .atZoneSameInstant(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
    }.recoverCatching {
        Instant.parse(iso).toEpochMilli()
    }.getOrNull() ?: return null
    return DateUtils.getRelativeTimeSpanString(
        ms,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS
    ).toString()
}

@Composable
private fun RoutineShareCardMetaLines(snapshot: RoutineShareSnapshot) {
    val onVar = MaterialTheme.colorScheme.onSurfaceVariant
    snapshot.exerciseCount?.takeIf { it > 0 }?.let { n ->
        val text = if (snapshot.routineKind == "hyrox") {
            stringResource(R.string.shared_routine_stations_count, n)
        } else {
            stringResource(R.string.shared_routine_exercises_count, n)
        }
        Text(text, style = MaterialTheme.typography.bodySmall, color = onVar)
    }
    snapshot.totalSets?.takeIf { it > 0 && snapshot.routineKind == "strength" }?.let { ts ->
        Text(
            stringResource(R.string.shared_routine_total_sets_count, ts),
            style = MaterialTheme.typography.bodySmall,
            color = onVar
        )
    }
    snapshot.previewExerciseName?.trim()?.takeIf { it.isNotEmpty() }?.let { p ->
        Text(
            p,
            style = MaterialTheme.typography.bodySmall,
            color = onVar,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
    routineShareUpdatedRelativeLabel(snapshot.updatedAt)?.let { rel ->
        Text(
            stringResource(R.string.chat_routine_share_updated, rel),
            style = MaterialTheme.typography.labelSmall,
            color = onVar
        )
    }
}

// MARK: - Message bubble

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageRow(
    msg: ChatMessageWire,
    mine: Boolean,
    isLastSeenMine: Boolean,
    reactions: List<ReactionWire>,
    replyTarget: ReplyPreviewWire?,
    myUserId: String?,
    onDoubleTap: () -> Unit,
    onLongPress: () -> Unit,
    onReactionTap: (ReactionEmoji) -> Unit,
    onOpenRoutineShare: (RoutineShareSnapshot) -> Unit,
    onOpenWorkoutShare: (WorkoutShareSnapshot) -> Unit,
    onOpenAchievementShare: (String) -> Unit,
    onOpenSegmentShare: (UUID) -> Unit,
    onSaveSharedIngredient: (SharedIngredientSnapshot) -> Unit,
    onSaveSharedRecipe: (SharedRecipeSnapshot) -> Unit
) {
    val deleted = msg.deletedAt != null
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start
    ) {
        Column(
            horizontalAlignment = if (mine) Alignment.End else Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(2.dp),
            modifier = Modifier.widthIn(max = 320.dp)
        ) {
            replyTarget?.let { target ->
                ReplyChip(target = target, mine = mine)
            }

            Surface(
                color = when {
                    deleted -> MaterialTheme.colorScheme.surfaceVariant
                    mine -> MaterialTheme.colorScheme.primary
                    else -> MaterialTheme.colorScheme.surfaceVariant
                },
                shape = RoundedCornerShape(18.dp),
                modifier = Modifier
                    .combinedClickable(
                        onClick = {},
                        onDoubleClick = onDoubleTap,
                        onLongClick = onLongPress
                    )
            ) {
                if (deleted) {
                    Text(
                        text = "Message deleted",
                        fontStyle = FontStyle.Italic,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        style = MaterialTheme.typography.bodyMedium
                    )
                } else {
                    val routineSnap = msg.decodeRoutineShare()
                    val workoutSnap = msg.decodeWorkoutShare()
                    val achievementSnap = msg.decodeAchievementShare()
                    val segmentSnap = msg.decodeSegmentShare()
                    val sharedIngredientSnap = msg.decodeSharedIngredient()
                    val sharedRecipeSnap = msg.decodeSharedRecipe()
                    when {
                        routineSnap != null -> {
                            Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                                if (!msg.body.isNullOrBlank()) {
                                    Text(
                                        text = msg.body.orEmpty(),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = if (mine) MaterialTheme.colorScheme.onPrimary
                                        else MaterialTheme.colorScheme.onSurface,
                                        modifier = Modifier.padding(bottom = 6.dp)
                                    )
                                }
                                val kindLabel = if (routineSnap.routineKind == "hyrox") {
                                    stringResource(R.string.chat_share_routine_card_hyrox)
                                } else {
                                    stringResource(R.string.chat_share_routine_card_strength)
                                }
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f),
                                    modifier = Modifier.clickable { onOpenRoutineShare(routineSnap) }
                                ) {
                                    Row(
                                        Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                                        verticalAlignment = Alignment.Top,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        LiftrAvatar(
                                            imageUrl = routineSnap.ownerAvatarUrl,
                                            displayName = routineSnap.ownerUsername,
                                            size = 36.dp
                                        )
                                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                            routineSnap.ownerUsername?.takeIf { it.isNotBlank() }?.let { u ->
                                                val handle = if (u.startsWith("@")) u else "@$u"
                                                Text(
                                                    text = handle,
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
                                                    else MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                            Text(
                                                text = kindLabel,
                                                style = MaterialTheme.typography.labelSmall,
                                                color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f)
                                                else MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                            Text(
                                                text = routineSnap.name,
                                                style = MaterialTheme.typography.titleSmall,
                                                color = if (mine) MaterialTheme.colorScheme.onPrimary
                                                else MaterialTheme.colorScheme.onSurface
                                            )
                                            RoutineShareCardMetaLines(routineSnap)
                                        }
                                    }
                                }
                            }
                        }
                        workoutSnap != null -> {
                            Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                                if (!msg.body.isNullOrBlank()) {
                                    Text(
                                        text = msg.body.orEmpty(),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = if (mine) MaterialTheme.colorScheme.onPrimary
                                        else MaterialTheme.colorScheme.onSurface,
                                        modifier = Modifier.padding(bottom = 6.dp)
                                    )
                                }
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f),
                                    modifier = Modifier.clickable {
                                        onOpenWorkoutShare(workoutSnap)
                                    }
                                ) {
                                    Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                                        Text(
                                            text = stringResource(R.string.chat_share_workout_card),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f)
                                            else MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                        Text(
                                            text = workoutSnap.title?.takeIf { it.isNotBlank() }
                                                ?: stringResource(R.string.chat_share_workout_card),
                                            style = MaterialTheme.typography.titleSmall,
                                            color = if (mine) MaterialTheme.colorScheme.onPrimary
                                            else MaterialTheme.colorScheme.onSurface
                                        )
                                    }
                                }
                            }
                        }
                        achievementSnap != null -> {
                            Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                                if (!msg.body.isNullOrBlank()) {
                                    Text(
                                        text = msg.body.orEmpty(),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = if (mine) MaterialTheme.colorScheme.onPrimary
                                        else MaterialTheme.colorScheme.onSurface,
                                        modifier = Modifier.padding(bottom = 6.dp)
                                    )
                                }
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f),
                                    modifier = Modifier.clickable { onOpenAchievementShare(achievementSnap.code) }
                                ) {
                                    Row(
                                        Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                                        verticalAlignment = Alignment.Top,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        LiftrAvatar(
                                            imageUrl = achievementSnap.ownerAvatarUrl,
                                            displayName = achievementSnap.ownerUsername,
                                            size = 36.dp
                                        )
                                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                            achievementSnap.ownerUsername?.takeIf { it.isNotBlank() }?.let { u ->
                                                val handle = if (u.startsWith("@")) u else "@$u"
                                                Text(
                                                    text = handle,
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
                                                    else MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                            Text(
                                                text = stringResource(R.string.chat_share_achievement_card),
                                                style = MaterialTheme.typography.labelSmall,
                                                color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f)
                                                else MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                            Text(
                                                text = achievementSnap.title,
                                                style = MaterialTheme.typography.titleSmall,
                                                color = if (mine) MaterialTheme.colorScheme.onPrimary
                                                else MaterialTheme.colorScheme.onSurface
                                            )
                                            Text(
                                                text = achievementSnap.category,
                                                style = MaterialTheme.typography.labelSmall,
                                                color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f)
                                                else MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        segmentSnap != null -> {
                            Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                                if (!msg.body.isNullOrBlank()) {
                                    Text(
                                        text = msg.body.orEmpty(),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = if (mine) MaterialTheme.colorScheme.onPrimary
                                        else MaterialTheme.colorScheme.onSurface,
                                        modifier = Modifier.padding(bottom = 6.dp)
                                    )
                                }
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f),
                                    modifier = Modifier.clickable {
                                        runCatching { UUID.fromString(segmentSnap.segmentId) }
                                            .getOrNull()
                                            ?.let { onOpenSegmentShare(it) }
                                    }
                                ) {
                                    Row(
                                        Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                                        verticalAlignment = Alignment.Top,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        LiftrAvatar(
                                            imageUrl = segmentSnap.ownerAvatarUrl,
                                            displayName = segmentSnap.ownerUsername,
                                            size = 36.dp
                                        )
                                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                            segmentSnap.ownerUsername?.takeIf { it.isNotBlank() }?.let { u ->
                                                val handle = if (u.startsWith("@")) u else "@$u"
                                                Text(
                                                    text = handle,
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
                                                    else MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                            Text(
                                                text = stringResource(R.string.chat_share_segment_card),
                                                style = MaterialTheme.typography.labelSmall,
                                                color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f)
                                                else MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                            Text(
                                                text = segmentSnap.name,
                                                style = MaterialTheme.typography.titleSmall,
                                                color = if (mine) MaterialTheme.colorScheme.onPrimary
                                                else MaterialTheme.colorScheme.onSurface
                                            )
                                            segmentSnap.segmentLengthM?.takeIf { it > 0 }?.let { len ->
                                                Text(
                                                    text = stringResource(
                                                        R.string.chat_segment_share_length_m,
                                                        len.toInt()
                                                    ),
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f)
                                                    else MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                            segmentSnap.leaderboardEffortCount?.takeIf { it > 0 }?.let { n ->
                                                Text(
                                                    text = stringResource(R.string.chat_segment_share_efforts, n.toInt()),
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f)
                                                    else MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        sharedIngredientSnap != null -> {
                            Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                                if (!msg.body.isNullOrBlank()) {
                                    Text(
                                        text = msg.body.orEmpty(),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = if (mine) MaterialTheme.colorScheme.onPrimary
                                        else MaterialTheme.colorScheme.onSurface,
                                        modifier = Modifier.padding(bottom = 6.dp)
                                    )
                                }
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f),
                                    modifier = Modifier.clickable { onSaveSharedIngredient(sharedIngredientSnap) }
                                ) {
                                    Column(
                                        Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                                        verticalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Text(
                                            text = "Ingredient",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f)
                                            else MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                        Text(
                                            text = sharedIngredientSnap.name,
                                            style = MaterialTheme.typography.titleSmall,
                                            color = if (mine) MaterialTheme.colorScheme.onPrimary
                                            else MaterialTheme.colorScheme.onSurface
                                        )
                                        val c = sharedIngredientSnap.caloriesPer100g.roundToInt()
                                        val p = sharedIngredientSnap.proteinPer100g.roundToInt()
                                        val ca = sharedIngredientSnap.carbsPer100g.roundToInt()
                                        val f = sharedIngredientSnap.fatPer100g.roundToInt()
                                        Text(
                                            text = "$c kcal · P ${p}g · C ${ca}g · F ${f}g",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
                                            else MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                        }
                        sharedRecipeSnap != null -> {
                            Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                                if (!msg.body.isNullOrBlank()) {
                                    Text(
                                        text = msg.body.orEmpty(),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = if (mine) MaterialTheme.colorScheme.onPrimary
                                        else MaterialTheme.colorScheme.onSurface,
                                        modifier = Modifier.padding(bottom = 6.dp)
                                    )
                                }
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f),
                                    modifier = Modifier.clickable { onSaveSharedRecipe(sharedRecipeSnap) }
                                ) {
                                    Column(
                                        Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                                        verticalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Text(
                                            text = "Recipe",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f)
                                            else MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                        Text(
                                            text = sharedRecipeSnap.name,
                                            style = MaterialTheme.typography.titleSmall,
                                            color = if (mine) MaterialTheme.colorScheme.onPrimary
                                            else MaterialTheme.colorScheme.onSurface
                                        )
                                        val profile = sharedRecipeSnap.profilePer100g
                                        val line = if (profile != null) {
                                            val c = profile.calories.roundToInt()
                                            val p = profile.protein.roundToInt()
                                            val ca = profile.carbs.roundToInt()
                                            val f = profile.fat.roundToInt()
                                            "$c kcal · P ${p}g · C ${ca}g · F ${f}g"
                                        } else {
                                            "${sharedRecipeSnap.ingredients.size} ingredients"
                                        }
                                        Text(
                                            text = line,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = if (mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
                                            else MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                        }
                        ChatKind.fromRaw(msg.kind) == ChatKind.ROUTINE_SHARE ||
                            ChatKind.fromRaw(msg.kind) == ChatKind.WORKOUT_SHARE ||
                            ChatKind.fromRaw(msg.kind) == ChatKind.ACHIEVEMENT_SHARE ||
                            ChatKind.fromRaw(msg.kind) == ChatKind.SEGMENT_SHARE ||
                            ChatKind.fromRaw(msg.kind) == ChatKind.SHARED_INGREDIENT ||
                            ChatKind.fromRaw(msg.kind) == ChatKind.SHARED_RECIPE -> {
                            Text(
                                text = stringResource(R.string.chat_share_sent_fallback),
                                color = if (mine) MaterialTheme.colorScheme.onPrimary
                                else MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                        else -> {
                            Text(
                                text = msg.body.orEmpty(),
                                color = if (mine) MaterialTheme.colorScheme.onPrimary
                                else MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }
                }
            }

            if (reactions.isNotEmpty()) {
                ReactionsRow(
                    reactions = reactions,
                    myUserId = myUserId,
                    onTap = onReactionTap
                )
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (!deleted && msg.editedAt != null) {
                    Text(
                        "Edited",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = formatTime(msg.createdAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (mine && isLastSeenMine) {
                Text(
                    text = "Seen",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun ReplyChip(target: ReplyPreviewWire, mine: Boolean) {
    val previewText = target.previewText()
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .heightIn(min = 24.dp)
                .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp))
        )
        Spacer(Modifier.width(6.dp))
        Column {
            Text(
                "Reply",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                previewText,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ReactionsRow(
    reactions: List<ReactionWire>,
    myUserId: String?,
    onTap: (ReactionEmoji) -> Unit
) {
    val grouped = reactions.groupBy { it.emoji }
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        grouped.keys.sorted().forEach { emojiRaw ->
            val arr = grouped[emojiRaw].orEmpty()
            val emoji = ReactionEmoji.fromRaw(emojiRaw)
            val mineReacted = arr.any { it.userId == myUserId }
            Surface(
                color = if (mineReacted) MaterialTheme.colorScheme.primaryContainer
                else MaterialTheme.colorScheme.surfaceVariant,
                shape = CircleShape,
                modifier = Modifier
                    .combinedClickable(
                        onClick = {
                            emoji?.let(onTap)
                        },
                        onLongClick = {}
                    )
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(emoji?.glyph ?: "•", style = MaterialTheme.typography.bodySmall)
                    if (arr.size > 1) {
                        Spacer(Modifier.width(2.dp))
                        Text(
                            "${arr.size}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Action sheet (long-press) and edit dialog

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun MessageActionSheet(
    message: ChatMessageWire,
    mine: Boolean,
    onDismiss: () -> Unit,
    onReact: (ReactionEmoji) -> Unit,
    onReply: () -> Unit,
    onCopy: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface
    ) {
        val k = ChatKind.fromRaw(message.kind)
        val canEditMessage = mine && k != ChatKind.WORKOUT_SHARE && k != ChatKind.ROUTINE_SHARE
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Reactions strip.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                ReactionEmoji.entries.forEach { e ->
                    Surface(
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier
                            .size(44.dp)
                            .combinedClickable(onClick = { onReact(e); onDismiss() }, onLongClick = {})
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Text(e.glyph, style = MaterialTheme.typography.titleMedium)
                        }
                    }
                }
            }

            DropdownMenuItem(
                text = { Text("Reply") },
                onClick = { onReply(); onDismiss() },
                leadingIcon = { Icon(Icons.Filled.Reply, contentDescription = null) }
            )
            DropdownMenuItem(
                text = { Text("Copy") },
                onClick = {
                    onCopy()
                    onDismiss()
                },
                leadingIcon = { Icon(Icons.Filled.ContentCopy, contentDescription = null) }
            )
            if (canEditMessage) {
                DropdownMenuItem(
                    text = { Text("Edit") },
                    onClick = { onEdit() },
                    leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) }
                )
            }
            if (mine) {
                DropdownMenuItem(
                    text = {
                        Text(
                            "Delete",
                            color = MaterialTheme.colorScheme.error
                        )
                    },
                    onClick = { onDelete(); onDismiss() },
                    leadingIcon = {
                        Icon(
                            Icons.Filled.Delete, contentDescription = null,
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                )
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun ChatComposer(
    draft: String,
    onDraftChange: (String) -> Unit,
    replyingTo: ChatMessageWire?,
    editingMessage: ChatMessageWire?,
    onCancelReply: () -> Unit,
    onCancelEdit: () -> Unit,
    onSend: () -> Unit,
    onSave: (String) -> Unit
) {
    val focusRequester = remember { FocusRequester() }
    LaunchedEffect(replyingTo?.id, editingMessage?.id) {
        if (replyingTo != null || editingMessage != null) {
            focusRequester.requestFocus()
        }
    }

    val trimmedDraft = draft.trim()
    val canSubmit = when {
        trimmedDraft.isEmpty() -> false
        editingMessage != null -> trimmedDraft != editingMessage.body?.trim().orEmpty()
        else -> true
    }

    Surface(
        tonalElevation = 2.dp,
        color = MaterialTheme.colorScheme.surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()
        ) {
            when {
                replyingTo != null -> {
                    ComposerContextBanner(
                        title = "Replying",
                        subtitle = replyingTo.replyComposerSubtitle(),
                        onCancel = onCancelReply,
                        cancelContentDescription = "Cancel reply"
                    )
                }
                editingMessage != null -> {
                    ComposerContextBanner(
                        title = "Editing",
                        subtitle = editingMessage.body.orEmpty(),
                        onCancel = onCancelEdit,
                        cancelContentDescription = "Cancel edit"
                    )
                }
            }

            Row(
                verticalAlignment = Alignment.Bottom,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp)
            ) {
                BasicTextField(
                    value = draft,
                    onValueChange = onDraftChange,
                    modifier = Modifier
                        .weight(1f)
                        .heightIn(min = 40.dp)
                        .focusRequester(focusRequester)
                        .background(
                            color = MaterialTheme.colorScheme.surfaceVariant,
                            shape = RoundedCornerShape(18.dp)
                        )
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                        color = MaterialTheme.colorScheme.onSurface
                    ),
                    maxLines = 5,
                    decorationBox = { innerTextField ->
                        Box {
                            if (draft.isEmpty()) {
                                Text(
                                    "Message…",
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            innerTextField()
                        }
                    }
                )
                Spacer(Modifier.width(8.dp))
                IconButton(
                    onClick = {
                        if (editingMessage != null) {
                            onSave(draft)
                        } else {
                            onSend()
                        }
                    },
                    enabled = canSubmit
                ) {
                    Icon(
                        imageVector = if (editingMessage != null) Icons.Filled.Check else Icons.Filled.Send,
                        contentDescription = if (editingMessage != null) "Save" else "Send"
                    )
                }
            }
        }
    }
}

@Composable
private fun ComposerContextBanner(
    title: String,
    subtitle: String,
    onCancel: () -> Unit,
    cancelContentDescription: String
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .heightIn(min = 32.dp)
                .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp))
        )
        Spacer(Modifier.width(8.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                title,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        IconButton(onClick = onCancel) {
            Icon(Icons.Filled.Close, contentDescription = cancelContentDescription)
        }
    }
}

// MARK: - Helpers

private fun formatTime(iso: String): String = runCatching {
    val odt = OffsetDateTime.parse(iso, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
    odt.format(DateTimeFormatter.ofPattern("HH:mm"))
}.getOrDefault("")

private fun copyToClipboard(ctx: Context, text: String) {
    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
    cm.setPrimaryClip(ClipData.newPlainText("message", text))
}
