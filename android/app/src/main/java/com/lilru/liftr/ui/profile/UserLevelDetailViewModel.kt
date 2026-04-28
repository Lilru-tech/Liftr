package com.lilru.liftr.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
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
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.OffsetDateTime
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

data class XpEventUiModel(
    val id: String,
    val createdAtMs: Long,
    val gainedXp: Long
)

data class XpStatsForKind(
    val kindLabel: String,
    val eventCount: Int,
    val totalXp: Long,
    val maxXp: Long,
    val avgXp: Double
)

data class XpStatsSummary(
    val sampledEventCount: Int,
    val totalXpFromSample: Long,
    val maxSingleAward: Long,
    val avgPerEvent: Double,
    val byKind: List<XpStatsForKind>,
    val bonusNoWorkoutEventCount: Int,
    val bonusNoWorkoutTotalXp: Long,
    val orphanWorkoutRefEventCount: Int,
    val orphanWorkoutRefTotalXp: Long
)

data class LevelMilestone(
    val level: Int,
    val xpRequired: Long
)

data class UserLevelDetailUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val level: Int = 1,
    val xp: Long = 0,
    val lastActivityAtMs: Long? = null,
    val nextLevelThresholdXp: Long? = null,
    val milestones: List<LevelMilestone> = emptyList(),
    val xpEvents: List<XpEventUiModel> = emptyList(),
    val xpEventsFailed: Boolean = false,
    val xpEventsCanLoadMore: Boolean = false,
    val xpEventsLoadingMore: Boolean = false,
    val xpStatsSummary: XpStatsSummary? = null,
    val xpStatsLoading: Boolean = false
) {
    val progressRatio: Double
        get() {
            val cap = nextLevelThresholdXp ?: return 0.0
            if (cap <= 0) return 0.0
            return min(1.0, max(0.0, xp.toDouble() / cap.toDouble()))
        }

    val xpToNextLevel: Long?
        get() {
            val cap = nextLevelThresholdXp ?: return null
            return max(0, cap - xp)
        }
}

@Serializable
private data class GetUserLevelRow(
    val level: Int = 1,
    val xp: Long = 0,
    @SerialName("last_activity_at") val lastActivityAt: String? = null
)

private data class ParsedXpStatEvent(
    val gained: Long,
    val workoutId: Int?
)

