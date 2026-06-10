package com.lilru.liftr.ui.pets

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.CoinManager
import com.lilru.liftr.data.PetFullDataWire
import com.lilru.liftr.data.PetMarketItemWire
import com.lilru.liftr.data.PetService
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class MarketUiState(
    val items: List<PetMarketItemWire> = emptyList(),
    val petData: PetFullDataWire? = null,
    val loading: Boolean = false,
    val incubating: Boolean = false,
    val upgradingRarity: Boolean = false,
    val upgradingEnergy: Boolean = false,
    val error: String? = null
)

class MarketViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val _ui = MutableStateFlow(MarketUiState())
    val uiState: StateFlow<MarketUiState> = _ui.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _ui.update { it.copy(loading = it.items.isEmpty(), error = null) }
            CoinManager.refreshBalance(supabase)
            runCatching {
                val items = PetService.fetchMarketItems(supabase)
                val pet = PetService.fetchMyPet(supabase)
                items to pet
            }.onSuccess { (items, pet) ->
                _ui.update { it.copy(items = items, petData = pet, loading = false) }
            }.onFailure { e ->
                _ui.update { it.copy(loading = false, error = e.message) }
            }
        }
    }

    fun buy(itemType: String, quantity: Int, onSuccess: () -> Unit) {
        viewModelScope.launch {
            runCatching { PetService.buyItem(supabase, itemType, quantity) }
                .onSuccess {
                    PetMarketPurchaseFeedback.recordPurchase(itemType)
                    refresh()
                    onSuccess()
                }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
        }
    }

    fun upgradeRarity(onSuccess: () -> Unit) {
        viewModelScope.launch {
            _ui.update { it.copy(upgradingRarity = true, error = null) }
            runCatching { PetService.upgradeRarity(supabase) }
                .onSuccess {
                    refresh()
                    onSuccess()
                }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
            _ui.update { it.copy(upgradingRarity = false) }
        }
    }

    fun upgradeEnergyCapacity(onSuccess: () -> Unit) {
        viewModelScope.launch {
            _ui.update { it.copy(upgradingEnergy = true, error = null) }
            runCatching { PetService.upgradeEnergyCapacity(supabase) }
                .onSuccess {
                    refresh()
                    onSuccess()
                }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
            _ui.update { it.copy(upgradingEnergy = false) }
        }
    }

    fun startIncubation(context: Context) {
        viewModelScope.launch {
            _ui.update { it.copy(incubating = true, error = null) }
            runCatching { PetService.startIncubation(supabase) }
                .onSuccess { hatchAtMs ->
                    refresh()
                    val petType = _ui.value.petData?.pet?.petType ?: "pet"
                    if (hatchAtMs != null) {
                        PetHatchLocalNotificationScheduler.schedule(context, hatchAtMs, petType)
                    }
                }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
            _ui.update { it.copy(incubating = false) }
        }
    }
}

class MarketViewModelFactory(
    private val supabase: SupabaseClient
) : androidx.lifecycle.ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return MarketViewModel(supabase) as T
    }
}
