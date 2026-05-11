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

data class MessagesInboxUiState(
    val loading: Boolean = false,
    val rows: List<ConversationOverviewWire> = emptyList(),
    val otherUserByConversationId: Map<Long, String> = emptyMap(),
    val profilesByUserId: Map<String, ProfileLite> = emptyMap(),
    val error: String? = null
)

class MessagesInboxViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {

    private val repo = ChatRepository(supabase)

    private val _uiState = MutableStateFlow(MessagesInboxUiState())
    val uiState: StateFlow<MessagesInboxUiState> = _uiState.asStateFlow()

    private var inbox: ChatInboxRealtime? = null
    private var realtimeJob: Job? = null

    fun reload() {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true) }
            runCatching {
                val list = repo.fetchConversations(limit = 100)
                val otherIds = repo.fetchOtherParticipantIds(list.map { it.id }, me)
                val profiles = repo.fetchProfiles(otherIds.values.toSet())
                Triple(list, otherIds, profiles)
            }.onSuccess { (list, otherIds, profiles) ->
                _uiState.update {
                    it.copy(
                        loading = false,
                        rows = list,
                        otherUserByConversationId = otherIds,
                        profilesByUserId = profiles,
                        error = null
                    )
                }
            }.onFailure { e ->
                _uiState.update { it.copy(loading = false, error = e.message ?: "Error") }
            }
        }
    }

    fun startRealtimeIfNeeded() {
        if (realtimeJob?.isActive == true) return
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        val r = ChatInboxRealtime(supabase, me) { reload() }
        inbox = r
        realtimeJob = viewModelScope.launch { r.start() }
    }

    fun startDirect(profile: ProfileLite, onResult: (Long?) -> Unit) {
        viewModelScope.launch {
            runCatching { repo.startDirectConversation(profile.userId) }
                .onSuccess { id ->
                    _uiState.update {
                        it.copy(
                            otherUserByConversationId = it.otherUserByConversationId + (id to profile.userId),
                            profilesByUserId = it.profilesByUserId + (profile.userId to profile)
                        )
                    }
                    reload()
                    onResult(id)
                }
                .onFailure { e ->
                    val msg = friendlyStartError(e)
                    _uiState.update { it.copy(error = msg) }
                    onResult(null)
                }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    /**
     * Hides the conversation for the current user. Optimistically removes
     * the row, restores it on failure. The server-side `clear_conversation`
     * RPC sets the per-user `cleared_at_message_id` cursor so the row stops
     * showing in `get_conversations_overview` until a new message arrives.
     */
    fun clearConversation(conversationId: Long) {
        val previous = _uiState.value.rows
        _uiState.update { it.copy(rows = it.rows.filterNot { row -> row.id == conversationId }) }
        viewModelScope.launch {
            runCatching { repo.clearConversation(conversationId) }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(rows = previous, error = e.message ?: "Couldn't clear conversation")
                    }
                }
        }
    }

    override fun onCleared() {
        super.onCleared()
        realtimeJob?.cancel()
        val r = inbox
        if (r != null) {
            // Unsubscribe is suspending; fire and forget on a background scope.
            kotlinx.coroutines.GlobalScope.launch { runCatching { r.stop() } }
        }
    }

    private fun friendlyStartError(error: Throwable): String {
        val raw = (error.message ?: "").lowercase()
        return when {
            raw.contains("not_mutual_follow") -> "You can only DM people who follow you back."
            raw.contains("cannot_dm_self") -> "You can't message yourself."
            else -> error.message ?: "Couldn't start conversation"
        }
    }
}

class MessagesInboxViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != MessagesInboxViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return MessagesInboxViewModel(supabase) as T
    }
}
