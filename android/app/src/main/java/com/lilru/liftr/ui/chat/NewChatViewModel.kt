package com.lilru.liftr.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.ChatRepository
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class NewChatUiState(
    val loading: Boolean = false,
    val profiles: List<ProfileLite> = emptyList(),
    val query: String = "",
    val error: String? = null
) {
    val filtered: List<ProfileLite>
        get() = if (query.isBlank()) profiles
        else profiles.filter { it.username.contains(query.trim(), ignoreCase = true) }
}

class NewChatViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {

    private val repo = ChatRepository(supabase)
    private val _uiState = MutableStateFlow(NewChatUiState())
    val uiState: StateFlow<NewChatUiState> = _uiState.asStateFlow()

    fun load() {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true) }
            runCatching { repo.fetchMutualFollowees(me) }
                .onSuccess { list ->
                    _uiState.update {
                        it.copy(loading = false, profiles = list, error = null)
                    }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(loading = false, error = e.message ?: "Couldn't load contacts")
                    }
                }
        }
    }

    fun setQuery(value: String) {
        _uiState.update { it.copy(query = value) }
    }
}

class NewChatViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != NewChatViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return NewChatViewModel(supabase) as T
    }
}
