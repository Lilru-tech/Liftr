package com.lilru.liftr.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Surface
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.ui.components.LiftrAvatar
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessagesInboxScreen(
    supabase: SupabaseClient,
    onClose: () -> Unit,
    onOpenThread: (conversationId: Long, otherProfile: ProfileLite?) -> Unit,
    modifier: Modifier = Modifier
) {
    val viewModel: MessagesInboxViewModel = viewModel(
        factory = MessagesInboxViewModelFactory(supabase)
    )
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var showNewChat by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.reload()
        viewModel.startRealtimeIfNeeded()
    }

    LaunchedEffect(state.error) {
        val msg = state.error ?: return@LaunchedEffect
        scope.launch {
            snackbar.showSnackbar(msg)
            viewModel.clearError()
        }
    }

    Scaffold(
        modifier = modifier,
        containerColor = Color.Transparent,
        topBar = {
            TopAppBar(
                title = { Text("Messages") },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Filled.Close, contentDescription = "Close")
                    }
                },
                actions = {
                    IconButton(onClick = { showNewChat = true }) {
                        Icon(Icons.Filled.Add, contentDescription = "New chat")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent
                )
            )
        },
        snackbarHost = { SnackbarHost(snackbar) }
    ) { padding ->
        InboxContent(
            state = state,
            padding = padding,
            onClickRow = { row ->
                val otherId = state.otherUserByConversationId[row.id]
                val profile = otherId?.let { state.profilesByUserId[it] }
                onOpenThread(row.id, profile)
            },
            onClearRow = { id -> viewModel.clearConversation(id) }
        )
        if (showNewChat) {
            NewChatScreen(
                supabase = supabase,
                onCancel = { showNewChat = false },
                onPick = { profile ->
                    viewModel.startDirect(profile) { id ->
                        showNewChat = false
                        if (id != null) {
                            onOpenThread(id, profile)
                        }
                    }
                }
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InboxContent(
    state: MessagesInboxUiState,
    padding: PaddingValues,
    onClickRow: (ConversationOverviewWire) -> Unit,
    onClearRow: (Long) -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
    ) {
        when {
            state.loading && state.rows.isEmpty() -> {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
            }
            state.rows.isEmpty() -> {
                Column(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(horizontal = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Filled.Send, contentDescription = null, modifier = Modifier.size(40.dp))
                    Text(
                        "No conversations yet",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        "Tap + to start a chat with someone you follow.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(vertical = 8.dp)
                ) {
                    items(state.rows, key = { it.id }) { row ->
                        val otherId = state.otherUserByConversationId[row.id]
                        val profile = otherId?.let { state.profilesByUserId[it] }
                        SwipeToDeleteRow(
                            rowId = row.id,
                            onClear = onClearRow
                        ) {
                            InboxRow(row, profile) { onClickRow(row) }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDeleteRow(
    rowId: Long,
    onClear: (Long) -> Unit,
    content: @Composable () -> Unit
) {
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) {
                onClear(rowId)
                true
            } else false
        },
        positionalThreshold = { distance -> distance * 0.5f }
    )
    // progress is NOT “finger down”: at rest it can be 1f between Settled→Settled. Use offset-based
    // dismissDirection (Material3): EndToStart iff offset < 0 (swipe left in LTR), Settled at 0.
    val revealDeleteTrack =
        state.dismissDirection == SwipeToDismissBoxValue.EndToStart
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        enableDismissFromEndToStart = true,
        backgroundContent = {
            if (revealDeleteTrack) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .padding(horizontal = 24.dp),
                    contentAlignment = Alignment.CenterEnd
                ) {
                    Icon(
                        Icons.Filled.Delete,
                        contentDescription = "Delete",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    ) {
        content()
    }
}

@Composable
private fun InboxRow(
    row: ConversationOverviewWire,
    profile: ProfileLite?,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
        shadowElevation = 0.dp
    ) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        LiftrAvatar(
            imageUrl = profile?.avatarUrl,
            displayName = profile?.username,
            size = 44.dp
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = profile?.let { "@${it.username}" } ?: row.title ?: "Conversation",
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1
                )
                row.lastMessageAt?.let {
                    Text(
                        text = relativeShort(it),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = row.lastMessageBody?.takeIf { it.isNotEmpty() } ?: "Say hi",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                    maxLines = 2
                )
                if (row.unreadCount > 0) {
                    Spacer(Modifier.width(8.dp))
                    Box(
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.primary, CircleShape)
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = row.unreadCount.coerceAtMost(99).toString(),
                            color = MaterialTheme.colorScheme.onPrimary,
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
            }
        }
    }
    }
}

private fun relativeShort(iso: String): String {
    return runCatching {
        val date = OffsetDateTime.parse(iso, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
        val now = OffsetDateTime.now(date.offset)
        val mins = ChronoUnit.MINUTES.between(date, now)
        when {
            mins < 1 -> "now"
            mins < 60 -> "${mins}m"
            mins < 60 * 24 -> "${mins / 60}h"
            mins < 60 * 24 * 7 -> "${mins / (60 * 24)}d"
            else -> "${mins / (60 * 24 * 7)}w"
        }
    }.getOrDefault("")
}
