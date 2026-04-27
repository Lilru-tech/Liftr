package com.lilru.liftr.ui.profile

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
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
private data class PrRowWire(
    val kind: String,
    @SerialName("user_id") val userId: String,
    val label: String,
    val metric: String,
    val value: Double,
    @SerialName("achieved_at") val achievedAt: String? = null
)

data class ComparePrsSection(
    val title: String,
    val items: List<ComparePrsMergedRow>
)

data class ComparePrsMergedRow(
    val id: String,
    val kind: String,
    val label: String,
    val metric: String,
    val myValue: Double?,
    val otherValue: Double?,
    val winner: PrWinner
)

data class ComparePrsUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val sections: List<ComparePrsSection> = emptyList(),
    val tallyMe: Int = 0,
    val tallyTies: Int = 0,
    val tallyOther: Int = 0
)

private data class PrKey(
    val kind: String,
    val label: String,
    val metric: String
)

class ComparePrsViewModel(
    private val supabase: SupabaseClient,
    private val myUserId: String,
    private val otherUserId: String
) : ViewModel() {
    private companion object {
        const val TAG = "ComparePrsVM"
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val _uiState = MutableStateFlow(ComparePrsUiState())
    val uiState: StateFlow<ComparePrsUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            _uiState.value = ComparePrsUiState(loading = true, error = null)
            val result = runCatching {
                coroutineScope {
                    val a = async { fetchPrs(myUserId) }
                    val b = async { fetchPrs(otherUserId) }
                    buildMerged(a.await(), b.await())
                }
            }
            result.onSuccess { m ->
                _uiState.value = ComparePrsUiState(
                    loading = false,
                    error = null,
                    sections = m.sections,
                    tallyMe = m.tallyMe,
                    tallyTies = m.tallyTies,
                    tallyOther = m.tallyOther
                )
            }.onFailure { e ->
                Log.w(TAG, "load failed", e)
                _uiState.value = ComparePrsUiState(
                    loading = false,
                    error = e.message?.take(400) ?: e::class.java.simpleName
                )
            }
        }
    }

    private suspend fun fetchPrs(userId: String): List<PrRowWire> {
        val res = supabase
            .from(BackendContracts.Views.VW_USER_PRS)
            .select(
                columns = Columns.raw("kind, user_id, label, metric, value, achieved_at")
            ) {
                filter { eq("user_id", userId) }
                order("achieved_at", Order.DESCENDING)
            }
        return decodeFlexibleList(res.data)
    }

    private data class Merged(
        val sections: List<ComparePrsSection>,
        val tallyMe: Int,
        val tallyTies: Int,
        val tallyOther: Int
    )

    private fun buildMerged(mine: List<PrRowWire>, other: List<PrRowWire>): Merged {
        val byMine = mine.groupBy { PrKey(it.kind, it.label, it.metric) }
        val byOther = other.groupBy { PrKey(it.kind, it.label, it.metric) }
        val commonKeys = byMine.keys.intersect(byOther.keys)
        val rows = commonKeys.map { k ->
            val a = bestRow(byMine[k] ?: emptyList())
            val b = bestRow(byOther[k] ?: emptyList())
            val w = ComparePrsFormat.winner(k.metric, a?.value, b?.value)
            ComparePrsMergedRow(
                id = "${k.kind}|${k.label}|${k.metric}",
                kind = k.kind,
                label = k.label,
                metric = k.metric,
                myValue = a?.value,
                otherValue = b?.value,
                winner = w
            )
        }
        val byTitle = rows.groupBy { sectionTitleForKind(it.kind) }
        val sections = byTitle.keys.sorted().map { title ->
            ComparePrsSection(
                title = title,
                items = (byTitle[title] ?: emptyList()).sortedBy { it.label }
            )
        }
        var me = 0
        var ties = 0
        var oth = 0
        for (r in rows) {
            when (r.winner) {
                PrWinner.Me -> me++
                PrWinner.Tie -> ties++
                PrWinner.Other -> oth++
                PrWinner.Unknown -> {}
            }
        }
        return Merged(sections, me, ties, oth)
    }

    private fun bestRow(rows: List<PrRowWire>): PrRowWire? {
        if (rows.isEmpty()) return null
        return rows.maxByOrNull { r -> timeKey(r.achievedAt) }
    }

    private fun timeKey(iso: String?): Long =
        if (iso.isNullOrBlank()) 0L else {
            runCatching { Instant.parse(iso.trim()).toEpochMilli() }.getOrDefault(0L)
        }

    private fun sectionTitleForKind(k: String): String = when (k.lowercase()) {
        "strength" -> "Strength"
        "cardio" -> "Cardio"
        "sport" -> "Sport"
        else -> "Other"
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

class ComparePrsViewModelFactory(
    private val supabase: SupabaseClient,
    private val myUserId: String,
    private val otherUserId: String
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ComparePrsViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ComparePrsViewModel(supabase, myUserId, otherUserId) as T
    }
}
