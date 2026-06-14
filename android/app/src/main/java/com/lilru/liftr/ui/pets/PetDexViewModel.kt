package com.lilru.liftr.ui.pets

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.PetDexDataWire
import com.lilru.liftr.data.PetRarityConfigWire
import com.lilru.liftr.data.PetService
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PetDexUiState(
    val loading: Boolean = true,
    val data: PetDexDataWire? = null,
    val rarities: List<PetRarityConfigWire> = emptyList(),
    val error: String? = null
)

class PetDexViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val _uiState = MutableStateFlow(PetDexUiState())
    val uiState: StateFlow<PetDexUiState> = _uiState.asStateFlow()

    init {
        loadIfNeeded()
    }

    fun loadIfNeeded() {
        if (_uiState.value.data != null && _uiState.value.error == null) return
        load(force = _uiState.value.data == null)
    }

    fun retry() {
        load(force = true)
    }

    private fun load(force: Boolean) {
        viewModelScope.launch {
            _uiState.update { it.copy(loading = force || it.data == null, error = null) }
            runCatching {
                val dex = PetService.fetchMyPetDex(supabase)
                val rarities = PetService.fetchRarityConfig(supabase)
                dex to rarities
            }
                .onSuccess { (data, rarities) ->
                    _uiState.update { it.copy(loading = false, data = data, rarities = rarities, error = null) }
                }
                .onFailure { err ->
                    _uiState.update {
                        it.copy(
                            loading = false,
                            error = err.message ?: "Failed to load Pet Dex"
                        )
                    }
                }
        }
    }
}

class PetDexViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return PetDexViewModel(supabase) as T
    }
}
