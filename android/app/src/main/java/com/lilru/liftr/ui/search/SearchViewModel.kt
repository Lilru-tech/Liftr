package com.lilru.liftr.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class SearchProfileRow(
    @SerialName("user_id") val userId: String,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null
)

@Serializable
data class SearchWorkoutRow(
    val id: Int,
    @SerialName("user_id") val userId: String,
    val kind: String? = null,
    val title: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    val state: String? = null,
    @SerialName("calories_kcal") val caloriesKcal: Double? = null
)

@Serializable
data class TrendingQueryRow(
    @SerialName("normalized_query") val query: String
)

@Serializable
data class RecentQueryRow(
    @SerialName("normalized_query") val query: String
)

enum class SearchScope { USERS, WORKOUTS, SEGMENTS }

@Serializable
data class SearchSegmentRow(
    val id: String,
    val name: String,
    val buffer_m: Double? = null
)

data class SearchUiState(
    val query: String = "",
    val scope: SearchScope = SearchScope.USERS,
    val loading: Boolean = false,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val recentQueries: List<String> = emptyList(),
    val trendingQueries: List<String> = emptyList(),
    val profiles: List<SearchProfileRow> = emptyList(),
    val workouts: List<SearchWorkoutRow> = emptyList(),
    val segments: List<SearchSegmentRow> = emptyList(),
    val ownerUsernames: Map<String, String> = emptyMap()
)

private data class SearchResult(
    val profiles: List<SearchProfileRow> = emptyList(),
    val workouts: List<SearchWorkoutRow> = emptyList(),
    val segments: List<SearchSegmentRow> = emptyList(),
    val ownerUsernames: Map<String, String> = emptyMap()
)

private data class SuggestionsResult(
    val trending: List<String>,
    val recents: List<String>
)

class SearchViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val json = Json { ignoreUnknownKeys = true }
    private val _uiState = MutableStateFlow(SearchUiState())
    val uiState: StateFlow<SearchUiState> = _uiState.asStateFlow()

    init {
        refreshSuggestions()
    }

    fun onQueryChanged(query: String) {
        _uiState.value = _uiState.value.copy(query = query)
    }

    fun setScope(scope: SearchScope) {
        if (_uiState.value.scope == scope) return
        _uiState.value = _uiState.value.copy(scope = scope)
        if (_uiState.value.query.trim().length >= 2) {
            search()
        }
    }

    /** Pull: refresca sugerencias y repite búsqueda si el término es válido. */
    fun pullRefresh() {
        val st = _uiState.value
        if (st.isRefreshing) return
        _uiState.value = st.copy(isRefreshing = true, error = null)
        viewModelScope.launch {
            runCatching { refreshSuggestionsInternal() }
            val term = st.query.trim()
            if (term.length < 2) {
                _uiState.value = _uiState.value.copy(isRefreshing = false)
                return@launch
            }
            searchInternal(query = st.query, useRefreshing = true)
        }
    }

    fun search(query: String = _uiState.value.query) {
        viewModelScope.launch { searchInternal(query, useRefreshing = false) }
    }

    private suspend fun searchInternal(query: String, useRefreshing: Boolean) {
            val term = query.trim()
            val scope = _uiState.value.scope
            if (term.length < 2) {
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    query = query,
                    error = null,
                    profiles = emptyList(),
                    workouts = emptyList(),
                    segments = emptyList(),
                    ownerUsernames = emptyMap()
                )
                return
            }

            if (useRefreshing) {
                _uiState.value = _uiState.value.copy(isRefreshing = true, error = null, query = query)
            } else {
                _uiState.value = _uiState.value.copy(loading = true, isRefreshing = false, error = null, query = query)
            }
            runCatching {
                if (scope == SearchScope.USERS) {
                    val me = supabase.auth.currentUserOrNull()?.id
                    val profiles = supabase
                        .from(BackendContracts.Tables.PROFILES)
                        .select(columns = Columns.raw("user_id, username, avatar_url")) {
                            filter { ilike("username", "%$term%") }
                            order("username", Order.ASCENDING)
                            limit(50)
                        }
                        .decodeList<SearchProfileRow>()
                        .filterNot { it.userId == me }

                    recordSearch(term, "users")
                    SearchResult(profiles = profiles)
                } else if (scope == SearchScope.SEGMENTS) {
                    val rows = supabase.postgrest.rpc(
                        BackendContracts.Rpc.SEARCH_SEGMENTS_V1,
                        buildJsonObject {
                            put("p_query", term)
                            put("p_limit", 50)
                        }
                    ) { }
                        .let { decodeFlexibleList<SearchSegmentRow>(it.data) }
                    SearchResult(segments = rows)
                } else {
                    val workouts = supabase
                        .from(BackendContracts.Tables.WORKOUTS)
                        .select(
                            columns = Columns.raw(
                                "id, user_id, kind, title, started_at, state, calories_kcal"
                            )
                        ) {
                            filter {
                                eq("state", "published")
                                ilike("title", "%$term%")
                            }
                            order("started_at", Order.DESCENDING)
                            limit(50)
                        }
                        .decodeList<SearchWorkoutRow>()

                    val ownerIds = workouts.map { it.userId }.distinct()
                    val ownerMap = if (ownerIds.isEmpty()) {
                        emptyMap()
                    } else {
                        supabase
                            .from(BackendContracts.Tables.PROFILES)
                            .select(columns = Columns.raw("user_id, username")) {
                                filter { isIn("user_id", ownerIds) }
                            }
                            .let { decodeFlexibleList<SearchProfileRow>(it.data) }
                            .associate { it.userId to (it.username ?: "") }
                    }

                    recordSearch(term, "workouts")
                    SearchResult(
                        workouts = workouts,
                        ownerUsernames = ownerMap
                    )
                }
            }.onSuccess { result ->
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    profiles = result.profiles,
                    workouts = result.workouts,
                    segments = result.segments,
                    ownerUsernames = result.ownerUsernames
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    segments = emptyList(),
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
    }

    private suspend fun refreshSuggestionsInternal() {
        val result = runCatching {
            val trending = supabase.postgrest.rpc(BackendContracts.Rpc.TRENDING_SEARCH_QUERIES_24H) { }
                .let { decodeFlexibleList<TrendingQueryRow>(it.data) }
                .map { it.query }
                .distinct()
                .take(12)
            val recents = supabase.postgrest.rpc(BackendContracts.Rpc.USER_SEARCH_RECENT_LIST) { }
                .let { decodeFlexibleList<RecentQueryRow>(it.data) }
                .map { it.query }
                .distinct()
                .take(12)
            SuggestionsResult(trending = trending, recents = recents)
        }.getOrNull() ?: return
        _uiState.value = _uiState.value.copy(
            trendingQueries = result.trending,
            recentQueries = result.recents
        )
    }

    fun refreshSuggestions() {
        viewModelScope.launch { refreshSuggestionsInternal() }
    }

    fun clearRecents() {
        viewModelScope.launch {
            runCatching {
                supabase.postgrest.rpc(BackendContracts.Rpc.CLEAR_USER_SEARCH_RECENT) { }
            }.also {
                refreshSuggestions()
            }
        }
    }

    private suspend fun recordSearch(term: String, scope: String) {
        runCatching {
            supabase.postgrest.rpc(
                BackendContracts.Rpc.RECORD_SEARCH,
                buildJsonObject {
                    put("p_query", term)
                    put("p_scope", scope)
                }
            ) { }
        }
        refreshSuggestions()
    }

    private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }
}

class SearchViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != SearchViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return SearchViewModel(supabase) as T
    }
}
