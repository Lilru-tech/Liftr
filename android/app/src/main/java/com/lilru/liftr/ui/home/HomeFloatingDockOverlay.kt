package com.lilru.liftr.ui.home

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.material3.FloatingActionButton
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
import androidx.compose.ui.input.pointer.pointerInput
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
import com.lilru.liftr.ui.common.floatingEdgeAnchor
import com.lilru.liftr.ui.common.floatingEdgeDock
import com.lilru.liftr.ui.common.floatingDockShouldMerge
import com.lilru.liftr.ui.common.floatingDockUnmergePositions
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@Composable
fun HomeFloatingDockOverlay(
    supabase: SupabaseClient,
    quickPrefs: android.content.SharedPreferences,
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

            if (showMergedMenu) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clickable { showMergedMenu = false }
                )
                HomeFloatingDockMergedMenu(
                    busy = busy,
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
                        homeFloatingDockMenuOffset(anchor, mergedEdge, widthPx, heightPx, density, menuHeightDp = 300f)
                    }
                )
            }

            var mergedDidDrag by remember { mutableStateOf(false) }
            HomeFloatingDockMergedButton(
                busy = busy,
                onClick = {
                    if (mergedDidDrag) {
                        mergedDidDrag = false
                    } else {
                        showMergedMenu = !showMergedMenu
                    }
                },
                modifier = Modifier
                    .offset {
                        IntOffset(
                            (anchor.x - mergedTabPx / 2f).roundToInt(),
                            (anchor.y - mergedTabPx / 2f).roundToInt()
                        )
                    }
                    .pointerInput(mergedEdge, mergedPosition, widthPx, heightPx) {
                        var dragAnchor = anchor
                        detectDragGestures(
                            onDragStart = {
                                mergedDidDrag = false
                                dragAnchor = anchor
                                showMergedMenu = false
                            },
                            onDragEnd = {
                                mergedEdge = dragAnchor.let {
                                    floatingEdgeDock(it, widthPx, heightPx, mergedTabPx, bottomInsetPx).first
                                }
                                mergedPosition = dragAnchor.let {
                                    floatingEdgeDock(it, widthPx, heightPx, mergedTabPx, bottomInsetPx).second
                                }
                                persistMergedDock()
                            },
                            onDrag = { _, drag ->
                                mergedDidDrag = true
                                dragAnchor += drag
                                val dock = floatingEdgeDock(
                                    dragAnchor,
                                    widthPx,
                                    heightPx,
                                    mergedTabPx,
                                    bottomInsetPx
                                )
                                mergedEdge = dock.first
                                mergedPosition = dock.second
                            }
                        )
                    }
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
                        homeFloatingDockMenuOffset(quickAnchor, quickEdge, widthPx, heightPx, density)
                    }
                )
            }

            if (!quickHintDismissed && !showQuickMenu && !busy) {
                HomeQuickActionsTooltip(
                    onDismiss = {
                        quickHintDismissed = true
                        quickPrefs.edit().putBoolean("hintDismissed", true).apply()
                    },
                    modifier = Modifier.offset {
                        homeQuickTooltipOffset(quickAnchor, quickEdge, widthPx, heightPx, density)
                    }
                )
            }

            if (!chatDragHintSeen) {
                Card(
                    modifier = Modifier
                        .offset {
                            homeChatFabDragHintOffset(
                                chatAnchor,
                                chatFabEdge,
                                widthPx,
                                heightPx,
                                density
                            )
                        }
                        .width(280.dp),
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
            var chatDidDrag by remember { mutableStateOf(false) }
            FloatingActionButton(
                onClick = {
                    if (chatDidDrag) {
                        chatDidDrag = false
                    } else {
                        showInbox = true
                    }
                },
                modifier = Modifier
                    .offset {
                        IntOffset(
                            (chatAnchor.x - chatTabPx / 2f).roundToInt(),
                            (chatAnchor.y - chatTabPx / 2f).roundToInt()
                        )
                    }
                    .size(56.dp)
                    .pointerInput(chatFabEdge, chatFabPosition, quickAnchor) {
                        var dragAnchor = chatAnchor
                        detectDragGestures(
                            onDragStart = {
                                chatDidDrag = false
                                dragAnchor = chatAnchor
                                showQuickMenu = false
                            },
                            onDragEnd = {
                                val dock = floatingEdgeDock(
                                    dragAnchor,
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
                            },
                            onDrag = { change, drag ->
                                change.consume()
                                chatDidDrag = true
                                if (!chatDragHintSeen) {
                                    scope.launch { ChatPreferences.setFabDragHintSeen(context) }
                                }
                                dragAnchor += Offset(drag.x, drag.y)
                                val dock = floatingEdgeDock(
                                    dragAnchor,
                                    widthPx,
                                    heightPx,
                                    chatTabPx,
                                    bottomInsetPx
                                )
                                chatFabEdge = dock.first
                                chatFabPosition = dock.second
                            }
                        )
                    },
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary
            ) {
                Icon(Icons.Filled.Send, contentDescription = "Open messages")
            }
            }

            var quickDidDrag by remember { mutableStateOf(false) }
            FloatingActionButton(
                onClick = {
                    if (quickDidDrag) {
                        quickDidDrag = false
                    } else if (!isSignedIn) {
                        onQuickSignInRequired()
                    } else {
                        quickHintDismissed = true
                        quickPrefs.edit().putBoolean("hintDismissed", true).apply()
                        showQuickMenu = !showQuickMenu
                    }
                },
                modifier = Modifier
                    .offset {
                        IntOffset(
                            (quickAnchor.x - quickTabPx / 2f).roundToInt(),
                            (quickAnchor.y - quickTabPx / 2f).roundToInt()
                        )
                    }
                    .size(52.dp)
                    .pointerInput(quickEdge, quickPosition, chatAnchor) {
                        var dragAnchor = quickAnchor
                        detectDragGestures(
                            onDragStart = {
                                quickDidDrag = false
                                dragAnchor = quickAnchor
                                showQuickMenu = false
                            },
                            onDragEnd = {
                                val dock = floatingEdgeDock(
                                    dragAnchor,
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
                            },
                            onDrag = { _, drag ->
                                quickDidDrag = true
                                dragAnchor += drag
                                val dock = floatingEdgeDock(
                                    dragAnchor,
                                    widthPx,
                                    heightPx,
                                    quickTabPx,
                                    bottomInsetPx
                                )
                                quickEdge = dock.first
                                quickPosition = dock.second
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
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .size(width = 72.dp, height = 52.dp)
            .clip(RoundedCornerShape(16.dp))
            .border(0.8.dp, Color.White.copy(alpha = 0.22f), RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
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
            Box(
                modifier = Modifier
                    .width(36.dp)
                    .fillMaxHeight()
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f)),
                contentAlignment = Alignment.Center
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
}

@Composable
private fun HomeFloatingDockMergedMenu(
    busy: Boolean,
    onMessages: () -> Unit,
    onStrength: () -> Unit,
    onCardio: () -> Unit,
    onSport: () -> Unit,
    onSeparate: () -> Unit,
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

private fun homeChatFabDragHintOffset(
    anchor: Offset,
    edge: FloatingDockEdge,
    widthPx: Float,
    heightPx: Float,
    density: androidx.compose.ui.unit.Density
): IntOffset {
    val cardWidth = with(density) { 280.dp.toPx() }
    val cardHeight = with(density) { 96.dp.toPx() }
    val spacing = with(density) { 70.dp.toPx() }
    val verticalSpacing = with(density) { 58.dp.toPx() }
    val raw = when (edge) {
        FloatingDockEdge.LEFT -> Offset(anchor.x + spacing, anchor.y)
        FloatingDockEdge.RIGHT -> Offset(anchor.x - spacing - cardWidth, anchor.y)
        FloatingDockEdge.TOP -> Offset(anchor.x - cardWidth / 2f, anchor.y + verticalSpacing)
        FloatingDockEdge.BOTTOM -> Offset(anchor.x - cardWidth / 2f, anchor.y - verticalSpacing - cardHeight)
    }

    return IntOffset(
        raw.x.coerceIn(12f, widthPx - cardWidth - 12f).roundToInt(),
        (raw.y - cardHeight / 2f).coerceIn(12f, heightPx - cardHeight - 12f).roundToInt()
    )
}
