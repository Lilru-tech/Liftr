package com.lilru.liftr.ui.pets

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.PetFullDataWire
import com.lilru.liftr.data.PetMarketItemWire
import com.lilru.liftr.data.PetService
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PetUserItemsUiState(
    val catalog: List<PetMarketItemWire> = emptyList(),
    val petData: PetFullDataWire? = null,
    val loading: Boolean = false,
    val incubating: Boolean = false,
    val error: String? = null
)

class PetUserItemsViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val _ui = MutableStateFlow(PetUserItemsUiState())
    val uiState: StateFlow<PetUserItemsUiState> = _ui.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _ui.update { it.copy(loading = it.petData == null, error = null) }
            runCatching {
                PetService.fetchMarketItems(supabase) to PetService.fetchMyPet(supabase)
            }.onSuccess { (catalog, pet) ->
                _ui.update { it.copy(catalog = catalog, petData = pet, loading = false) }
            }.onFailure { e ->
                _ui.update { it.copy(loading = false, error = e.message) }
            }
        }
    }

    fun startIncubation(context: Context, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _ui.update { it.copy(incubating = true, error = null) }
            runCatching { PetService.startIncubation(supabase) }
                .onSuccess { hatchAtMs ->
                    refresh()
                    val petType = _ui.value.petData?.pet?.petType ?: "pet"
                    if (hatchAtMs != null) {
                        PetHatchLocalNotificationScheduler.schedule(context, hatchAtMs, petType)
                    }
                    onSuccess()
                }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
            _ui.update { it.copy(incubating = false) }
        }
    }
}

class PetUserItemsViewModelFactory(
    private val supabase: SupabaseClient
) : androidx.lifecycle.ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return PetUserItemsViewModel(supabase) as T
    }
}