class UserLevelDetailViewModel(
    private val supabase: SupabaseClient,
    private val userId: String
) : ViewModel() {
    private val json = Json { ignoreUnknownKeys = true }
    private val pageSize = 10L
    private val statsSampleLimit = 800L

    private val _uiState = MutableStateFlow(UserLevelDetailUiState())
    val uiState: StateFlow<UserLevelDetailUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun loadMoreXpEvents() {
        val st = _uiState.value
        if (st.xpEventsLoadingMore || !st.xpEventsCanLoadMore || st.xpEventsFailed) return
        viewModelScope.launch {
            val currentCount = st.xpEvents.size
            _uiState.update { it.copy(xpEventsLoadingMore = true) }
            runCatching {
                val offset = currentCount
                val res = supabase
                    .from(BackendContracts.Tables.XP_EVENTS)
                    .select {
                        filter { eq("user_id", userId) }
                        order("created_at", Order.DESCENDING)
                        range(offset.toLong(), offset.toLong() + pageSize - 1L)
                    }
                parseXpEventsPage(res.data)
            }.onSuccess { newRows ->
                _uiState.update { s ->
                    val existing = s.xpEvents.map { it.id }.toSet()
                    val merged = newRows.filter { it.id !in existing }
                    if (newRows.isEmpty() || merged.isEmpty()) {
                        s.copy(
                            xpEventsCanLoadMore = false,
                            xpEventsLoadingMore = false
                        )
                    } else {
                        s.copy(
                            xpEvents = s.xpEvents + merged,
                            xpEventsCanLoadMore = newRows.size >= pageSize.toInt(),
                            xpEventsLoadingMore = false
                        )
                    }
                }
            }.onFailure {
                _uiState.update { it.copy(xpEventsCanLoadMore = false, xpEventsLoadingMore = false) }
            }
        }
    }

    private fun load() {
        viewModelScope.launch {
            _uiState.value = UserLevelDetailUiState(loading = true, error = null, xpStatsLoading = false)
            runCatching {
                val res = supabase.postgrest.rpc(
                    BackendContracts.Rpc.GET_USER_LEVEL,
                    buildJsonObject { put("p_user", userId) }
                ) { }
                val levelRow = decodeFlexibleList<GetUserLevelRow>(res.data).firstOrNull()
                val lv = levelRow?.level ?: 1
                val totalXp = levelRow?.xp ?: 0L
                val lastMs = parseLastActivityToEpochMs(levelRow?.lastActivityAt)

                val nextRows = supabase
                    .from(BackendContracts.Tables.LEVEL_THRESHOLDS)
                    .select(columns = Columns.raw("level,xp_required")) {
                        filter { eq("level", lv + 1) }
                        limit(1)
                    }
                val nextCap = decodeFlexibleList<LevelThresholdRow>(nextRows.data).firstOrNull()?.xpRequired

                val msLevels = listOf(lv + 1, lv + 2, lv + 3)
                val levelAny: List<Any> = msLevels.map { it as Any }
                val msRes = supabase
                    .from(BackendContracts.Tables.LEVEL_THRESHOLDS)
                    .select(columns = Columns.raw("level,xp_required")) {
                        filter { isIn("level", levelAny) }
                        order("level", Order.ASCENDING)
                    }
                val milestones = decodeFlexibleList<LevelThresholdRow>(msRes.data).map {
                    LevelMilestone(it.level, it.xpRequired)
                }

                val (firstPage, evFailed) = runCatching {
                    val r = supabase
                        .from(BackendContracts.Tables.XP_EVENTS)
                        .select {
                            filter { eq("user_id", userId) }
                            order("created_at", Order.DESCENDING)
                            range(0L, pageSize - 1)
                        }
                    parseXpEventsPage(r.data)
                }.fold(
                    onSuccess = { it to false },
                    onFailure = { emptyList<XpEventUiModel>() to true }
                )

                _uiState.value = UserLevelDetailUiState(
                    loading = false,
                    error = null,
                    level = lv,
                    xp = totalXp,
                    lastActivityAtMs = firstPage.firstOrNull()?.createdAtMs ?: lastMs,
                    nextLevelThresholdXp = nextCap,
                    milestones = milestones,
                    xpEvents = firstPage,
                    xpEventsFailed = evFailed,
                    xpEventsCanLoadMore = firstPage.size >= pageSize,
                    xpStatsLoading = true
                )
            }.onFailure {
                _uiState.value = UserLevelDetailUiState(
                    loading = false,
                    error = "Couldn’t load level data."
                )
                return@launch
            }
            if (_uiState.value.error == null) {
                loadXpStatsSummary()
            }
        }
    }

    private suspend fun loadXpStatsSummary() {
        _uiState.update { it.copy(xpStatsLoading = true, xpStatsSummary = null) }
        runCatching {
            val r = supabase
                .from(BackendContracts.Tables.XP_EVENTS)
                .select {
                    filter { eq("user_id", userId) }
                    order("created_at", Order.DESCENDING)
                    range(0L, statsSampleLimit - 1)
                }
            val events = parseXpEventsForStats(r.data)
            if (events.isEmpty()) {
                _uiState.update { it.copy(xpStatsLoading = false, xpStatsSummary = null) }
                return
            }
            val workoutIds = events.mapNotNull { it.workoutId }.distinct()
            val kindById = fetchWorkoutKinds(workoutIds)
            val summary = buildXpStatsSummary(events, kindById)
            _uiState.update { it.copy(xpStatsLoading = false, xpStatsSummary = summary) }
        }.onFailure {
            _uiState.update { it.copy(xpStatsLoading = false, xpStatsSummary = null) }
        }
    }

    private suspend fun fetchWorkoutKinds(ids: List<Int>): Map<Int, String> {
        if (ids.isEmpty()) return emptyMap()
        val out = mutableMapOf<Int, String>()
        var idx = 0
        while (idx < ids.size) {
            val chunk = ids.subList(idx, min(idx + 100, ids.size))
            idx += chunk.size
            val wres = supabase
                .from(BackendContracts.Tables.WORKOUTS)
                .select(columns = Columns.raw("id,kind")) {
                    filter {
                        eq("user_id", userId)
                        isIn("id", chunk.map { it as Any })
                    }
                }
            val arr = JSONArray(wres.data)
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val id = o.optInt("id", -1)
                if (id < 0) continue
                val k = o.optString("kind", "")
                if (k.isNotEmpty()) out[id] = k
            }
        }
        return out
    }

    private fun buildXpStatsSummary(
        events: List<ParsedXpStatEvent>,
        workoutKindById: Map<Int, String>
    ): XpStatsSummary {
        var bonusNo = 0
        var bonusSum = 0L
        var orphanC = 0
        var orphanS = 0L
        val bucket = mutableMapOf<String, Triple<Int, Long, Long>>()
        for (e in events) {
            if (e.workoutId == null) {
                bonusNo += 1
                bonusSum += e.gained
                continue
            }
            val wid = e.workoutId
            val raw = workoutKindById[wid]
            if (raw == null) {
                orphanC += 1
                orphanS += e.gained
            } else {
                val label = normalizedWorkoutKindLabel(raw)
                val t = bucket[label] ?: Triple(0, 0L, 0L)
                val newMax = max(t.third, e.gained)
                bucket[label] = Triple(
                    t.first + 1,
                    t.second + e.gained,
                    newMax
                )
            }
        }
        val total = events.sumOf { it.gained }
        val maxSingle = events.maxOfOrNull { it.gained } ?: 0L
        val avg = if (events.isEmpty()) 0.0 else total.toDouble() / events.size
        val order = listOf("Strength", "Cardio", "Sport", "Other")
        val byKind = order.mapNotNull { lab ->
            val b = bucket[lab] ?: return@mapNotNull null
            if (b.first == 0) return@mapNotNull null
            val avgK = b.second.toDouble() / b.first
            XpStatsForKind(
                kindLabel = lab,
                eventCount = b.first,
                totalXp = b.second,
                maxXp = b.third,
                avgXp = avgK
            )
        }
        return XpStatsSummary(
            sampledEventCount = events.size,
            totalXpFromSample = total,
            maxSingleAward = maxSingle,
            avgPerEvent = avg,
            byKind = byKind,
            bonusNoWorkoutEventCount = bonusNo,
            bonusNoWorkoutTotalXp = bonusSum,
            orphanWorkoutRefEventCount = orphanC,
            orphanWorkoutRefTotalXp = orphanS
        )
    }

    private fun normalizedWorkoutKindLabel(raw: String): String = when (raw.trim().lowercase(Locale.ROOT)) {
        "strength" -> "Strength"
        "cardio" -> "Cardio"
        "sport" -> "Sport"
        else -> "Other"
    }

    private fun parseXpEventsForStats(raw: String): List<ParsedXpStatEvent> {
        return runCatching {
            val arr = JSONArray(raw)
            val amountKeys = listOf(
                "xp_delta", "amount", "xp", "points", "value", "delta",
                "xp_awarded", "xp_amount", "change", "awarded_xp"
            )
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val gained = firstInt64(o, amountKeys)
                val wid = firstWorkoutId(o)
                ParsedXpStatEvent(gained, wid)
            }
        }.getOrDefault(emptyList())
    }

    private fun parseXpEventsPage(raw: String): List<XpEventUiModel> {
        return runCatching {
            val arr = JSONArray(raw)
            val amountKeys = listOf(
                "xp_delta", "amount", "xp", "points", "value", "delta",
                "xp_awarded", "xp_amount", "change", "awarded_xp"
            )
            val out = mutableListOf<XpEventUiModel>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val created = firstDateMs(o) ?: continue
                val gained = firstInt64(o, amountKeys)
                val idBase = o.optLong("id", o.optInt("id", i).toLong())
                out.add(
                    XpEventUiModel(
                        id = "$idBase-$created",
                        createdAtMs = created,
                        gainedXp = gained
                    )
                )
            }
            out
        }.getOrDefault(emptyList())
    }

    private fun firstDateMs(o: JSONObject): Long? {
        val keys = listOf("created_at", "inserted_at", "occurred_at")
        for (k in keys) {
            if (o.isNull(k)) continue
            val s = o.optString(k, "")
            if (s.isBlank()) continue
            parseLastActivityToEpochMs(s)?.let { return it }
        }
        return null
    }

    private fun firstInt64(o: JSONObject, keys: List<String>): Long {
        for (k in keys) {
            when (val v = o.opt(k)) {
                is Number -> return v.toLong()
                is String -> v.toLongOrNull()?.let { return it }
            }
        }
        return 0L
    }

    private fun firstWorkoutId(o: JSONObject): Int? {
        val keys = listOf("workout_id", "workoutId", "workout", "ref_workout_id")
        for (k in keys) {
            when (val v = o.opt(k)) {
                is Number -> return v.toInt()
                is String -> v.toIntOrNull()?.let { return it }
            }
        }
        return null
    }

    private fun parseLastActivityToEpochMs(raw: String?): Long? {
        if (raw.isNullOrBlank()) return null
        return runCatching { Instant.parse(raw).toEpochMilli() }.getOrNull()
            ?: runCatching { OffsetDateTime.parse(raw).toInstant().toEpochMilli() }.getOrNull()
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

class UserLevelDetailViewModelFactory(
    private val supabase: SupabaseClient,
    private val userId: String
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != UserLevelDetailViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return UserLevelDetailViewModel(supabase, userId) as T
    }
}
