package com.lilru.liftr.ui.feature

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class FeatureRequestCreateUiState(
    val title: String = "",
    val description: String = "",
    val userEmail: String = "",
    val saving: Boolean = false,
    val error: String? = null
) {
    val canSave: Boolean
        get() = title.isNotBlank() && description.isNotBlank() && userEmail.isNotBlank() && !saving
}

class FeatureRequestCreateViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val _uiState = MutableStateFlow(
        FeatureRequestCreateUiState(
            userEmail = supabase.auth.currentUserOrNull()?.email?.trim().orEmpty()
        )
    )
    val uiState: StateFlow<FeatureRequestCreateUiState> = _uiState.asStateFlow()

    fun setTitle(t: String) {
        _uiState.update { it.copy(title = if (t.length > 50) t.take(50) else t, error = null) }
    }

    fun setDescription(t: String) {
        _uiState.update { it.copy(description = if (t.length > 500) t.take(500) else t, error = null) }
    }

    fun create(
        onSuccess: () -> Unit,
        errNoEmail: String,
        errNotSignedIn: String,
        errGeneric: String
    ) {
        val me = supabase.auth.currentUserOrNull()?.id
        if (me == null) {
            _uiState.update { it.copy(error = errNotSignedIn) }
            return
        }
        val s = _uiState.value
        if (!s.canSave) return
        val email = s.userEmail.trim()
        if (email.isEmpty()) {
            _uiState.update { it.copy(error = errNoEmail) }
            return
        }
        viewModelScope.launch {
            _uiState.update { it.copy(saving = true, error = null) }
            runCatching {
                supabase.from(BackendContracts.Tables.FEATURE_REQUESTS).insert(
                    FeatureRequestInsert(
                        title = s.title.trim(),
                        description = s.description.trim(),
                        email = email,
                        createdBy = me
                    )
                ) { }
            }.onSuccess {
                _uiState.update { it.copy(saving = false) }
                onSuccess()
            }.onFailure { e ->
                _uiState.update {
                    it.copy(
                        saving = false,
                        error = e.message?.take(300) ?: errGeneric
                    )
                }
            }
        }
    }
}

class FeatureRequestCreateViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != FeatureRequestCreateViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return FeatureRequestCreateViewModel(supabase) as T
    }
}
