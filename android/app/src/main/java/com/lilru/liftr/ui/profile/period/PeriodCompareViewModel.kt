package com.lilru.liftr.ui.profile.period

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.add.FollowEdge
import com.lilru.liftr.ui.add.ProfileLite
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale

enum class PeriodCompareDatePreset {
    /** Last 7 days (B) vs the 7 days before that (A). */
    SEVEN_VS_PRIOR_SEVEN,
    /** This calendar week so far (B) vs the same weekday span last week (A). */
    WEEK_THIS_VS_ALIGNED_PRIOR,
    /** Last 28 days (B) vs the 28 days before that (A). */
    TWENTY_EIGHT_VS_PRIOR_TWENTY_EIGHT
}

enum class PeriodCompareKind(val wire: String) {
    ALL("all"),
    STRENGTH("strength"),
    CARDIO("cardio"),
    SPORT("sport")
}

data class PeriodSummaryUi(
    val workoutCount: Int = 0,
    val durationMin: Long = 0,
    val caloriesKcal: Double = 0.0,
    val score: Double = 0.0,
    val distanceKm: Double = 0.0,
    val volumeKg: Double = 0.0
)

data class BreakdownRowUi(
    val label: String,
    val workoutCount: Int,
    val durationMin: Long,
    val caloriesKcal: Double,
    val score: Double,
    val distanceKm: Double,
    val volumeKg: Double
)

data class PeriodSideUi(
    val summary: PeriodSummaryUi,
    val breakdown: List<BreakdownRowUi>
)

data class PeriodCompareUiState(
    val loading: Boolean = false,
    val loadingFollowees: Boolean = false,
    val error: String? = null,
    val followees: List<ProfileLite> = emptyList(),
    val kind: PeriodCompareKind = PeriodCompareKind.ALL,
    /** Segundo usuario (periodo B). Igual que [viewerUserId] = comparar dos ventanas propias. */
    val userBId: String? = null,
    val localZone: ZoneId = ZoneId.systemDefault(),
    val periodAStart: LocalDate = LocalDate.now().minusWeeks(2),
    val periodAEndInclusive: LocalDate = LocalDate.now().minusWeeks(1).minusDays(1),
    val periodBStart: LocalDate = LocalDate.now().minusWeeks(1),
    val periodBEndInclusive: LocalDate = LocalDate.now(),
    val resultA: PeriodSideUi? = null,
    val resultB: PeriodSideUi? = null
)

