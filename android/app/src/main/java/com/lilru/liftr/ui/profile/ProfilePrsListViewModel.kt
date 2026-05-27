package com.lilru.liftr.ui.profile

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
private data class PrListWire(
    val kind: String,
    @SerialName("user_id") val userId: String,
    val label: String,
    val metric: String,
    val value: Double,
    @SerialName("achieved_at") val achievedAt: String? = null
) {
    fun toRow() = ProfilePrListRow(
        kind = kind,
        label = label,
        metric = metric,
        value = value,
        achievedAt = achievedAt
    )
}

data class ProfilePrsListUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val rows: List<ProfilePrListRow> = emptyList(),
    val filter: PrKindFilter = PrKindFilter.ALL,
    val searchQuery: String = ""
)

class ProfilePrsListViewModel(
    private val supabase: SupabaseClient,
    private val userId: String
) : ViewModel() {
    private companion object {
        const val TAG = "ProfilePrsListVM"
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val _uiState = MutableStateFlow(ProfilePrsListUiState())
    val uiState: StateFlow<ProfilePrsListUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun setFilter(f: PrKindFilter) {
        val old = _uiState.value.filter
        if (old == f) return
        _uiState.update { it.copy(filter = f) }
        load()
    }

    fun setSearchQuery(q: String) {
        _uiState.update { it.copy(searchQuery = q) }
    }

    private fun load() {
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true, error = null) } // mantiene filas hasta nueva carga
            val f = _uiState.value.filter
            val result = runCatching {
                val params = buildJsonObject {
                    put("p_user_id", userId)
                    if (f != PrKindFilter.ALL) put("p_kind", kindWire(f))
                }
                val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_USER_PRS, params) { }
                decodeFlexibleList<PrListWire>(res.data).map { it.toRow() }
            }
            result.onSuccess { rows ->
                _uiState.update { it.copy(loading = false, error = null, rows = rows) }
            }.onFailure { e ->
                Log.w(TAG, "load failed", e)
                _uiState.update {
                    it.copy(
                        loading = false,
                        error = e.message?.take(400) ?: e::class.java.simpleName
                    )
                }
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

private fun kindWire(f: PrKindFilter): String = when (f) {
    PrKindFilter.STRENGTH -> "strength"
    PrKindFilter.CARDIO -> "cardio"
    PrKindFilter.SPORT -> "sport"
    PrKindFilter.ALL -> "strength" // no usado
}

class ProfilePrsListViewModelFactory(
    private val supabase: SupabaseClient,
    private val userId: String
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ProfilePrsListViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ProfilePrsListViewModel(supabase, userId) as T
    }
}
