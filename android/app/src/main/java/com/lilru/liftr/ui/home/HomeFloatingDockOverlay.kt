package com.lilru.liftr.ui.home

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.ui.draw.shadow
import com.lilru.liftr.ui.components.LiftrChatFab
import com.lilru.liftr.ui.components.LiftrGlassSurface
import com.lilru.liftr.ui.components.LiftrQuickActionFab
import com.lilru.liftr.ui.theme.LiftrRadii
import com.lilru.liftr.ui.theme.rememberLiftrHazeBlurEnabled
import dev.chrisbanes.haze.HazeState
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lilru.liftr.R
import com.lilru.liftr.prefs.ChatFabDockState
import com.lilru.liftr.prefs.ChatPreferences
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.chat.ChatThreadScreen
import com.lilru.liftr.ui.chat.MessagesInboxScreen
import com.lilru.liftr.ui.chat.ProfileLite
import com.lilru.liftr.ui.common.FLOATING_DOCK_MERGE_THRESHOLD_PX
import com.lilru.liftr.ui.common.FloatingDockEdge
import com.lilru.liftr.ui.common.floatingDockDragAndTap
import com.lilru.liftr.ui.common.floatingEdgeAnchor
import com.lilru.liftr.ui.common.floatingEdgeDock
import com.lilru.liftr.ui.common.floatingDockShouldMerge
import com.lilru.liftr.ui.common.floatingDockUnmergePositions
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.IntSize
import com.lilru.liftr.ui.common.floatingBubbleOffset
import com.lilru.liftr.ui.common.marginPx
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@Composable
fun HomeFloatingDockOverlay(
    supabase: SupabaseClient,
    quickPrefs: android.content.SharedPreferences,
    hazeState: HazeState,
    bottomInsetPx: Float,
    busy: Boolean,
    showChat: Boolean,
    isSignedIn: Boolean,
    onQuickSignInRequired: () -> Unit,
    onStrength: () -> Unit,
    onCardio: () -> Unit,
    onSport: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val view = LocalView.current

    val chatDock by ChatPreferences.fabDockFlow(context).collectAsStateWithLifecycle(
        initialValue = ChatFabDockState(edge = FloatingDockEdge.RIGHT, position = 0.64f)
    )
    val chatDragHintSeen by ChatPreferences.fabDragHintSeenFlow(context).collectAsStateWithLifecycle(
        initialValue = false
    )

    var quickEdge by remember {
        mutableStateOf(
            runCatching {
                FloatingDockEdge.valueOf(
                    quickPrefs.getString("edge", FloatingDockEdge.RIGHT.name) ?: FloatingDockEdge.RIGHT.name
                )
            }.getOrDefault(FloatingDockEdge.RIGHT)
        )
    }
    var quickPosition by remember { mutableStateOf(quickPrefs.getFloat("position", 0.64f)) }
    var quickHintDismissed by remember { mutableStateOf(quickPrefs.getBoolean("hintDismissed", false)) }

    var dockMerged by remember { mutableStateOf(quickPrefs.getBoolean("merged", false)) }
    var mergedEdge by remember {
        mutableStateOf(
            runCatching {
                FloatingDockEdge.valueOf(
                    quickPrefs.getString("mergedEdge", FloatingDockEdge.RIGHT.name)
                        ?: FloatingDockEdge.RIGHT.name
                )
            }.getOrDefault(FloatingDockEdge.RIGHT)
        )
    }
    var mergedPosition by remember { mutableStateOf(quickPrefs.getFloat("mergedPosition", 0.64f)) }

    var showQuickMenu by remember { mutableStateOf(false) }
    var showMergedMenu by remember { mutableStateOf(false) }
    var showInbox by remember { mutableStateOf(false) }
    var openThread by remember { mutableStateOf<Pair<Long, ProfileLite?>?>(null) }
    var quickTooltipSize by remember { mutableStateOf(IntSize.Zero) }
    var chatHintSize by remember { mutableStateOf(IntSize.Zero) }
    var chatDragLocation by remember { mutableStateOf<Offset?>(null) }
    var quickDragLocation by remember { mutableStateOf<Offset?>(null) }
    var mergedDragLocation by remember { mutableStateOf<Offset?>(null) }

    var chatFabEdge by remember { mutableStateOf(chatDock.edge) }
    var chatFabPosition by remember { mutableStateOf(chatDock.position) }

    LaunchedEffect(chatDock) {
        chatFabEdge = chatDock.edge
        chatFabPosition = chatDock.position
    }

    LaunchedEffect(showChat) {
        if (!showChat && dockMerged) {
            dockMerged = false
            quickPrefs.edit().putBoolean("merged", false).apply()
        }
    }

    fun persistQuickDock() {
        quickPrefs.edit()
            .putString("edge", quickEdge.name)
            .putFloat("position", quickPosition)
            .apply()
    }

    fun persistMergedDock() {
        quickPrefs.edit()
            .putBoolean("merged", dockMerged)
            .putString("mergedEdge", mergedEdge.name)
            .putFloat("mergedPosition", mergedPosition)
            .apply()
    }

    fun applyMerge(edge: FloatingDockEdge, position: Float) {
        dockMerged = true
        mergedEdge = edge
        mergedPosition = position
        chatFabEdge = edge
        chatFabPosition = position
        quickEdge = edge
        quickPosition = position
        showQuickMenu = false
        scope.launch {
            ChatPreferences.setFabDock(context, edge, position)
            quickPrefs.edit()
                .putBoolean("merged", true)
                .putString("mergedEdge", edge.name)
                .putFloat("mergedPosition", position)
                .putString("edge", edge.name)
                .putFloat("position", position)
                .apply()
        }
        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
    }

    fun unmerge() {
        val (chatPair, quickPair) = floatingDockUnmergePositions(mergedEdge, mergedPosition)
        dockMerged = false
        chatFabEdge = chatPair.first
        chatFabPosition = chatPair.second
        quickEdge = quickPair.first
        quickPosition = quickPair.second
        showMergedMenu = false
        scope.launch {
            ChatPreferences.setFabDock(context, chatFabEdge, chatFabPosition)
            quickPrefs.edit()
                .putBoolean("merged", false)
                .putString("edge", quickEdge.name)
                .putFloat("position", quickPosition)
                .apply()
        }
    }

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        val chatTabPx = with(density) { 56.dp.toPx() }
        val quickTabPx = with(density) { 52.dp.toPx() }
        val mergedTabPx = with(density) { 72.dp.toPx() }

        if (dockMerged && showChat) {
            val anchor = floatingEdgeAnchor(
                mergedEdge,
                mergedPosition,
                widthPx,
                heightPx,
                mergedTabPx,
                bottomInsetPx
            )
            val mergedDisplayAnchor = mergedDragLocation ?: anchor

            if (showMergedMenu) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clickable { showMergedMenu = false }
                )
                HomeFloatingDockMergedMenu(
                    busy = busy,
                    hazeState = hazeState,
                    onMessages = {
                        showMergedMenu = false
                        showInbox = true
                    },
                    onStrength = {
                        showMergedMenu = false
                        onStrength()
                    },
                    onCardio = {
                        showMergedMenu = false
                        onCardio()
                    },
                    onSport = {
                        showMergedMenu = false
                        onSport()
                    },
                    onSeparate = { unmerge() },
                    modifier = Modifier.offset {
                        homeFloatingDockMenuOffset(mergedDisplayAnchor, mergedEdge, widthPx, heightPx, density, menuHeightDp = 300f)
                    }
                )
            }

            HomeFloatingDockMergedButton(
                busy = busy,
                hazeState = hazeState,
                modifier = Modifier
                    .offset {
                        IntOffset(
                            (mergedDisplayAnchor.x - mergedTabPx / 2f).roundToInt(),
                            (mergedDisplayAnchor.y - mergedTabPx / 2f).roundToInt()
                        )
                    }
                    .floatingDockDragAndTap(
                        widthPx = widthPx,
                        heightPx = heightPx,
                        bottomInsetPx = bottomInsetPx,
                        startAnchor = { anchor },
                        onClick = { showMergedMenu = !showMergedMenu },
                        onDragStart = { showMergedMenu = false },
                        onDrag = { point -> mergedDragLocation = point },
                        onDragEnd = { point ->
                            mergedDragLocation = null
                            val dock = floatingEdgeDock(
                                point,
                                widthPx,
                                heightPx,
                                mergedTabPx,
                                bottomInsetPx
                            )
                            mergedEdge = dock.first
                            mergedPosition = dock.second
                            persistMergedDock()
                        }
                    )
            )
        } else {
            val chatAnchor = floatingEdgeAnchor(
                chatFabEdge,
                chatFabPosition,
                widthPx,
                heightPx,
                chatTabPx,
                bottomInsetPx
            )
            val quickAnchor = floatingEdgeAnchor(
                quickEdge,
                quickPosition,
                widthPx,
                heightPx,
                quickTabPx,
                bottomInsetPx
            )
            val chatDisplayAnchor = chatDragLocation ?: chatAnchor
            val quickDisplayAnchor = quickDragLocation ?: quickAnchor

            if (showQuickMenu) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clickable { showQuickMenu = false }
                )
                HomeQuickActionsMenu(
                    onStrength = {
                        showQuickMenu = false
                        onStrength()
                    },
                    onCardio = {
                        showQuickMenu = false
                        onCardio()
                    },
                    onSport = {
                        showQuickMenu = false
                        onSport()
                    },
                    modifier = Modifier.offset {
                        homeFloatingDockMenuOffset(quickDisplayAnchor, quickEdge, widthPx, heightPx, density)
                    }
                )
            }

            if (!quickHintDismissed && !showQuickMenu && !busy) {
                val tooltipWidthPx = if (quickTooltipSize.width > 0) {
                    quickTooltipSize.width.toFloat()
                } else {
                    with(density) { 280.dp.toPx() }
                }
                val tooltipHeightPx = if (quickTooltipSize.height > 0) {
                    quickTooltipSize.height.toFloat()
                } else {
                    with(density) { 48.dp.toPx() }
                }
                HomeQuickActionsTooltip(
                    onDismiss = {
                        quickHintDismissed = true
                        quickPrefs.edit().putBoolean("hintDismissed", true).apply()
                    },
                    modifier = Modifier
                        .onGloballyPositioned { coordinates ->
                            val size = coordinates.size
                            if (size != quickTooltipSize) {
                                quickTooltipSize = size
                            }
                        }
                        .offset {
                            homeQuickTooltipOffset(
                                quickDisplayAnchor,
                                quickEdge,
                                widthPx,
                                heightPx,
                                density,
                                tooltipWidthPx,
                                tooltipHeightPx,
                                with(density) { 56.dp.toPx() },
                                quickTabPx
                            )
                        }
                )
            }

            if (!chatDragHintSeen) {
                val chatCardWidthPx = with(density) { 280.dp.toPx() }
                val chatCardHeightPx = if (chatHintSize.height > 0) {
                    chatHintSize.height.toFloat()
                } else {
                    with(density) { 130.dp.toPx() }
                }
                val spacingPx = with(density) { 12.dp.toPx() }
                Card(
                    modifier = Modifier
                        .width(280.dp)
                        .onGloballyPositioned { coordinates ->
                            val size = coordinates.size
                            if (size != chatHintSize) {
                                chatHintSize = size
                            }
                        }
                        .offset {
                            floatingBubbleOffset(
                                anchor = chatDisplayAnchor,
                                edge = chatFabEdge,
                                bubbleWidthPx = chatCardWidthPx,
                                bubbleHeightPx = chatCardHeightPx,
                                tabWidthPx = chatTabPx,
                                tabHeightPx = chatTabPx,
                                screenWidthPx = widthPx,
                                screenHeightPx = heightPx,
                                spacingPx = spacingPx,
                                marginPx = density.marginPx()
                            )
                        },
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f)
                    )
                ) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            text = stringResource(R.string.chat_fab_drag_hint_message),
                            style = MaterialTheme.typography.bodyMedium
                        )
                        TextButton(
                            onClick = { scope.launch { ChatPreferences.setFabDragHintSeen(context) } },
                            modifier = Modifier.align(Alignment.End)
                        ) {
                            Text(stringResource(R.string.chat_fab_drag_hint_ok))
                        }
                    }
                }
            }

            if (showChat) {
            LiftrChatFab(
                modifier = Modifier
                    .offset {
                        IntOffset(
                            (chatDisplayAnchor.x - chatTabPx / 2f).roundToInt(),
                            (chatDisplayAnchor.y - chatTabPx / 2f).roundToInt()
                        )
                    }
                    .floatingDockDragAndTap(
                        widthPx = widthPx,
                        heightPx = heightPx,
                        bottomInsetPx = bottomInsetPx,
                        startAnchor = { chatAnchor },
                        onClick = { showInbox = true },
                        onDragStart = { showQuickMenu = false },
                        onDrag = { point ->
                            if (!chatDragHintSeen) {
                                scope.launch { ChatPreferences.setFabDragHintSeen(context) }
                            }
                            chatDragLocation = point
                        },
                        onDragEnd = { point ->
                            chatDragLocation = null
                            val dock = floatingEdgeDock(
                                point,
                                widthPx,
                                heightPx,
                                chatTabPx,
                                bottomInsetPx
                            )
                            val snapped = floatingEdgeAnchor(
                                dock.first,
                                dock.second,
                                widthPx,
                                heightPx,
                                chatTabPx,
                                bottomInsetPx
                            )
                            if (showChat && floatingDockShouldMerge(snapped, quickAnchor, FLOATING_DOCK_MERGE_THRESHOLD_PX)) {
                                applyMerge(dock.first, dock.second)
                            } else {
                                chatFabEdge = dock.first
                                chatFabPosition = dock.second
                                scope.launch {
                                    ChatPreferences.setFabDock(context, chatFabEdge, chatFabPosition)
                                }
                            }
                        }
                    )
            )
            }

            LiftrQuickActionFab(
                hazeState = hazeState,
                busy = busy,
                modifier = Modifier
                    .offset {
                        IntOffset(
                            (quickDisplayAnchor.x - quickTabPx / 2f).roundToInt(),
                            (quickDisplayAnchor.y - quickTabPx / 2f).roundToInt()
                        )
                    }
                    .size(52.dp)
                    .floatingDockDragAndTap(
                        widthPx = widthPx,
                        heightPx = heightPx,
                        bottomInsetPx = bottomInsetPx,
                        startAnchor = { quickAnchor },
                        onClick = {
                            if (!isSignedIn) {
                                onQuickSignInRequired()
                            } else {
                                quickHintDismissed = true
                                quickPrefs.edit().putBoolean("hintDismissed", true).apply()
                                showQuickMenu = !showQuickMenu
                            }
                        },
                        onDragStart = { showQuickMenu = false },
                        onDrag = { point -> quickDragLocation = point },
                        onDragEnd = { point ->
                            quickDragLocation = null
                            val dock = floatingEdgeDock(
                                point,
                                widthPx,
                                heightPx,
                                quickTabPx,
                                bottomInsetPx
                            )
                            val snapped = floatingEdgeAnchor(
                                dock.first,
                                dock.second,
                                widthPx,
                                heightPx,
                                quickTabPx,
                                bottomInsetPx
                            )
                            if (showChat && floatingDockShouldMerge(snapped, chatAnchor, FLOATING_DOCK_MERGE_THRESHOLD_PX)) {
                                applyMerge(dock.first, dock.second)
                            } else {
                                quickEdge = dock.first
                                quickPosition = dock.second
                                quickHintDismissed = true
                                persistQuickDock()
                                quickPrefs.edit().putBoolean("hintDismissed", true).apply()
                            }
                        }
                    )
            )
        }

        if (showInbox && openThread == null) {
            val theme = remember { LiftrPreferences.backgroundTheme(context) }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .liftrAppBackgroundGradientOpaque(theme)
            ) {
                MessagesInboxScreen(
                    supabase = supabase,
                    onClose = { showInbox = false },
                    onOpenThread = { id, profile -> openThread = id to profile }
                )
            }
        }
        openThread?.let { (id, profile) ->
            val theme = remember { LiftrPreferences.backgroundTheme(context) }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .liftrAppBackgroundGradientOpaque(theme)
            ) {
                ChatThreadScreen(
                    supabase = supabase,
                    conversationId = id,
                    otherProfile = profile,
                    onBack = { openThread = null }
                )
            }
        }
    }
}