class PeriodCompareViewModel(
    private val supabase: SupabaseClient,
    private val viewerUserId: String
) : ViewModel() {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }
    private val _ui = MutableStateFlow(PeriodCompareUiState(userBId = viewerUserId))
    val uiState: StateFlow<PeriodCompareUiState> = _ui.asStateFlow()

    init {
        loadFollowees()
    }

    fun setKind(k: PeriodCompareKind) {
        _ui.update { it.copy(kind = k) }
    }

    fun setUserB(id: String) {
        _ui.update { it.copy(userBId = id) }
    }

    fun setPeriodAStart(d: LocalDate) {
        _ui.update { it.copy(periodAStart = d) }
    }

    fun setPeriodAEndInclusive(d: LocalDate) {
        _ui.update { it.copy(periodAEndInclusive = d) }
    }

    fun setPeriodBStart(d: LocalDate) {
        _ui.update { it.copy(periodBStart = d) }
    }

    fun setPeriodBEndInclusive(d: LocalDate) {
        _ui.update { it.copy(periodBEndInclusive = d) }
    }

    /**
     * Applies a quick date-range preset using [PeriodCompareUiState.localZone] and [locale]’s first day of week.
     *
     * When [comparingWithSelf] is false (you vs someone else), **A and B share the same calendar window** so
     * totals are comparable. Split consecutive windows only make sense for yo-vs-yo.
     */
    fun applyDatePreset(preset: PeriodCompareDatePreset, locale: Locale, comparingWithSelf: Boolean) {
        val zone = _ui.value.localZone
        val today = LocalDate.now(zone)
        when (preset) {
            PeriodCompareDatePreset.SEVEN_VS_PRIOR_SEVEN -> {
                val bEnd = today
                val bStart = today.minusDays(6)
                if (!comparingWithSelf) {
                    _ui.update {
                        it.copy(
                            periodAStart = bStart,
                            periodAEndInclusive = bEnd,
                            periodBStart = bStart,
                            periodBEndInclusive = bEnd
                        )
                    }
                } else {
                    _ui.update {
                        it.copy(
                            periodBEndInclusive = bEnd,
                            periodBStart = bStart,
                            periodAEndInclusive = today.minusDays(7),
                            periodAStart = today.minusDays(13)
                        )
                    }
                }
            }
            PeriodCompareDatePreset.WEEK_THIS_VS_ALIGNED_PRIOR -> {
                val wf = WeekFields.of(locale)
                val thisWeekStart = today.with(TemporalAdjusters.previousOrSame(wf.firstDayOfWeek))
                val daysSpan = ChronoUnit.DAYS.between(thisWeekStart, today).toInt() + 1
                if (!comparingWithSelf) {
                    _ui.update {
                        it.copy(
                            periodAStart = thisWeekStart,
                            periodAEndInclusive = today,
                            periodBStart = thisWeekStart,
                            periodBEndInclusive = today
                        )
                    }
                } else {
                    val aStart = thisWeekStart.minusWeeks(1)
                    val aEnd = aStart.plusDays((daysSpan - 1).toLong())
                    _ui.update {
                        it.copy(
                            periodAStart = aStart,
                            periodAEndInclusive = aEnd,
                            periodBStart = thisWeekStart,
                            periodBEndInclusive = today
                        )
                    }
                }
            }
            PeriodCompareDatePreset.TWENTY_EIGHT_VS_PRIOR_TWENTY_EIGHT -> {
                val bEnd = today
                val bStart = today.minusDays(27)
                if (!comparingWithSelf) {
                    _ui.update {
                        it.copy(
                            periodAStart = bStart,
                            periodAEndInclusive = bEnd,
                            periodBStart = bStart,
                            periodBEndInclusive = bEnd
                        )
                    }
                } else {
                    _ui.update {
                        it.copy(
                            periodBEndInclusive = bEnd,
                            periodBStart = bStart,
                            periodAEndInclusive = today.minusDays(28),
                            periodAStart = today.minusDays(55)
                        )
                    }
                }
            }
        }
    }

    private fun loadFollowees() {
        viewModelScope.launch {
            _ui.update { it.copy(loadingFollowees = true) }
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("session")
                val edgeRes = supabase.from(BackendContracts.Tables.FOLLOWS)
                    .select(columns = Columns.raw("followee_id")) {
                        filter { eq("follower_id", me) }
                        limit(500)
                    }
                val ids = runCatching {
                    json.decodeFromString<List<FollowEdge>>(edgeRes.data).mapNotNull { it.followeeId }
                }.getOrDefault(emptyList())
                if (ids.isEmpty()) return@runCatching emptyList()
                val profileRes = supabase.from(BackendContracts.Tables.PROFILES)
                    .select(columns = Columns.raw("user_id, username, avatar_url")) {
                        filter { isIn("user_id", ids) }
                        order("username", Order.ASCENDING)
                    }
                json.decodeFromString<List<ProfileLite>>(profileRes.data)
            }.onSuccess { list ->
                _ui.update { it.copy(loadingFollowees = false, followees = list) }
            }.onFailure { e ->
                _ui.update {
                    it.copy(loadingFollowees = false, error = e.message?.take(300) ?: e::class.java.simpleName)
                }
            }
        }
    }

    fun compare() {
        viewModelScope.launch {
            val st = _ui.value
            _ui.update { it.copy(loading = true, error = null, resultA = null, resultB = null) }
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("session")
                val userB = st.userBId?.takeIf { it.isNotBlank() } ?: me
                val zone = st.localZone
                val aStart = st.periodAStart.atStartOfDay(zone).toInstant()
                val aEnd = st.periodAEndInclusive.plusDays(1).atStartOfDay(zone).toInstant()
                val bStart = st.periodBStart.atStartOfDay(zone).toInstant()
                val bEnd = st.periodBEndInclusive.plusDays(1).atStartOfDay(zone).toInstant()
                if (!aEnd.isAfter(aStart) || !bEnd.isAfter(bStart)) {
                    error("invalid_range")
                }
                val params = buildJsonObject {
                    put("p_user_a", me)
                    put("p_user_b", userB)
                    put("p_kind", st.kind.wire)
                    put("p_a_start", aStart.toString())
                    put("p_a_end", aEnd.toString())
                    put("p_b_start", bStart.toString())
                    put("p_b_end", bEnd.toString())
                }
                val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_PERIOD_TRAINING_COMPARE_V1, params) { }
                val root = parseRpcJsonObject(res.data)
                parseSide(root.getJSONObject("period_a")) to parseSide(root.getJSONObject("period_b"))
            }.onSuccess { (a, b) ->
                _ui.update { it.copy(loading = false, resultA = a, resultB = b, error = null) }
            }.onFailure { e ->
                _ui.update {
                    it.copy(
                        loading = false,
                        error = e.message?.take(300) ?: e::class.java.simpleName
                    )
                }
            }
        }
    }

    private fun parseRpcJsonObject(raw: String): JSONObject {
        val t = raw.trim()
        if (t.startsWith("[")) {
            val arr = JSONArray(t)
            if (arr.length() > 0) return arr.getJSONObject(0)
        }
        if (t.startsWith("{")) {
            val o = JSONObject(t)
            if (o.has("data") && o.opt("data") is JSONObject) {
                return o.getJSONObject("data")
            }
        }
        return JSONObject(t)
    }

    private fun parseSide(o: JSONObject): PeriodSideUi {
        val s = o.getJSONObject("summary")
        val summary = PeriodSummaryUi(
            workoutCount = s.optInt("workout_count"),
            durationMin = s.optLong("duration_min"),
            caloriesKcal = s.optDouble("calories_kcal", 0.0),
            score = s.optDouble("score", 0.0),
            distanceKm = s.optDouble("distance_km", 0.0),
            volumeKg = s.optDouble("volume_kg", 0.0)
        )
        val br = o.optJSONArray("breakdown") ?: JSONArray()
        val rows = (0 until br.length()).mapNotNull { i ->
            br.optJSONObject(i)?.let { b ->
                BreakdownRowUi(
                    label = b.optString("label", "—"),
                    workoutCount = b.optInt("workout_count"),
                    durationMin = b.optLong("duration_min"),
                    caloriesKcal = b.optDouble("calories_kcal", 0.0),
                    score = b.optDouble("score", 0.0),
                    distanceKm = b.optDouble("distance_km", 0.0),
                    volumeKg = b.optDouble("volume_kg", 0.0)
                )
            }
        }
        return PeriodSideUi(summary, rows)
    }
}

class PeriodCompareViewModelFactory(
    private val supabase: SupabaseClient,
    private val viewerUserId: String
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != PeriodCompareViewModel::class.java) error("Unknown VM")
        return PeriodCompareViewModel(supabase, viewerUserId) as T
    }
}
