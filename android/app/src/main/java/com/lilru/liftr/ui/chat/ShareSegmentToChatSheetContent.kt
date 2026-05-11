package com.lilru.liftr.ui.chat

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.data.ChatRepository
import com.lilru.liftr.ui.components.LiftrAvatar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareSegmentToChatSheetContent(
    supabase: SupabaseClient,
    snapshot: SegmentShareSnapshot,
    onDone: () -> Unit,
    modifier: Modifier = Modifier
) {
    val repo = remember { ChatRepository(supabase) }
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(true) }
    var rows by remember { mutableStateOf<List<ConversationOverviewWire>>(emptyList()) }
    var otherByConv by remember { mutableStateOf<Map<Long, String>>(emptyMap()) }
    var profiles by remember { mutableStateOf<Map<String, ProfileLite>>(emptyMap()) }
    var error by remember { mutableStateOf<String?>(null) }
    var sendBusyId by remember { mutableStateOf<Long?>(null) }
    var showNewChat by remember { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            loading = true
            error = null
            runCatching {
                val list = repo.fetchConversations(limit = 100, offset = 0)
                val me = supabase.auth.currentUserOrNull()?.id ?: return@runCatching
                val map = repo.fetchOtherParticipantIds(list.map { it.id }, me)
                val profs = repo.fetchProfiles(map.values)
                rows = list
                otherByConv = map
                profiles = profs
            }.onFailure { e ->
                error = e.message ?: "Error"
            }
            loading = false
        }
    }

    LaunchedEffect(Unit) { reload() }

    Box(modifier = modifier.fillMaxSize()) {
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.share_segment_title)) },
                    navigationIcon = {
                        IconButton(onClick = onDone) {
                            Icon(Icons.Filled.Close, contentDescription = null)
                        }
                    },
                    actions = {
                        IconButton(onClick = { showNewChat = true }) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent)
                )
            }
        ) { padding ->
            when {
                loading && rows.isEmpty() -> {
                    Box(
                        Modifier
                            .padding(padding)
                            .fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }
                error != null && rows.isEmpty() -> {
                    Column(
                        Modifier
                            .padding(padding)
                            .fillMaxSize()
                            .padding(24.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text(error!!, color = MaterialTheme.colorScheme.error)
                        Text(
                            stringResource(R.string.common_retry),
                            Modifier.clickable { reload() },
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
                rows.isEmpty() -> {
                    Column(
                        Modifier
                            .padding(padding)
                            .fillMaxSize()
                            .padding(horizontal = 32.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Spacer(Modifier.weight(0.2f))
                        Text(stringResource(R.string.share_segment_no_conversations))
                        Spacer(Modifier.weight(0.3f))
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier
                            .padding(padding)
                            .fillMaxSize(),
                        contentPadding = PaddingValues(vertical = 8.dp)
                    ) {
                        items(rows, key = { it.id }) { row ->
                            val otherId = otherByConv[row.id]
                            val profile = otherId?.let { profiles[it] }
                            val busy = sendBusyId == row.id
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable(enabled = !busy) {
                                        scope.launch {
                                            sendBusyId = row.id
                                            runCatching {
                                                repo.sendSegmentShare(row.id, snapshot)
                                                onDone()
                                            }.onFailure { e ->
                                                error = e.message
                                            }
                                            sendBusyId = null
                                        }
                                    }
                                    .padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                LiftrAvatar(
                                    imageUrl = profile?.avatarUrl,
                                    displayName = profile?.username,
                                    size = 44.dp
                                )
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        profile?.username?.let { "@$it" } ?: row.title ?: "Chat",
                                        style = MaterialTheme.typography.bodyLarge
                                    )
                                    Text(
                                        row.lastMessageBody?.takeIf { it.isNotBlank() } ?: "…",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1
                                    )
                                }
                                if (busy) {
                                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                                }
                            }
                        }
                    }
                }
            }
        }
        if (showNewChat) {
            NewChatScreen(
                supabase = supabase,
                onCancel = { showNewChat = false },
                onPick = { profile ->
                    scope.launch {
                        runCatching {
                            val cid = repo.startDirectConversation(profile.userId)
                            repo.sendSegmentShare(cid, snapshot)
                            showNewChat = false
                            onDone()
                        }.onFailure { e ->
                            error = shareSheetFriendlyStartError(e)
                        }
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}

private fun shareSheetFriendlyStartError(e: Throwable): String {
    val raw = e.message?.lowercase().orEmpty()
    if (raw.contains("not_mutual_follow")) {
        return "You can only DM people who follow you back."
    }
    if (raw.contains("cannot_dm_self")) {
        return "You can't message yourself."
    }
    return e.message ?: "Error"
}
