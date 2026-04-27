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
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
private data class VoteProbeRow(
    @SerialName("feature_request_id") val featureRequestId: Long
)

data class FeatureRequestsListUiState(
    val loading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val items: List<FeatureRequestRow> = emptyList(),
    /** null = not loaded yet, for vote button enable */
    val voteByRequestId: Map<Long, Boolean?> = emptyMap(),
    val votingRequestId: Long? = null
)

class FeatureRequestsListViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val _uiState = MutableStateFlow(FeatureRequestsListUiState())
    val uiState: StateFlow<FeatureRequestsListUiState> = _uiState.asStateFlow()

    init {
        refresh(showBlockingLoader = true)
    }

    fun refresh(showBlockingLoader: Boolean = false) {
        viewModelScope.launch {
            if (showBlockingLoader) {
                _uiState.update { it.copy(loading = true, isRefreshing = false, error = null) }
            } else {
                _uiState.update { it.copy(isRefreshing = true, error = null) }
            }
            runCatching {
                val res = supabase
                    .from(BackendContracts.Views.VW_FEATURE_REQUESTS)
                    .select(columns = Columns.raw("*")) {
                        order("created_at", Order.DESCENDING)
                    }
                FeatureRequestsJson.decodeList<FeatureRequestRow>(res.data)
            }.onSuccess { rows ->
                _uiState.update {
                    it.copy(
                        loading = false,
                        isRefreshing = false,
                        error = null,
                        items = rows,
                        voteByRequestId = rows.associate { r -> r.id to (it.voteByRequestId[r.id]) }
                    )
                }
            }.onFailure { e ->
                _uiState.update {
                    it.copy(
                        loading = false,
                        isRefreshing = false,
                        error = e.message?.take(300) ?: e::class.java.simpleName
                    )
                }
            }
        }
    }

    fun ensureVoteState(requestId: Long) {
        val me = supabase.auth.currentUserOrNull()?.id ?: run {
            _uiState.update { s ->
                s.copy(voteByRequestId = s.voteByRequestId + (requestId to false))
            }
            return
        }
        if (_uiState.value.voteByRequestId[requestId] != null) return
        viewModelScope.launch {
            val voted = runCatching { fetchMyVote(requestId, me) }.getOrDefault(false)
            _uiState.update { s ->
                s.copy(voteByRequestId = s.voteByRequestId + (requestId to voted))
            }
        }
    }

    private suspend fun fetchMyVote(requestId: Long, userId: String): Boolean {
        val res = supabase
            .from(BackendContracts.Tables.FEATURE_REQUEST_VOTES)
            .select(columns = Columns.raw("feature_request_id")) {
                filter {
                    eq("feature_request_id", requestId)
                    eq("user_id", userId)
                }
                limit(1)
            }
        return FeatureRequestsJson.decodeList<VoteProbeRow>(res.data).isNotEmpty()
    }

    fun toggleVote(requestId: Long) {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        val st = _uiState.value
        val voted = st.voteByRequestId[requestId] ?: return
        if (st.votingRequestId != null) return
        viewModelScope.launch {
            _uiState.update { it.copy(votingRequestId = requestId) }
            runCatching {
                if (voted) {
                    supabase.from(BackendContracts.Tables.FEATURE_REQUEST_VOTES).delete {
                        filter {
                            eq("feature_request_id", requestId)
                            eq("user_id", me)
                        }
                    }
                } else {
                    supabase.from(BackendContracts.Tables.FEATURE_REQUEST_VOTES).upsert(
                        FeatureVoteInsert(featureRequestId = requestId, userId = me)
                    ) {
                        onConflict = "feature_request_id,user_id"
                    }
                }
            }.onSuccess {
                _uiState.update { s ->
                    s.copy(
                        votingRequestId = null,
                        voteByRequestId = s.voteByRequestId + (requestId to !voted)
                    )
                }
                refresh(showBlockingLoader = false)
            }.onFailure {
                _uiState.update { s -> s.copy(votingRequestId = null) }
            }
        }
    }
}

class FeatureRequestsListViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != FeatureRequestsListViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return FeatureRequestsListViewModel(supabase) as T
    }
}
