package com.lilru.liftr.ui.profile

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
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

data class ContactSupportUiState(
    val userEmail: String = "",
    val subject: String = "Bug Report",
    val message: String = "",
    val loading: Boolean = false,
    val error: String? = null,
    val success: Boolean = false
) {
    val isValid: Boolean
        get() = userEmail.isNotBlank() && subject.isNotBlank() && message.isNotBlank()
}

@Serializable
private data class ContactMessageRow(
    @SerialName("user_email") val userEmail: String,
    val subject: String,
    val message: String
)

class ContactSupportViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val _uiState = MutableStateFlow(ContactSupportUiState())
    val uiState: StateFlow<ContactSupportUiState> = _uiState.asStateFlow()

    init {
        val email = supabase.auth.currentUserOrNull()?.email?.trim().orEmpty()
        _uiState.update { it.copy(userEmail = email) }
    }

    fun setSubjectFromList(subjects: List<String>, index: Int) {
        if (index in subjects.indices) {
            _uiState.update { it.copy(subject = subjects[index], error = null) }
        }
    }

    fun setMessage(text: String) {
        val t = if (text.length > MAX_MESSAGE) text.take(MAX_MESSAGE) else text
        _uiState.update { it.copy(message = t, error = null) }
    }

    fun send(errorNoEmail: String, errorSend: String) {
        val s = _uiState.value
        if (s.loading) return
        if (s.userEmail.isBlank()) {
            _uiState.update { it.copy(error = errorNoEmail) }
            return
        }
        val msg = s.message.trim()
        if (msg.isEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true, error = null) }
            runCatching {
                supabase.from(BackendContracts.Tables.CONTACT_MESSAGES).insert(
                    ContactMessageRow(
                        userEmail = s.userEmail.trim(),
                        subject = s.subject,
                        message = msg
                    )
                ) { }
            }.onSuccess {
                _uiState.update { it.copy(loading = false, success = true, error = null) }
            }.onFailure {
                _uiState.update { it.copy(loading = false, error = errorSend) }
            }
        }
    }

    companion object {
        const val MAX_MESSAGE = 1000
    }
}

class ContactSupportViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ContactSupportViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ContactSupportViewModel(supabase) as T
    }
}
