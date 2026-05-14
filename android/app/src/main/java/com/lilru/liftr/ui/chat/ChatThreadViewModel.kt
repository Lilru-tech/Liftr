package com.lilru.liftr.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.ChatRepository
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

data class ChatThreadUiState(
    val loading: Boolean = false,
    val messages: List<ChatMessageWire> = emptyList(),
    val typingUserIds: Set<String> = emptySet(),
    val error: String? = null,
    val hasMore: Boolean = true,
    val loadingOlder: Boolean = false,
    val draft: String = "",
    val reactionsByMessageId: Map<Long, List<ReactionWire>> = emptyMap(),
    val replyTargetsById: Map<Long, ReplyPreviewWire> = emptyMap(),
    val replyingTo: ChatMessageWire? = null,
    val editingMessage: ChatMessageWire? = null,
    val muted: Boolean = false,
    /** `last_read_message_id` of the *other* participant; used for "Seen". */
    val peerLastReadMessageId: Long? = null,
    /** Bottom-sheet target: long-pressed message that triggered the actions sheet. */
    val actionSheetMessage: ChatMessageWire? = null
)

class ChatThreadViewModel(
    private val supabase: SupabaseClient,
    val conversationId: Long
) : ViewModel() {

    private val repo = ChatRepository(supabase)
    private val _uiState = MutableStateFlow(ChatThreadUiState())
    val uiState: StateFlow<ChatThreadUiState> = _uiState.asStateFlow()

    private var realtime: ChatThreadRealtime? = null
    private var reactionsRealtime: ChatReactionsRealtime? = null
    private var typing: ChatTypingChannel? = null
    private var realtimeJob: Job? = null

    val myUserId: String?
        get() = supabase.auth.currentUserOrNull()?.id

    fun loadInitial() {
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true) }
            runCatching { repo.fetchMessages(conversationId, beforeId = null, limit = 50) }
                .onSuccess { page ->
                    val asc = page.reversed()
                    _uiState.update {
                        it.copy(
                            loading = false,
                            messages = asc,
                            hasMore = page.size >= 50,
                            error = null
                        )
                    }
                    markRead()
                    refreshSidecars()
                    refreshPeerLastRead()
                    loadMutedFlag()
                }
                .onFailure { e ->
                    _uiState.update { it.copy(loading = false, error = e.message ?: "Error") }
                }
        }
    }

    fun loadOlderIfNeeded() {
        val state = _uiState.value
        if (state.loadingOlder || !state.hasMore) return
        val oldest = state.messages.firstOrNull()?.id ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(loadingOlder = true) }
            runCatching { repo.fetchMessages(conversationId, beforeId = oldest, limit = 50) }
                .onSuccess { page ->
                    val asc = page.reversed()
                    _uiState.update {
                        it.copy(
                            messages = asc + it.messages,
                            hasMore = page.size >= 50,
                            loadingOlder = false
                        )
                    }
                    refreshSidecars()
                }
                .onFailure { e ->
                    _uiState.update { it.copy(loadingOlder = false, error = e.message ?: "Error") }
                }
        }
    }

    fun setDraft(text: String) {
        _uiState.update { it.copy(draft = text) }
        typing?.setTyping(text.isNotBlank())
    }

    fun send() {
        val draft = _uiState.value.draft.trim()
        if (draft.isEmpty()) return
        val me = myUserId ?: return
        val replyToId = _uiState.value.replyingTo?.id

        // Optimistic insert: pick a tentative id that won't collide with any
        // future server id (random negative bigint).
        val tentativeId = -(UUID.randomUUID().mostSignificantBits.let {
            if (it == Long.MIN_VALUE) Long.MAX_VALUE else kotlin.math.abs(it)
        })
        val tentative = ChatMessageWire(
            id = tentativeId,
            userId = me,
            kind = "text",
            body = draft,
            metadata = null,
            replyToMessageId = replyToId,
            createdAt = java.time.OffsetDateTime.now().toString(),
            editedAt = null,
            deletedAt = null,
            conversationId = conversationId
        )
        _uiState.update {
            it.copy(
                messages = it.messages + tentative,
                draft = "",
                replyingTo = null
            )
        }
        typing?.setTyping(false)

        viewModelScope.launch {
            runCatching {
                repo.sendMessage(conversationId, draft, UUID.randomUUID(), replyToMessageId = replyToId)
            }
                .onSuccess { newId ->
                    _uiState.update { state ->
                        val alreadyArrived = state.messages.any { it.id == newId }
                        val updated = if (alreadyArrived) {
                            state.messages.filterNot { it.id == tentativeId }
                        } else {
                            state.messages.map {
                                if (it.id == tentativeId) it.copy(id = newId) else it
                            }
                        }
                        state.copy(messages = updated)
                    }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(
                            messages = it.messages.filterNot { m -> m.id == tentativeId },
                            error = e.message ?: "Couldn't send message"
                        )
                    }
                }
        }
    }

    fun startRealtime() {
        if (realtimeJob?.isActive == true) return
        val me = myUserId ?: return
        val r = ChatThreadRealtime(supabase, conversationId) { event -> apply(event) }
        val rx = ChatReactionsRealtime(supabase, conversationId) { event -> apply(event) }
        val t = ChatTypingChannel(supabase, conversationId, me) { typingUsers ->
            _uiState.update { it.copy(typingUserIds = typingUsers) }
        }
        realtime = r
        reactionsRealtime = rx
        typing = t
        realtimeJob = viewModelScope.launch {
            r.start()
            rx.start()
            t.start()
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    // MARK: - Replying / editing UI state

    fun startReply(message: ChatMessageWire) {
        _uiState.update {
            it.copy(
                replyingTo = message,
                editingMessage = null,
                actionSheetMessage = null
            )
        }
    }

    fun cancelReply() {
        _uiState.update { it.copy(replyingTo = null) }
    }

    fun startEdit(message: ChatMessageWire) {
        _uiState.update {
            it.copy(
                editingMessage = message,
                replyingTo = null,
                draft = message.body.orEmpty(),
                actionSheetMessage = null
            )
        }
    }

    fun cancelEdit() {
        _uiState.update { it.copy(editingMessage = null, draft = "") }
        typing?.setTyping(false)
    }

    fun showActionSheet(message: ChatMessageWire) {
        _uiState.update { it.copy(actionSheetMessage = message) }
    }

    fun dismissActionSheet() {
        _uiState.update { it.copy(actionSheetMessage = null) }
    }

    // MARK: - Reactions / edit / delete / mute / clear

    fun toggleReaction(messageId: Long, emoji: ReactionEmoji) {
        if (messageId <= 0) return
        val me = myUserId ?: return
        // Optimistic.
        _uiState.update { state ->
            val current = state.reactionsByMessageId[messageId].orEmpty()
            val existing = current.firstOrNull { it.userId == me && it.emoji == emoji.raw }
            val next = if (existing != null) current - existing
            else current + ReactionWire(messageId, me, emoji.raw, java.time.OffsetDateTime.now().toString())
            state.copy(
                reactionsByMessageId = state.reactionsByMessageId + (messageId to next),
                actionSheetMessage = null
            )
        }
        viewModelScope.launch {
            runCatching { repo.toggleReaction(messageId, emoji.raw) }
                .onFailure { e ->
                    _uiState.update { it.copy(error = e.message ?: "Couldn't react") }
                    // Reload server-side state for this message to undo bad UI.
                    runCatching { repo.fetchReactions(listOf(messageId)) }
                        .onSuccess { map ->
                            _uiState.update {
                                it.copy(
                                    reactionsByMessageId = it.reactionsByMessageId +
                                            (messageId to (map[messageId] ?: emptyList()))
                                )
                            }
                        }
                }
        }
    }

    fun submitEdit(newBody: String) {
        val target = _uiState.value.editingMessage ?: return
        val trimmed = newBody.trim()
        if (trimmed.isEmpty() || trimmed == target.body?.trim()) {
            _uiState.update { it.copy(editingMessage = null, draft = "") }
            return
        }
        viewModelScope.launch {
            runCatching { repo.editMessage(target.id, trimmed) }
                .onSuccess {
                    _uiState.update { state ->
                        state.copy(
                            messages = state.messages.map {
                                if (it.id == target.id) it.copy(
                                    body = trimmed,
                                    editedAt = java.time.OffsetDateTime.now().toString()
                                ) else it
                            },
                            editingMessage = null,
                            draft = ""
                        )
                    }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(error = e.message ?: "Couldn't edit", editingMessage = null)
                    }
                }
        }
    }

    fun deleteMessage(messageId: Long) {
        viewModelScope.launch {
            runCatching { repo.deleteMessage(messageId) }
                .onSuccess {
                    _uiState.update { state ->
                        state.copy(
                            messages = state.messages.map {
                                if (it.id == messageId) it.copy(
                                    body = null,
                                    deletedAt = java.time.OffsetDateTime.now().toString()
                                ) else it
                            },
                            actionSheetMessage = null
                        )
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(error = e.message ?: "Couldn't delete") }
                }
        }
    }

    fun setMuted(muted: Boolean) {
        viewModelScope.launch {
            runCatching { repo.setMuted(conversationId, muted) }
                .onSuccess { _uiState.update { it.copy(muted = muted) } }
                .onFailure { e -> _uiState.update { it.copy(error = e.message ?: "Couldn't change mute") } }
        }
    }

    fun clearConversation(onCleared: () -> Unit = {}) {
        viewModelScope.launch {
            runCatching { repo.clearConversation(conversationId) }
                .onSuccess {
                    _uiState.update { it.copy(messages = emptyList()) }
                    onCleared()
                }
                .onFailure { e -> _uiState.update { it.copy(error = e.message ?: "Couldn't clear") } }
        }
    }

    // MARK: - Internal

    private fun apply(event: ChatRealtimeEvent) {
        _uiState.update { state ->
            when (event) {
                is ChatRealtimeEvent.Inserted -> {
                    val msg = event.message
                    val merged = state.messages.toMutableList()
                    val sameId = merged.indexOfFirst { it.id == msg.id }
                    if (sameId >= 0) {
                        merged[sameId] = msg
                    } else {
                        val pending = merged.indexOfFirst { local ->
                            local.id < 0 &&
                                    local.userId == msg.userId &&
                                    local.body == msg.body
                        }
                        if (pending >= 0) {
                            merged[pending] = msg
                        } else {
                            merged.add(msg)
                        }
                    }
                    state.copy(messages = merged)
                }
                is ChatRealtimeEvent.Updated -> state.copy(
                    messages = state.messages.map {
                        if (it.id == event.message.id) event.message else it
                    }
                )
                is ChatRealtimeEvent.Deleted -> state.copy(
                    messages = state.messages.filterNot { it.id == event.messageId },
                    reactionsByMessageId = state.reactionsByMessageId - event.messageId
                )
            }
        }
        if (event is ChatRealtimeEvent.Inserted) {
            markRead()
            // Hydrate reply target if needed.
            event.message.replyToMessageId?.let { rid ->
                if (_uiState.value.replyTargetsById[rid] == null) {
                    viewModelScope.launch {
                        runCatching { repo.fetchReplyTargets(listOf(rid)) }
                            .onSuccess { map ->
                                _uiState.update { state ->
                                    state.copy(replyTargetsById = state.replyTargetsById + map)
                                }
                            }
                    }
                }
            }
        }
    }

    private fun apply(event: ChatReactionRealtimeEvent) {
        _uiState.update { state ->
            when (event) {
                is ChatReactionRealtimeEvent.Inserted -> {
                    val r = event.reaction
                    val current = state.reactionsByMessageId[r.messageId].orEmpty()
                    val next = if (current.any { it.userId == r.userId && it.emoji == r.emoji }) {
                        current
                    } else current + r
                    state.copy(
                        reactionsByMessageId = state.reactionsByMessageId + (r.messageId to next)
                    )
                }
                is ChatReactionRealtimeEvent.Deleted -> {
                    val current = state.reactionsByMessageId[event.messageId].orEmpty()
                    val next = current.filterNot {
                        it.userId == event.userId && it.emoji == event.emoji
                    }
                    state.copy(
                        reactionsByMessageId = state.reactionsByMessageId + (event.messageId to next)
                    )
                }
            }
        }
    }

    private fun refreshSidecars() {
        val state = _uiState.value
        val ids = state.messages.map { it.id }.filter { it > 0 }
        if (ids.isNotEmpty()) {
            viewModelScope.launch {
                runCatching { repo.fetchReactions(ids) }
                    .onSuccess { map ->
                        _uiState.update { s ->
                            // Replace per-message lists; preserve those for ids
                            // we didn't query (rare but possible).
                            val merged = s.reactionsByMessageId.toMutableMap()
                            for (id in ids) merged[id] = map[id] ?: emptyList()
                            s.copy(reactionsByMessageId = merged)
                        }
                    }
            }
        }
        val replyIds = state.messages.mapNotNull { it.replyToMessageId }.toSet().toList()
        if (replyIds.isNotEmpty()) {
            viewModelScope.launch {
                runCatching { repo.fetchReplyTargets(replyIds) }
                    .onSuccess { map ->
                        _uiState.update { it.copy(replyTargetsById = it.replyTargetsById + map) }
                    }
            }
        }
    }

    private fun refreshPeerLastRead() {
        val me = myUserId ?: return
        viewModelScope.launch {
            runCatching { repo.fetchPeerLastRead(conversationId, me) }
                .onSuccess { last -> _uiState.update { it.copy(peerLastReadMessageId = last) } }
        }
    }

    private fun loadMutedFlag() {
        val me = myUserId ?: return
        viewModelScope.launch {
            runCatching { repo.fetchMutedFlag(conversationId, me) }
                .onSuccess { muted -> _uiState.update { it.copy(muted = muted) } }
        }
    }

    private fun markRead() {
        val last = _uiState.value.messages.lastOrNull() ?: return
        if (last.id <= 0) return
        viewModelScope.launch {
            runCatching { repo.markRead(conversationId, last.id) }
        }
    }

    override fun onCleared() {
        super.onCleared()
        val r = realtime
        val rx = reactionsRealtime
        val t = typing
        realtimeJob?.cancel()
        if (r != null || rx != null || t != null) {
            kotlinx.coroutines.GlobalScope.launch {
                runCatching { r?.stop() }
                runCatching { rx?.stop() }
                runCatching { t?.stop() }
            }
        }
    }
}

class ChatThreadViewModelFactory(
    private val supabase: SupabaseClient,
    private val conversationId: Long
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ChatThreadViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ChatThreadViewModel(supabase, conversationId) as T
    }
}
