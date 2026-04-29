package com.lilru.liftr.ui.notifications

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
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

@Serializable
private data class NotificationRow(
    val id: Int,
    val type: String? = null,
    val title: String? = null,
    val body: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("is_read") val isRead: Boolean = false,
    val data: JsonObject? = null
)

data class NotificationItemUi(
    val id: Int,
    val type: String,
    val title: String,
    val body: String?,
    val createdAt: String?,
    val isRead: Boolean,
    val workoutId: Int? = null,
    val profileUserId: String? = null,
    val data: JsonObject? = null
)

data class NotificationsUiState(
    val loading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val items: List<NotificationItemUi> = emptyList(),
    val unreadCount: Int = 0,
    val deleteAllBusy: Boolean = false,
    val deletingIds: Set<Int> = emptySet()
)

class NotificationsViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val json = Json { ignoreUnknownKeys = true }
    private val _uiState = MutableStateFlow(NotificationsUiState())
    val uiState: StateFlow<NotificationsUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    /**
     * @param showBlockingLoader false al tirar del refresh: no sustituye la lista por un estado vacío de carga.
     */
    fun refresh(showBlockingLoader: Boolean = true) {
        viewModelScope.launch {
            if (showBlockingLoader) {
                _uiState.value = _uiState.value.copy(loading = true, isRefreshing = false, error = null)
            } else {
                _uiState.value = _uiState.value.copy(isRefreshing = true, error = null)
            }
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("No active session")
                val rows = supabase
                    .from(BackendContracts.Tables.NOTIFICATIONS)
                    .select(columns = Columns.raw("id,type,title,body,created_at,is_read,data")) {
                        filter { eq("user_id", me) }
                        order("created_at", Order.DESCENDING)
                        limit(300)
                    }
                    .let { decodeFlexibleList<NotificationRow>(it.data) }

                rows.map { row ->
                    val workoutId = row.data?.get("workout_id")?.jsonPrimitive?.contentOrNull?.toIntOrNull()
                    val profileUserId = row.data?.get("follower_id")?.jsonPrimitive?.contentOrNull
                    NotificationItemUi(
                        id = row.id,
                        type = row.type ?: "notification",
                        title = row.title ?: "Notification",
                        body = row.body,
                        createdAt = row.createdAt,
                        isRead = row.isRead,
                        workoutId = workoutId,
                        profileUserId = profileUserId,
                        data = row.data
                    )
                }
            }.onSuccess { items ->
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    items = items,
                    unreadCount = items.count { !it.isRead }
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    error = e.message?.take(260) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun markAsRead(id: Int) {
        val current = _uiState.value.items.find { it.id == id } ?: return
        if (current.isRead) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            runCatching {
                @Serializable
                data class UpdatePayload(@SerialName("is_read") val isRead: Boolean)
                supabase.from(BackendContracts.Tables.NOTIFICATIONS).update(
                    UpdatePayload(isRead = true)
                ) {
                    filter {
                        eq("id", id)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                val updated = _uiState.value.items.map {
                    if (it.id == id) it.copy(isRead = true) else it
                }
                _uiState.value = _uiState.value.copy(
                    items = updated,
                    unreadCount = updated.count { item -> !item.isRead }
                )
                NotificationUnreadSync.notifyChanged()
            }
        }
    }

    fun deleteNotification(id: Int) {
        if (_uiState.value.deletingIds.contains(id)) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            _uiState.value = _uiState.value.copy(
                deletingIds = _uiState.value.deletingIds + id,
                error = null
            )
            runCatching {
                supabase.from(BackendContracts.Tables.NOTIFICATIONS).delete {
                    filter {
                        eq("id", id)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                val updated = _uiState.value.items.filterNot { it.id == id }
                _uiState.value = _uiState.value.copy(
                    items = updated,
                    unreadCount = updated.count { item -> !item.isRead },
                    deletingIds = _uiState.value.deletingIds - id
                )
                NotificationUnreadSync.notifyChanged()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    deletingIds = _uiState.value.deletingIds - id,
                    error = e.message?.take(260) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun deleteAllNotifications() {
        if (_uiState.value.deleteAllBusy) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            _uiState.value = _uiState.value.copy(deleteAllBusy = true, error = null)
            runCatching {
                supabase.from(BackendContracts.Tables.NOTIFICATIONS).delete {
                    filter { eq("user_id", me) }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    deleteAllBusy = false,
                    items = emptyList(),
                    unreadCount = 0,
                    deletingIds = emptySet()
                )
                NotificationUnreadSync.notifyChanged()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    deleteAllBusy = false,
                    error = e.message?.take(260) ?: e::class.java.simpleName
                )
            }
        }
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

class NotificationsViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != NotificationsViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return NotificationsViewModel(supabase) as T
    }
}
