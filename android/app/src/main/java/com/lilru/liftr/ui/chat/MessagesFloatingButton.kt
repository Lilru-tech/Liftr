package com.lilru.liftr.ui.chat

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.IntSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lilru.liftr.R
import com.lilru.liftr.prefs.ChatFabDockState
import com.lilru.liftr.prefs.ChatPreferences
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.common.FloatingDockEdge
import com.lilru.liftr.ui.common.floatingBubbleOffset
import com.lilru.liftr.ui.common.floatingEdgeAnchor
import com.lilru.liftr.ui.common.floatingEdgeDock
import com.lilru.liftr.ui.common.marginPx
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@Composable
fun MessagesFloatingButton(
    supabase: SupabaseClient,
    modifier: Modifier = Modifier,
    bottomInsetPx: Float = 0f
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()

    val persistedDock by ChatPreferences.fabDockFlow(context).collectAsStateWithLifecycle(
        initialValue = ChatFabDockState(
            edge = FloatingDockEdge.RIGHT,
            position = 0.64f
        )
    )
    val dragHintSeen by ChatPreferences.fabDragHintSeenFlow(context).collectAsStateWithLifecycle(
        initialValue = false
    )

    var fabEdge by remember { mutableStateOf(persistedDock.edge) }
    var fabPosition by remember { mutableStateOf(persistedDock.position) }

    LaunchedEffect(persistedDock) {
        fabEdge = persistedDock.edge
        fabPosition = persistedDock.position
    }

    var showInbox by remember { mutableStateOf(false) }
    var openThread by remember { mutableStateOf<Pair<Long, ProfileLite?>?>(null) }
    var dragHintClearRequested by remember { mutableStateOf(false) }
    var fabDidDrag by remember { mutableStateOf(false) }
    var dragHintSize by remember { mutableStateOf(IntSize.Zero) }

    LaunchedEffect(showInbox, dragHintSeen) {
        if (showInbox && !dragHintSeen) ChatPreferences.setFabDragHintSeen(context)
    }

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        val tabSizePx = with(density) { 56.dp.toPx() }

        val anchor = floatingEdgeAnchor(
            edge = fabEdge,
            position = fabPosition,
            widthPx = widthPx,
            heightPx = heightPx,
            tabSizePx = tabSizePx,
            bottomInsetPx = bottomInsetPx
        )

        if (!dragHintSeen) {
            val cardWidthPx = with(density) { 280.dp.toPx() }
            val cardHeightPx = if (dragHintSize.height > 0) {
                dragHintSize.height.toFloat()
            } else {
                with(density) { 130.dp.toPx() }
            }
            val spacingPx = with(density) { 12.dp.toPx() }
            Card(
                modifier = Modifier
                    .width(280.dp)
                    .onGloballyPositioned { coordinates ->
                        val size = coordinates.size
                        if (size != dragHintSize) {
                            dragHintSize = size
                        }
                    }
                    .offset {
                        floatingBubbleOffset(
                            anchor = anchor,
                            edge = fabEdge,
                            bubbleWidthPx = cardWidthPx,
                            bubbleHeightPx = cardHeightPx,
                            tabWidthPx = tabSizePx,
                            tabHeightPx = tabSizePx,
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
                Column(
                    Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
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

        FloatingActionButton(
            onClick = {
                if (fabDidDrag) {
                    fabDidDrag = false
                } else {
                    showInbox = true
                }
            },
            modifier = Modifier
                .offset {
                    IntOffset(
                        (anchor.x - tabSizePx / 2f).roundToInt(),
                        (anchor.y - tabSizePx / 2f).roundToInt()
                    )
                }
                .size(56.dp)
                .pointerInput(widthPx, heightPx, bottomInsetPx, dragHintSeen) {
                    var dragAnchor = anchor
                    detectDragGestures(
                        onDragStart = { fabDidDrag = false },
                        onDragEnd = {
                            scope.launch {
                                ChatPreferences.setFabDock(context, fabEdge, fabPosition)
                            }
                        },
                        onDrag = { change, drag ->
                            change.consume()
                            fabDidDrag = true
                            if (!dragHintSeen && !dragHintClearRequested) {
                                dragHintClearRequested = true
                                scope.launch { ChatPreferences.setFabDragHintSeen(context) }
                            }
                            dragAnchor += Offset(drag.x, drag.y)
                            val dock = floatingEdgeDock(
                                point = dragAnchor,
                                widthPx = widthPx,
                                heightPx = heightPx,
                                tabSizePx = tabSizePx,
                                bottomInsetPx = bottomInsetPx
                            )
                            fabEdge = dock.first
                            fabPosition = dock.second
                        }
                    )
                },
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary
        ) {
            Icon(Icons.Filled.Send, contentDescription = "Open messages")
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
