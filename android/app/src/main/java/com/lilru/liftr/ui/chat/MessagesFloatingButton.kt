package com.lilru.liftr.ui.chat

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lilru.liftr.R
import com.lilru.liftr.prefs.ChatPreferences
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Floating "messages" FAB that the user can drag freely and snaps to the
 * nearest screen corner on release. Persists the chosen corner across
 * launches via [ChatPreferences].
 *
 * The button itself opens [MessagesInboxScreen] as a full-screen overlay
 * (own Box stacked on top of the parent), and nesting [ChatThreadScreen]
 * keeps navigation contained inside this composable to avoid touching
 * the host's nav graph.
 */
@Composable
fun MessagesFloatingButton(
    supabase: SupabaseClient,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()

    val storedCorner by ChatPreferences.fabCornerFlow(context).collectAsStateWithLifecycle(
        initialValue = ChatPreferences.FabCorner.BottomLeading
    )
    val dragHintSeen by ChatPreferences.fabDragHintSeenFlow(context).collectAsStateWithLifecycle(
        initialValue = false
    )

    var showInbox by remember { mutableStateOf(false) }
    var openThread by remember { mutableStateOf<Pair<Long, ProfileLite?>?>(null) }
    var dragHintClearRequested by remember { mutableStateOf(false) }

    LaunchedEffect(showInbox, dragHintSeen) {
        if (showInbox && !dragHintSeen) ChatPreferences.setFabDragHintSeen(context)
    }

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        val pad = with(density) { 16.dp.toPx() }
        val fabSize = with(density) { 56.dp.toPx() }

        if (!dragHintSeen) {
            val fabStack = 16.dp + 56.dp + 8.dp
            val hintCardModifier = when (storedCorner) {
                ChatPreferences.FabCorner.BottomLeading ->
                    Modifier.align(Alignment.BottomStart).padding(start = 12.dp, bottom = fabStack)
                ChatPreferences.FabCorner.BottomTrailing ->
                    Modifier.align(Alignment.BottomEnd).padding(end = 12.dp, bottom = fabStack)
                ChatPreferences.FabCorner.TopLeading ->
                    Modifier.align(Alignment.TopStart).padding(start = 12.dp, top = fabStack)
                ChatPreferences.FabCorner.TopTrailing ->
                    Modifier.align(Alignment.TopEnd).padding(end = 12.dp, top = fabStack)
            }
            Card(
                modifier = hintCardModifier
                    .widthIn(max = 300.dp)
                    .fillMaxWidth(0.92f),
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

        val anchor = anchorFor(storedCorner, widthPx, heightPx, pad, fabSize)
        val offsetX = remember { Animatable(anchor.x) }
        val offsetY = remember { Animatable(anchor.y) }

        LaunchedEffect(storedCorner, widthPx, heightPx) {
            val target = anchorFor(storedCorner, widthPx, heightPx, pad, fabSize)
            scope.launch { offsetX.animateTo(target.x, spring()) }
            scope.launch { offsetY.animateTo(target.y, spring()) }
        }

        Box(
            modifier = Modifier
                .size(56.dp)
                .pointerInput(widthPx, heightPx, dragHintSeen) {
                    detectDragGestures(
                        onDrag = { change, drag ->
                            change.consume()
                            if (!dragHintSeen && !dragHintClearRequested) {
                                dragHintClearRequested = true
                                scope.launch { ChatPreferences.setFabDragHintSeen(context) }
                            }
                            scope.launch {
                                offsetX.snapTo(offsetX.value + drag.x)
                                offsetY.snapTo(offsetY.value + drag.y)
                            }
                        },
                        onDragEnd = {
                            val centerX = offsetX.value + fabSize / 2f
                            val centerY = offsetY.value + fabSize / 2f
                            val corner = nearestCorner(centerX, centerY, widthPx, heightPx)
                            scope.launch {
                                ChatPreferences.setFabCorner(context, corner)
                            }
                            val target = anchorFor(corner, widthPx, heightPx, pad, fabSize)
                            scope.launch { offsetX.animateTo(target.x, spring()) }
                            scope.launch { offsetY.animateTo(target.y, spring()) }
                        }
                    )
                }
                .offset { IntOffset(offsetX.value.roundToInt(), offsetY.value.roundToInt()) }
        ) {
            FloatingActionButton(
                onClick = { showInbox = true },
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary
            ) {
                Icon(Icons.Filled.Send, contentDescription = "Open messages")
            }
        }

        if (showInbox && openThread == null) {
            // Full-screen overlay above Home: gradient stops must be opaque here —
            // [liftrBackgroundGradientPair] uses translucent alphas that blend with
            // whatever is underneath (see liftrAppBackgroundGradientOpaque).
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

/** Returns the (x, y) px offset for the given corner so the FAB sits flush. */
private fun anchorFor(
    corner: ChatPreferences.FabCorner,
    widthPx: Float,
    heightPx: Float,
    padPx: Float,
    fabSize: Float
): Offset = when (corner) {
    ChatPreferences.FabCorner.BottomLeading ->
        Offset(padPx, heightPx - padPx - fabSize)
    ChatPreferences.FabCorner.BottomTrailing ->
        Offset(widthPx - padPx - fabSize, heightPx - padPx - fabSize)
    ChatPreferences.FabCorner.TopLeading ->
        Offset(padPx, padPx)
    ChatPreferences.FabCorner.TopTrailing ->
        Offset(widthPx - padPx - fabSize, padPx)
}

/** Decide which corner is closest to (centerX, centerY). */
private fun nearestCorner(
    centerX: Float,
    centerY: Float,
    widthPx: Float,
    heightPx: Float
): ChatPreferences.FabCorner {
    val isLeft = centerX < widthPx / 2f
    val isTop = centerY < heightPx / 2f
    return when {
        isTop && isLeft -> ChatPreferences.FabCorner.TopLeading
        isTop -> ChatPreferences.FabCorner.TopTrailing
        isLeft -> ChatPreferences.FabCorner.BottomLeading
        else -> ChatPreferences.FabCorner.BottomTrailing
    }
}
