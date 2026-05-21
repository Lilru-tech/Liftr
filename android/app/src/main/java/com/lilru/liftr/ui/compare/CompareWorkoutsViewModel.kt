package com.lilru.liftr.ui.compare

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CompareWorkoutsUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val labels: CompareSessionLabels? = null,
    val metrics: List<CompareMetricRow> = emptyList()
)

class CompareWorkoutsViewModel(
    private val supabase: SupabaseClient,
    val currentWorkoutId: Int,
    val other: CompareOtherTarget,
    private val averageRightLabel: String?
) : ViewModel() {
    private companion object {
        const val TAG = "CompareWorkoutsVM"
    }

    private val _uiState = MutableStateFlow(CompareWorkoutsUiState())
    val uiState: StateFlow<CompareWorkoutsUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = CompareWorkoutsUiState(loading = true, error = null)
            val r = loadCompareWorkoutData(
                supabase = supabase,
                currentWorkoutId = currentWorkoutId,
                other = other,
                averageRightLabel = averageRightLabel
            )
            r.onSuccess { data ->
                _uiState.value = CompareWorkoutsUiState(
                    loading = false,
                    error = null,
                    labels = data.labels,
                    metrics = data.metrics
                )
            }.onFailure { e ->
                Log.w(TAG, "load failed", e)
                _uiState.value = CompareWorkoutsUiState(
                    loading = false,
                    error = e.message?.take(500) ?: e::class.java.simpleName
                )
            }
        }
    }
}

class CompareWorkoutsViewModelFactory(
    private val supabase: SupabaseClient,
    private val currentWorkoutId: Int,
    private val other: CompareOtherTarget,
    private val averageRightLabel: String?
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != CompareWorkoutsViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return CompareWorkoutsViewModel(
            supabase,
            currentWorkoutId,
            other,
            averageRightLabel
        ) as T
    }
}
