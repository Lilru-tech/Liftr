package com.lilru.liftr.ui.pets

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.CoinManager
import com.lilru.liftr.data.PetFullDataWire
import com.lilru.liftr.data.PetLogWire
import com.lilru.liftr.data.PetRefreshBus
import com.lilru.liftr.data.PetService
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class PetUiState(
    val data: PetFullDataWire? = null,
    val logs: List<PetLogWire> = emptyList(),
    val hasMoreLogs: Boolean = true,
    val loading: Boolean = false,
    val error: String? = null,
    val feeding: Boolean = false,
    val evolving: Boolean = false,
    val rerolling: Boolean = false
)

class PetViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    private val _ui = MutableStateFlow(PetUiState())
    val uiState: StateFlow<PetUiState> = _ui.asStateFlow()
    private var pollJob: Job? = null
    private var logsOffset = 0
    private val logsPageSize = 5
    private var lastKnownStage: String? = null

    fun load() {
        viewModelScope.launch {
            _ui.update { it.copy(loading = it.data == null, error = null) }
            val previousStage = _ui.value.data?.pet?.evolutionStage ?: lastKnownStage
            runCatching { PetService.fetchMyPet(supabase) }
                .onSuccess { data ->
                    handleStageTransition(previousStage, data.pet?.evolutionStage)
                    _ui.update { it.copy(data = data, loading = false) }
                }
                .onFailure { e -> _ui.update { it.copy(loading = false, error = e.message) } }
        }
    }

    private fun handleStageTransition(previousStage: String?, newStage: String?) {
        if (newStage == null) return
        val wasEgg = previousStage.equals("egg", ignoreCase = true)
        val isBaby = newStage.equals("baby", ignoreCase = true)
        lastKnownStage = newStage
        if (wasEgg && isBaby) {
            PetHatchEventHandler.handleHatchEvent(navigateToProfile = false)
        }
    }

    fun reloadLogs() {
        viewModelScope.launch {
            logsOffset = 0
            runCatching { PetService.fetchPetLogs(supabase, 0, logsPageSize) }
                .onSuccess { page ->
                    logsOffset = page.size
                    _ui.update {
                        it.copy(
                            logs = page,
                            hasMoreLogs = page.size >= logsPageSize
                        )
                    }
                }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
        }
    }

    fun loadMoreLogs() {
        viewModelScope.launch {
            if (!_ui.value.hasMoreLogs) return@launch
            runCatching { PetService.fetchPetLogs(supabase, logsOffset, logsPageSize) }
                .onSuccess { page ->
                    logsOffset += page.size
                    _ui.update {
                        it.copy(
                            logs = it.logs + page,
                            hasMoreLogs = page.size >= logsPageSize
                        )
                    }
                }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
        }
    }

    fun deleteAllLogs() {
        viewModelScope.launch {
            runCatching { PetService.deleteAllPetLogs(supabase) }
                .onSuccess {
                    logsOffset = 0
                    _ui.update { it.copy(logs = emptyList(), hasMoreLogs = false) }
                }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
        }
    }

    fun startPollingIfNeeded() {
        if (pollJob != null) return
        pollJob = viewModelScope.launch {
            while (isActive) {
                val pet = _ui.value.data?.pet
                val shouldPoll = pet != null && (
                    PetService.isIncubating(pet) || PetService.isPendingHatch(pet)
                    )
                if (shouldPoll) {
                    load()
                    delay(30_000)
                } else {
                    delay(5_000)
                    val p = _ui.value.data?.pet
                    if (p == null || (!PetService.isIncubating(p) && !PetService.isPendingHatch(p))) break
                }
            }
            pollJob = null
        }
    }

    fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    fun feed(itemType: String) {
        viewModelScope.launch {
            _ui.update { it.copy(feeding = true, error = null) }
            runCatching { PetService.feed(supabase, itemType) }
                .onSuccess { load() }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
            _ui.update { it.copy(feeding = false) }
        }
    }

    fun confirmEvolution() {
        viewModelScope.launch {
            _ui.update { it.copy(evolving = true, error = null) }
            runCatching { PetService.confirmEvolution(supabase) }
                .onSuccess { load() }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
            _ui.update { it.copy(evolving = false) }
        }
    }

    fun updateName(name: String) {
        viewModelScope.launch {
            runCatching { PetService.updateName(supabase, name) }
                .onSuccess { load() }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
        }
    }

    fun rerollEgg(context: Context) {
        viewModelScope.launch {
            _ui.update { it.copy(rerolling = true, error = null) }
            runCatching { PetService.rerollEgg(supabase) }
                .onSuccess { hatchAtMs ->
                    load()
                    CoinManager.refreshBalanceAfterMutation(supabase)
                    val petType = _ui.value.data?.pet?.petType ?: "pet"
                    if (hatchAtMs != null) {
                        PetHatchLocalNotificationScheduler.schedule(context, hatchAtMs, petType)
                    }
                }
                .onFailure { e -> _ui.update { it.copy(error = e.message) } }
            _ui.update { it.copy(rerolling = false) }
        }
    }

    override fun onCleared() {
        stopPolling()
        super.onCleared()
    }
}

class PetViewModelFactory(
    private val supabase: SupabaseClient
) : androidx.lifecycle.ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return PetViewModel(supabase) as T
    }
}