@Composable
private fun HomeFloatingDockMergedButton(
    busy: Boolean,
    hazeState: HazeState,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(LiftrRadii.dockButton)
    Box(
        modifier = modifier
            .size(width = 72.dp, height = 52.dp)
            .shadow(
                elevation = 6.dp,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = 0.18f),
                spotColor = Color.Black.copy(alpha = 0.18f)
            )
            .clip(shape)
            .border(0.8.dp, Color.White.copy(alpha = 0.22f), shape)
    ) {
        Row(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .width(36.dp)
                    .fillMaxHeight()
                    .background(MaterialTheme.colorScheme.primary),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Filled.Send,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.size(20.dp)
                )
            }
            LiftrGlassSurface(
                hazeState = hazeState,
                shape = RoundedCornerShape(topEnd = LiftrRadii.dockButton, bottomEnd = LiftrRadii.dockButton),
                modifier = Modifier
                    .width(36.dp)
                    .fillMaxHeight(),
                elevation = 0.dp,
                strokeAlpha = 0f,
                blurEnabled = rememberLiftrHazeBlurEnabled()
            ) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    if (busy) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text("⚡", style = MaterialTheme.typography.titleLarge, color = Color(0xFFFFD600))
                    }
                }
            }
        }
    }
}

@Composable
private fun HomeFloatingDockMergedMenu(
    busy: Boolean,
    hazeState: HazeState,
    onMessages: () -> Unit,
    onStrength: () -> Unit,
    onCardio: () -> Unit,
    onSport: () -> Unit,
    onSeparate: () -> Unit,
    modifier: Modifier = Modifier
) {
    LiftrGlassSurface(
        hazeState = hazeState,
        shape = RoundedCornerShape(24.dp),
        modifier = modifier.width(158.dp),
        elevation = 16.dp,
        strokeAlpha = 0.22f
    ) {
    Column(
        modifier = Modifier
            .width(158.dp)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        TextButton(
            onClick = onMessages,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(50))
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.58f))
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.Send, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(
                    text = stringResource(R.string.home_floating_dock_messages),
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }

        Divider(modifier = Modifier.fillMaxWidth())

        Text(
            text = stringResource(R.string.home_quick_actions_title),
            style = MaterialTheme.typography.labelLarge
        )
        HomeQuickActionsMenuButton(
            text = stringResource(R.string.home_filter_strength),
            onClick = onStrength,
            enabled = !busy
        )
        HomeQuickActionsMenuButton(
            text = stringResource(R.string.home_filter_cardio),
            onClick = onCardio,
            enabled = !busy
        )
        HomeQuickActionsMenuButton(
            text = stringResource(R.string.home_filter_sport),
            onClick = onSport,
            enabled = !busy
        )

        Divider(modifier = Modifier.fillMaxWidth())

        TextButton(onClick = onSeparate) {
            Text(
                text = stringResource(R.string.home_floating_dock_separate_buttons),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
    }
}

@Composable
private fun HomeQuickActionsMenuButton(
    text: String,
    onClick: () -> Unit,
    enabled: Boolean = true
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(50))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.58f))
    ) {
        Text(text, color = MaterialTheme.colorScheme.onSurface)
    }
}

private fun homeFloatingDockMenuOffset(
    anchor: Offset,
    edge: FloatingDockEdge,
    widthPx: Float,
    heightPx: Float,
    density: androidx.compose.ui.unit.Density,
    menuHeightDp: Float = 188f
): IntOffset {
    val menuWidth = with(density) { 158.dp.toPx() }
    val menuHeight = with(density) { menuHeightDp.dp.toPx() }
    val spacing = with(density) { 92.dp.toPx() }
    val raw = when (edge) {
        FloatingDockEdge.LEFT -> Offset(anchor.x + spacing, anchor.y)
        FloatingDockEdge.RIGHT -> Offset(anchor.x - spacing, anchor.y)
        FloatingDockEdge.TOP -> Offset(anchor.x, anchor.y + spacing)
        FloatingDockEdge.BOTTOM -> Offset(anchor.x, anchor.y - spacing)
    }

    return IntOffset(
        (raw.x - menuWidth / 2f).coerceIn(12f, widthPx - menuWidth - 12f).roundToInt(),
        (raw.y - menuHeight / 2f).coerceIn(12f, heightPx - menuHeight - 12f).roundToInt()
    )
}
