package com.lilru.liftr.ui.feature

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class FeatureRequestDetailUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val comments: List<FeatureRequestCommentRow> = emptyList(),
    val sendingComment: Boolean = false,
    val commentDraft: String = ""
)

class FeatureRequestDetailViewModel(
    private val supabase: SupabaseClient,
    private val requestId: Long
) : ViewModel() {
    private val _uiState = MutableStateFlow(FeatureRequestDetailUiState())
    val uiState: StateFlow<FeatureRequestDetailUiState> = _uiState.asStateFlow()

    init {
        loadComments()
    }

    fun setCommentDraft(text: String) {
        val t = if (text.length > 500) text.take(500) else text
        _uiState.update { it.copy(commentDraft = t) }
    }

    fun loadComments() {
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true, error = null) }
            runCatching {
                val res = supabase
                    .from(BackendContracts.Views.VW_FEATURE_REQUEST_COMMENTS)
                    .select(columns = Columns.raw("*")) {
                        filter { eq("feature_request_id", requestId) }
                        order("created_at", Order.ASCENDING)
                    }
                FeatureRequestsJson.decodeList<FeatureRequestCommentRow>(res.data)
            }.onSuccess { list ->
                _uiState.update { it.copy(loading = false, error = null, comments = list) }
            }.onFailure { e ->
                _uiState.update {
                    it.copy(loading = false, error = e.message?.take(300) ?: e::class.java.simpleName)
                }
            }
        }
    }

    fun postComment() {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        val body = _uiState.value.commentDraft.trim()
        if (body.isEmpty() || _uiState.value.sendingComment) return
        viewModelScope.launch {
            _uiState.update { it.copy(sendingComment = true, error = null) }
            runCatching {
                supabase.from(BackendContracts.Tables.FEATURE_REQUEST_COMMENTS).insert(
                    FeatureCommentInsert(
                        featureRequestId = requestId,
                        userId = me,
                        body = body
                    )
                ) { }
            }.onSuccess {
                _uiState.update { it.copy(sendingComment = false, commentDraft = "") }
                loadComments()
            }.onFailure { e ->
                _uiState.update {
                    it.copy(
                        sendingComment = false,
                        error = e.message?.take(300) ?: e::class.java.simpleName
                    )
                }
            }
        }
    }
}

class FeatureRequestDetailViewModelFactory(
    private val supabase: SupabaseClient,
    private val requestId: Long
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != FeatureRequestDetailViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return FeatureRequestDetailViewModel(supabase, requestId) as T
    }
}
