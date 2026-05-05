package com.lilru.liftr.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

@Serializable
private data class FollowEdgeRow(
    @SerialName("follower_id") val followerId: String? = null,
    @SerialName("followee_id") val followeeId: String? = null
)

@Serializable
data class FollowUserRow(
    @SerialName("user_id") val userId: String,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    val isFollowedByMe: Boolean = false
)

data class FollowersListUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val query: String = "",
    val users: List<FollowUserRow> = emptyList(),
    val filtered: List<FollowUserRow> = emptyList(),
    val meUserId: String? = null,
    val followBusyIds: Set<String> = emptySet()
)

class FollowersListViewModel(
    private val supabase: SupabaseClient,
    private val userId: String,
    private val mode: FollowListMode
) : ViewModel() {
    private val json = Json { ignoreUnknownKeys = true }
    private val _uiState = MutableStateFlow(FollowersListUiState())
    val uiState: StateFlow<FollowersListUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun onQueryChanged(query: String) {
        val users = _uiState.value.users
        _uiState.value = _uiState.value.copy(
            query = query,
            filtered = filterUsers(users, query)
        )
    }

    private fun refresh() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(loading = true, error = null)
            runCatching<Pair<List<FollowUserRow>, String?>> {
                val me = supabase.auth.currentUserOrNull()?.id
                val edgeCol = if (mode == FollowListMode.FOLLOWERS) "follower_id" else "followee_id"
                val whereCol = if (mode == FollowListMode.FOLLOWERS) "followee_id" else "follower_id"

                val edgeRows = supabase
                    .from(BackendContracts.Tables.FOLLOWS)
                    .select(columns = Columns.raw(edgeCol)) {
                        filter { eq(whereCol, userId) }
                        limit(1000)
                    }
                    .let { decodeFlexibleList<FollowEdgeRow>(it.data) }

                val ids = edgeRows.mapNotNull {
                    if (mode == FollowListMode.FOLLOWERS) it.followerId else it.followeeId
                }.distinct()
                if (ids.isEmpty()) return@runCatching (emptyList<FollowUserRow>() to me)

                val profiles = supabase
                    .from(BackendContracts.Tables.PROFILES)
                    .select(columns = Columns.raw("user_id, username, avatar_url")) {
                        filter { isIn("user_id", ids) }
                        limit(1000)
                    }
                    .let { decodeFlexibleList<FollowUserRow>(it.data) }
                val followedByMeIds = if (me != null) {
                    runCatching {
                        supabase
                            .from(BackendContracts.Tables.FOLLOWS)
                            .select(columns = Columns.raw("followee_id")) {
                                filter {
                                    eq("follower_id", me)
                                    isIn("followee_id", ids)
                                }
                                limit(1000)
                            }
                            .let { decodeFlexibleList<FollowEdgeRow>(it.data) }
                            .mapNotNull { it.followeeId }
                            .toSet()
                    }.getOrDefault(emptySet())
                } else {
                    emptySet()
                }
                val users = profiles
                    .map { row -> row.copy(isFollowedByMe = followedByMeIds.contains(row.userId)) }
                    .sortedBy { (it.username ?: "").lowercase() }
                users to me
            }.onSuccess { (users, meId) ->
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    meUserId = meId,
                    users = users,
                    filtered = filterUsers(users, _uiState.value.query)
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun toggleFollow(targetUserId: String) {
        val s = _uiState.value
        val me = s.meUserId ?: return
        if (targetUserId == me) return
        if (s.followBusyIds.contains(targetUserId)) return
        val currentRow = s.users.find { it.userId == targetUserId } ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                followBusyIds = _uiState.value.followBusyIds + targetUserId,
                error = null
            )
            val currentlyFollowing = currentRow.isFollowedByMe
            runCatching {
                if (currentlyFollowing) {
                    supabase.from(BackendContracts.Tables.FOLLOWS).delete {
                        filter {
                            eq("follower_id", me)
                            eq("followee_id", targetUserId)
                        }
                    }
                } else {
                    @Serializable
                    data class FollowInsert(
                        @SerialName("follower_id") val followerId: String,
                        @SerialName("followee_id") val followeeId: String
                    )
                    supabase.from(BackendContracts.Tables.FOLLOWS).insert(
                        FollowInsert(followerId = me, followeeId = targetUserId)
                    ) { }
                }
            }.onSuccess {
                val nextUsers = _uiState.value.users.map { row ->
                    if (row.userId == targetUserId) {
                        row.copy(isFollowedByMe = !currentlyFollowing)
                    } else {
                        row
                    }
                }
                _uiState.value = _uiState.value.copy(
                    users = nextUsers,
                    filtered = filterUsers(nextUsers, _uiState.value.query),
                    followBusyIds = _uiState.value.followBusyIds - targetUserId
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    followBusyIds = _uiState.value.followBusyIds - targetUserId,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
            }
        }
    }

    private fun filterUsers(users: List<FollowUserRow>, query: String): List<FollowUserRow> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return users
        return users.filter { (it.username ?: "").contains(trimmed, ignoreCase = true) }
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

class FollowersListViewModelFactory(
    private val supabase: SupabaseClient,
    private val userId: String,
    private val mode: FollowListMode
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != FollowersListViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return FollowersListViewModel(supabase, userId, mode) as T
    }
}
