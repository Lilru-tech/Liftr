package com.lilru.liftr.ui.pets

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.PetRarityConfigWire
import com.lilru.liftr.data.PetService
import com.lilru.liftr.data.PetTypeCatalogWire
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PetHelpUiState(
    val loading: Boolean = true,
    val rarities: List<PetRarityConfigWire> = emptyList(),
    val species: List<PetTypeCatalogWire> = emptyList(),
    val error: String? = null
)

class PetHelpViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val _ui = MutableStateFlow(PetHelpUiState())
    val uiState: StateFlow<PetHelpUiState> = _ui.asStateFlow()

    private var loaded = false

    fun loadIfNeeded() {
        if (loaded && _ui.value.error == null && _ui.value.species.isNotEmpty()) return
        viewModelScope.launch {
            _ui.update { it.copy(loading = it.species.isEmpty(), error = null) }
            runCatching {
                val rarities = PetService.fetchRarityConfig(supabase)
                val species = PetService.fetchPetTypeCatalog(supabase)
                rarities to species
            }.onSuccess { (rarities, species) ->
                loaded = true
                _ui.update {
                    it.copy(
                        loading = false,
                        rarities = rarities,
                        species = species,
                        error = null
                    )
                }
            }.onFailure { err ->
                _ui.update {
                    it.copy(
                        loading = false,
                        error = err.message ?: "Failed to load pet guide"
                    )
                }
            }
        }
    }

    fun retry() {
        loaded = false
        loadIfNeeded()
    }
}

class PetHelpViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return PetHelpViewModel(supabase) as T
    }
}
