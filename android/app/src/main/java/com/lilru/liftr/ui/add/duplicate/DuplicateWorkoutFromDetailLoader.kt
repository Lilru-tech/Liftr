package com.lilru.liftr.ui.add.duplicate

import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.add.AddCardioActivity
import com.lilru.liftr.ui.add.AddFootballPosition
import com.lilru.liftr.ui.add.AddMatchResult
import com.lilru.liftr.ui.add.AddRacketFormat
import com.lilru.liftr.ui.add.AddRacketMode
import com.lilru.liftr.ui.add.AddSportType
import com.lilru.liftr.ui.add.AddWorkoutIntensity
import com.lilru.liftr.ui.add.AddWorkoutKind
import com.lilru.liftr.ui.add.AddWorkoutState
import com.lilru.liftr.ui.add.StrengthExerciseDraft
import com.lilru.liftr.ui.add.StrengthSetDraft
import com.lilru.liftr.ui.add.recommendation.HyroxExerciseRecommendationResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.util.UUID
import kotlin.math.floor
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.json.JSONArray
import org.json.JSONObject

@Serializable
private data class WorkoutBaseRow(
    @SerialName("user_id") val userId: String,
    val kind: String? = null,
    val title: String? = null,
    val notes: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    val state: String? = null,
    @SerialName("perceived_intensity") val perceivedIntensity: String? = null
)

@Serializable
private data class WorkoutExerciseWire(
    val id: Int,
    @SerialName("exercise_id") val exerciseId: Long,
    @SerialName("order_index") val orderIndex: Int,
    val notes: String? = null,
    @SerialName("custom_name") val customName: String? = null,
    val exercises: NameName? = null
)

@Serializable
private data class NameName(val name: String? = null)

@Serializable
private data class ExerciseSetWire(
    @SerialName("workout_exercise_id") val workoutExerciseId: Int,
    @SerialName("set_number") val setNumber: Int,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null
)

@Serializable
private data class CardioRow(
    val id: Int,
    @SerialName("activity_code") val activityCode: String? = null,
    val modality: String? = null,
    @SerialName("distance_km") val distanceKm: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("avg_hr") val avgHr: Int? = null,
    @SerialName("max_hr") val maxHr: Int? = null,
    @SerialName("avg_pace_sec_per_km") val avgPaceSecPerKm: Int? = null,
    @SerialName("elevation_gain_m") val elevationGainM: Int? = null
)

@Serializable
private data class CardioStatsRow(
    val stats: CardioStatsBody? = null
) {
    @Serializable
    data class CardioStatsBody(
        @SerialName("cadence_rpm") val cadenceRpm: Int? = null,
        @SerialName("watts_avg") val wattsAvg: Int? = null,
        @SerialName("incline_pct") val inclinePct: Double? = null,
        @SerialName("swim_laps") val swimLaps: Int? = null,
        @SerialName("pool_length_m") val poolLengthM: Int? = null,
        @SerialName("swim_style") val swimStyle: String? = null,
        @SerialName("split_sec_per_500m") val splitSecPer500m: Int? = null,
        @SerialName("km_split_pace_sec") val kmSplitPaceSec: List<Int>? = null
    )
}

@Serializable
private data class HyroxExRow(
    @SerialName("exercise_code") val exerciseCode: String,
    @SerialName("exercise_order") val exerciseOrder: Int = 0,
    @SerialName("distance_m") val distanceM: Int? = null,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("height_cm") val heightCm: Int? = null,
    @SerialName("implement_count") val implementCount: Int? = null,
    val notes: String? = null,
    @SerialName("exercise_display_name") val exerciseDisplayName: String? = null
)

private val loaderJson = Json { ignoreUnknownKeys = true }

private fun fmtNum(w: Double): String =
    if (floor(w) == w) w.toInt().toString() else String.format(java.util.Locale.US, "%.1f", w)

private fun jsonArrayData(raw: String): String =
    when {
        raw.isBlank() -> "[]"
        raw.trimStart().startsWith("[") -> raw
        else -> "[$raw]"
    }

private fun firstObjectFromSelect(raw: String): JSONObject? {
    val a = runCatching { JSONArray(jsonArrayData(raw)) }.getOrNull() ?: return null
    if (a.length() < 1) return null
    return a.optJSONObject(0)
}

/** JSON puede traer [duration_sec] como número. */
private fun jsonDurationSecToMin(o: JSONObject): String? {
    val sec = when {
        o.isNull("duration_sec") -> null
        o.has("duration_sec") && o.get("duration_sec") is Int -> o.getInt("duration_sec")
        o.has("duration_sec") && o.get("duration_sec") is java.lang.Number ->
            o.getDouble("duration_sec").toInt()
        else -> o.optString("duration_sec", "").toIntOrNull()
    } ?: return null
    if (sec <= 0) return null
    return (sec / 60).toString()
}

/**
 * Carga y mapea como iOS [Liftr.WorkoutDetailView.buildDuplicateDraft].
 */
suspend fun loadDuplicateForAdd(
    supabase: SupabaseClient,
    workoutId: Int,
    currentUserId: String?
): DuplicateWorkoutPayload? {
    val wRes = runCatching {
        supabase.from(BackendContracts.Tables.WORKOUTS)
            .select { filter { eq("id", workoutId) } }
    }.getOrNull() ?: return null
    val wList = runCatching { loaderJson.decodeFromString<List<WorkoutBaseRow>>(wRes.data) }
        .getOrNull() ?: return null
    val base = wList.firstOrNull() ?: return null
    val kind = (base.kind ?: "strength").lowercase()
    val ownerId = base.userId

    val startedIso = if (currentUserId != null && currentUserId == base.userId) {
        java.time.Instant.now().toString()
    } else {
        (base.startedAt?.takeIf { it.isNotBlank() }) ?: java.time.Instant.now().toString()
    }
    val endedIso = if (currentUserId != null && currentUserId == base.userId) {
        ""
    } else {
        base.endedAt?.trim().orEmpty()
    }
    val schedEnd = endedIso.isNotBlank()
    val intensity = AddWorkoutIntensity.entries
        .firstOrNull { it.wire == (base.perceivedIntensity?.trim()?.lowercase() ?: "moderate") }
        ?: AddWorkoutIntensity.MODERATE
    val wState = when (base.state?.lowercase()) {
        "planned" -> AddWorkoutState.PLANNED
        else -> AddWorkoutState.PUBLISHED
    }

    var prefill = AddDuplicateFormPrefill(
        title = base.title?.trim().orEmpty(),
        notes = base.notes?.trim().orEmpty(),
        startedAtIso = startedIso,
        scheduleEndedEnabled = schedEnd,
        endedAtIso = endedIso,
        addState = wState,
        intensity = intensity,
        kind = when (kind) {
            "strength" -> AddWorkoutKind.STRENGTH
            "cardio" -> AddWorkoutKind.CARDIO
            "sport" -> AddWorkoutKind.SPORT
            else -> AddWorkoutKind.STRENGTH
        },
        cardioActivity = AddCardioActivity.RUN,
        cardioDistanceKm = "",
        cardioDurH = "",
        cardioDurM = "",
        cardioDurS = "",
        cardioDurationSecFallback = "",
        didEditCardioDuration = false,
        didEditSportDuration = false,
        cardioAvgHr = "",
        cardioMaxHr = "",
        cardioAvgPaceSecPerKm = "",
        cardioElevationGainM = "",
        cardioStats = emptyMap(),
        sportType = AddSportType.PADEL,
        footballPosition = AddFootballPosition.FORWARD,
        racketMode = AddRacketMode.SINGLES,
        racketFormat = AddRacketFormat.BEST_OF_3,
        sportDurationMin = "",
        sportScoreFor = "",
        sportScoreAgainst = "",
        sportMatchScoreText = "",
        sportLocation = "",
        sportSessionNotes = "",
        sportMatchResult = AddMatchResult.UNFINISHED,
        hyroxExercisesJson = "[]",
        sportStats = emptyMap()
    )

    var strengthRows: List<StrengthExerciseDraft> = listOf(StrengthExerciseDraft())

    when (kind) {
        "strength" -> {
            val exs = runCatching {
                val r = supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES)
                    .select(
                        columns = Columns.raw("id, exercise_id, order_index, notes, custom_name, exercises(name)"),
                    ) {
                        filter { eq("workout_id", workoutId) }
                        order("order_index", Order.ASCENDING)
                    }
                loaderJson.decodeFromString<List<WorkoutExerciseWire>>(r.data)
            }.getOrNull() ?: return null
            if (exs.isEmpty()) return null
            val exIds = exs.map { it.id }
            var setsByEx: Map<Int, List<StrengthSetDraft>> = emptyMap()
            if (exIds.isNotEmpty()) {
                val sData = runCatching {
                    supabase.from(BackendContracts.Tables.EXERCISE_SETS)
                        .select(
                            columns = Columns.raw(
                                "workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec"
                            )
                        ) {
                            filter { isIn("workout_exercise_id", exIds) }
                            order("set_number", Order.ASCENDING)
                        }
                }.getOrNull() ?: return null
                val sRows = runCatching { loaderJson.decodeFromString<List<ExerciseSetWire>>(sData.data) }
                    .getOrNull() ?: return null
                setsByEx = sRows.groupBy({ it.workoutExerciseId }, { s ->
                    StrengthSetDraft(
                        setNumber = s.setNumber.coerceIn(1, 99),
                        repsText = s.reps?.toString() ?: "8",
                        weightText = s.weightKg?.let { fmtNum(it) } ?: "",
                        rpeText = s.rpe?.let { fmtNum(it) } ?: "",
                        restSecText = s.restSec?.toString() ?: ""
                    )
                })
            }
            strengthRows = exs.map { ex ->
                val displayName = when {
                    !ex.customName.isNullOrBlank() -> ex.customName
                    else -> ex.exercises?.name.orEmpty()
                }
                StrengthExerciseDraft(
                    id = UUID.randomUUID().toString(),
                    exerciseId = ex.exerciseId,
                    exerciseName = displayName,
                    customName = ex.customName?.trim() ?: "",
                    notes = ex.notes?.trim() ?: "",
                    sets = setsByEx[ex.id]?.ifEmpty { null } ?: listOf(StrengthSetDraft())
                )
            }
        }
        "cardio" -> {
            val cRes = runCatching {
                supabase.from(BackendContracts.Tables.CARDIO_SESSIONS)
                    .select { filter { eq("workout_id", workoutId) } }
            }.getOrNull() ?: return null
            val list = runCatching { loaderJson.decodeFromString<List<CardioRow>>(cRes.data) }
                .getOrNull() ?: return null
            val card = list.firstOrNull() ?: return null
            val actWire = (card.activityCode?.takeIf { it.isNotBlank() }
                ?: card.modality?.takeIf { it.isNotBlank() }
                ?: "run")
            val activity = AddCardioActivity.entries.firstOrNull { it.wire == actWire }
                ?: AddCardioActivity.RUN
            val dSec = card.durationSec?.takeIf { it > 0 }
            val h = dSec?.let { it / 3600 } ?: 0
            val m = dSec?.let { (it % 3600) / 60 } ?: 0
            val s = dSec?.let { it % 60 } ?: 0
            val pace = (card.avgPaceSecPerKm?.takeIf { it > 0 }?.toString()) ?: ""
            val cStats = mutableMapOf<String, String>()
            runCatching {
                val st = supabase.from(BackendContracts.Tables.CARDIO_SESSION_STATS)
                    .select { filter { eq("session_id", card.id) } }
                val statRows = runCatching { loaderJson.decodeFromString<List<CardioStatsRow>>(st.data) }
                    .getOrNull().orEmpty()
                val body = statRows.firstOrNull()?.stats
                if (body != null) {
                    body.cadenceRpm?.let { cStats["cadence_rpm"] = it.toString() }
                    body.wattsAvg?.let { cStats["watts_avg"] = it.toString() }
                    body.inclinePct?.let { cStats["incline_pct"] = it.toString() }
                    body.swimLaps?.let { cStats["swim_laps"] = it.toString() }
                    body.poolLengthM?.let { cStats["pool_length_m"] = it.toString() }
                    if (!body.swimStyle.isNullOrBlank()) cStats["swim_style"] = body.swimStyle
                    body.splitSecPer500m?.let { cStats["split_sec_per_500m"] = it.toString() }
                    val km = body.kmSplitPaceSec
                    if (km != null && km.isNotEmpty()) {
                        cStats["km_split_pace_sec"] = km.joinToString(",")
                    }
                }
            }
            prefill = prefill.copy(
                kind = AddWorkoutKind.CARDIO,
                cardioActivity = activity,
                cardioDistanceKm = card.distanceKm?.toString() ?: "",
                cardioDurH = if (dSec == null) "" else if (h == 0) "" else h.toString(),
                cardioDurM = if (dSec == null) "" else m.toString(),
                cardioDurS = if (dSec == null) "" else s.toString(),
                cardioAvgHr = card.avgHr?.toString() ?: "",
                cardioMaxHr = card.maxHr?.toString() ?: "",
                cardioAvgPaceSecPerKm = pace,
                cardioElevationGainM = card.elevationGainM?.toString() ?: "",
                cardioStats = cStats
            )
        }
        "sport" -> {
            val r = runCatching {
                supabase.from(BackendContracts.Tables.SPORT_SESSIONS)
                    .select { filter { eq("workout_id", workoutId) } }
            }.getOrNull() ?: return null
            val o0 = firstObjectFromSelect(r.data) ?: return null
            val sessionId = o0.optInt("id", 0)
            if (sessionId == 0) return null
            val spStr = o0.getString("sport").lowercase()
            val sportT = AddSportType.entries.firstOrNull { it.wire == spStr } ?: AddSportType.FOOTBALL
            val mRes = o0.optString("match_result", "").ifBlank { null }?.lowercase()
            val mMatch = AddMatchResult.entries.firstOrNull { it.wire == mRes } ?: AddMatchResult.UNFINISHED
            prefill = prefill.copy(
                kind = AddWorkoutKind.SPORT,
                sportType = sportT,
                sportDurationMin = jsonDurationSecToMin(o0) ?: "",
                sportScoreFor = o0.optString("score_for", "").ifBlank { null } ?: "",
                sportScoreAgainst = o0.optString("score_against", "").ifBlank { null } ?: "",
                sportMatchScoreText = o0.optString("match_score_text", "") ?: "",
                sportLocation = o0.optString("location", "") ?: "",
                sportSessionNotes = o0.optString("notes", "") ?: "",
                sportMatchResult = mMatch
            )
            val vRes = runCatching {
                supabase.from(BackendContracts.Views.VW_SPORT_SESSION_FULL)
                    .select { filter { eq("workout_id", workoutId) } }
            }.getOrNull()
            if (vRes != null) {
                val fullJ = firstObjectFromSelect(vRes.data)
                if (fullJ != null) {
                    prefill = mergeSportVw(
                        inP = prefill,
                        full = fullJ,
                        supabase = supabase,
                        sessionId = sessionId,
                        spFromSession = spStr
                    )
                }
            }
        }
    }

    val pIds = loadParticipantIds(
        supabase, workoutId, currentUserId, ownerId
    )
    return DuplicateWorkoutPayload(
        strengthExercises = if (kind == "strength") {
            strengthRows
        } else {
            listOf(StrengthExerciseDraft())
        },
        selectedParticipantIds = pIds,
        prefill = prefill
    )
}

private suspend fun mergeSportVw(
    inP: AddDuplicateFormPrefill,
    full: JSONObject,
    supabase: SupabaseClient,
    sessionId: Int,
    spFromSession: String
): AddDuplicateFormPrefill {
    var p = inP
    val sp = full.optString("sport", spFromSession).lowercase()
    p = p.copy(
        sportType = AddSportType.entries.firstOrNull { it.wire == sp } ?: p.sportType,
        sportDurationMin = jsonDurationSecToMin(full) ?: p.sportDurationMin,
        sportScoreFor = full.optString("score_for", p.sportScoreFor).ifBlank { p.sportScoreFor },
        sportScoreAgainst = full.optString("score_against", p.sportScoreAgainst)
            .ifBlank { p.sportScoreAgainst },
        sportMatchScoreText = full.optString("match_score_text", p.sportMatchScoreText).ifBlank { p.sportMatchScoreText },
        sportLocation = full.optString("location", p.sportLocation).ifBlank { p.sportLocation },
        sportSessionNotes = full.optString("session_notes", p.sportSessionNotes).ifBlank { p.sportSessionNotes },
        sportMatchResult = full.optString("match_result", "")
            .takeIf { it.isNotBlank() }
            ?.lowercase()
            ?.let { r -> AddMatchResult.entries.firstOrNull { a -> a.wire == r } } ?: p.sportMatchResult
    )
    val sMap = p.sportStats.toMutableMap()
    when (sp) {
        "padel", "tennis", "badminton", "squash", "table_tennis" -> {
            full.optString("rk_mode", "").takeIf { it.isNotBlank() }?.let { m ->
                p = p.copy(racketMode = AddRacketMode.entries.firstOrNull { a -> a.wire == m } ?: p.racketMode)
            }
            full.optString("rk_format", "").takeIf { it.isNotBlank() }?.let { f ->
                p = p.copy(racketFormat = AddRacketFormat.entries.firstOrNull { a -> a.wire == f } ?: p.racketFormat)
            }
            sMap["racket_stats_raw"] = buildRacketStatsJson(full)
        }
        "football" -> {
            full.optString("fb_position", "").takeIf { it.isNotBlank() }?.let { pos ->
                p = p.copy(
                    footballPosition = AddFootballPosition.entries.firstOrNull { a -> a.wire == pos }
                        ?: p.footballPosition
                )
            }
            sMap["assists"] = full.optString("fb_assists", sMap["assists"].orEmpty())
            sMap["shots_on_target"] = full.optString("fb_shots_on_target", sMap["shots_on_target"].orEmpty())
            sMap["passes_completed"] = full.optString("fb_passes_completed", sMap["passes_completed"].orEmpty())
            sMap["tackles"] = full.optString("fb_tackles", sMap["tackles"].orEmpty())
            sMap["saves"] = full.optString("fb_saves", sMap["saves"].orEmpty())
            sMap["yellow_cards"] = full.optString("fb_yellow_cards", sMap["yellow_cards"].orEmpty())
            sMap["red_cards"] = full.optString("fb_red_cards", sMap["red_cards"].orEmpty())
        }
        "basketball" -> {
            listOf(
                "bb_points" to "points", "bb_rebounds" to "rebounds", "bb_assists" to "assists",
                "bb_steals" to "steals", "bb_blocks" to "blocks", "bb_turnovers" to "turnovers",
                "bb_fouls" to "fouls"
            ).forEach { (kk, t) -> sMap[t] = full.optString(kk, sMap[t].orEmpty()) }
        }
        "volleyball" -> {
            sMap["points"] = full.optString("vb_points", sMap["points"].orEmpty())
            sMap["aces"] = full.optString("vb_aces", sMap["aces"].orEmpty())
            sMap["blocks"] = full.optString("vb_blocks", sMap["blocks"].orEmpty())
            sMap["digs"] = full.optString("vb_digs", sMap["digs"].orEmpty())
        }
        "handball" -> {
            sMap["raw_stats_json"] = handballJson(full)
        }
        "hockey" -> {
            sMap["raw_stats_json"] = hockeyJson(full)
        }
        "rugby" -> {
            sMap["raw_stats_json"] = rugbyJson(full)
        }
        "hyrox" -> {
            sMap["raw_stats_json"] = hyRawMeta(full)
            p = p.copy(
                hyroxExercisesJson = runCatching { loadHyroxExercisesJson(supabase, sessionId) }
                    .getOrNull() ?: p.hyroxExercisesJson
            )
        }
        "ski" -> {
            sMap["raw_stats_json"] = runCatching { skiRawFromTable(supabase, sessionId) }
                .getOrNull() ?: p.sportStats["raw_stats_json"].orEmpty()
        }
    }
    return p.copy(sportStats = sMap)
}

private fun handballJson(full: JSONObject): String = JSONObject().apply {
    full.optString("hb_position", "").takeIf { it.isNotBlank() }?.let { put("position", it) }
    put("goals", full.optInt("hb_goals", 0))
    put("shots", full.optInt("hb_shots", 0))
    put("shots_on_target", full.optInt("hb_shots_on_target", 0))
    put("assists", full.optInt("hb_assists", 0))
    put("steals", full.optInt("hb_steals", 0))
    put("blocks", full.optInt("hb_blocks", 0))
    put("turnovers_lost", full.optInt("hb_turnovers_lost", 0))
    put("seven_m_goals", full.optInt("hb_seven_m_goals", 0))
    put("seven_m_attempts", full.optInt("hb_seven_m_attempts", 0))
    put("saves", full.optInt("hb_saves", 0))
    put("yellow_cards", full.optInt("hb_yellow_cards", 0))
    put("two_min_suspensions", full.optInt("hb_two_min_suspensions", 0))
    put("red_cards", full.optInt("hb_red_cards", 0))
}.toString()

private fun hockeyJson(full: JSONObject): String = JSONObject().apply {
    full.optString("hk_position", "").takeIf { it.isNotBlank() }?.let { put("position", it) }
    put("goals", full.optInt("hk_goals", 0))
    put("assists", full.optInt("hk_assists", 0))
    put("shots_on_goal", full.optInt("hk_shots_on_goal", 0))
    put("plus_minus", full.optInt("hk_plus_minus", 0))
    put("hits", full.optInt("hk_hits", 0))
    put("blocks", full.optInt("hk_blocks", 0))
    put("faceoffs_won", full.optInt("hk_faceoffs_won", 0))
    put("faceoffs_total", full.optInt("hk_faceoffs_total", 0))
    put("saves", full.optInt("hk_saves", 0))
    put("penalty_minutes", full.optInt("hk_penalty_minutes", 0))
}.toString()

private fun rugbyJson(full: JSONObject): String = JSONObject().apply {
    full.optString("rg_position", "").takeIf { it.isNotBlank() }?.let { put("position", it) }
    put("tries", full.optInt("rg_tries", 0))
    put("conversions_made", full.optInt("rg_conversions_made", 0))
    put("conversions_attempted", full.optInt("rg_conversions_attempted", 0))
    put("penalty_goals_made", full.optInt("rg_penalty_goals_made", 0))
    put("penalty_goals_attempted", full.optInt("rg_penalty_goals_attempted", 0))
    put("runs", full.optInt("rg_runs", 0))
    put("meters_gained", full.optInt("rg_meters_gained", 0))
    put("offloads", full.optInt("rg_offloads", 0))
    put("tackles_made", full.optInt("rg_tackles_made", 0))
    put("tackles_missed", full.optInt("rg_tackles_missed", 0))
    put("turnovers_won", full.optInt("rg_turnovers_won", 0))
    put("yellow_cards", full.optInt("rg_yellow_cards", 0))
    put("red_cards", full.optInt("rg_red_cards", 0))
}.toString()

private fun hyRawMeta(full: JSONObject): String = JSONObject().apply {
    full.optString("hy_division", "").takeIf { it.isNotBlank() }?.let { put("division", it) }
    full.optString("hy_category", "").takeIf { it.isNotBlank() }?.let { put("category", it) }
    full.optString("hy_age_group", "").takeIf { it.isNotBlank() }?.let { put("age_group", it) }
    put("official_time_sec", full.optInt("hy_official_time_sec", 0))
    put("rank_overall", full.optInt("hy_rank_overall", 0))
    put("rank_category", full.optInt("hy_rank_category", 0))
    put("no_reps", full.optInt("hy_no_reps", 0))
    put("penalty_time_sec", full.optInt("hy_penalty_time_sec", 0))
    put("avg_hr", full.optInt("hy_avg_hr", 0))
    put("max_hr", full.optInt("hy_max_hr", 0))
}.toString()

private suspend fun skiRawFromTable(
    supabase: SupabaseClient,
    sessionId: Int
): String {
    val sRes = supabase
        .from(BackendContracts.Tables.SKI_SESSION_STATS)
        .select { filter { eq("session_id", sessionId) } }
    val o = firstObjectFromSelect(sRes.data) ?: return "{}"
    fun n(key: String): String {
        if (!o.has(key)) return ""
        val v = o.get(key)
        return when (v) {
            null, org.json.JSONObject.NULL -> ""
            is Number -> v.toString()
            else -> o.optString(key, "")
        }
    }
    return JSONObject().apply {
        put("total_distance_km", n("total_distance_km").ifEmpty { "0" })
        put("runs_count", o.optInt("runs_count", 0))
        put("max_speed_kmh", n("max_speed_kmh").ifEmpty { "0" })
        put("avg_speed_kmh", n("avg_speed_kmh").ifEmpty { "0" })
        put("vertical_drop_m", o.optInt("vertical_drop_m", 0))
        put("moving_time_sec", o.optInt("moving_time_sec", 0))
        put("paused_time_sec", o.optInt("paused_time_sec", 0))
        put("resort_name", o.optString("resort_name", ""))
        put("snow_condition", o.optString("snow_condition", ""))
        put("weather", o.optString("weather", ""))
    }.toString()
}

private suspend fun loadHyroxExercisesJson(supabase: SupabaseClient, sessionId: Int): String {
    val exRes = supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES)
        .select(
            columns = Columns.raw(
                "exercise_code, exercise_order, distance_m, reps, weight_kg, duration_sec, " +
                    "height_cm, implement_count, exercise_display_name, notes"
            )
        ) {
            filter { eq("session_id", sessionId) }
            order("exercise_order", Order.ASCENDING)
        }
    val rows: List<HyroxExRow> = loaderJson.decodeFromString(exRes.data)
    if (rows.isEmpty()) return "[]"
    val list = rows.map { r ->
        HyroxExerciseRecommendationResult(
            exerciseCode = r.exerciseCode,
            customDisplayName = r.exerciseDisplayName?.trim() ?: "",
            exerciseOrder = r.exerciseOrder,
            distanceM = r.distanceM,
            reps = r.reps,
            weightKg = r.weightKg,
            durationSec = r.durationSec,
            heightCm = r.heightCm,
            implementCount = r.implementCount,
            notes = r.notes
        )
    }
    return loaderJson.encodeToString(
        ListSerializer(HyroxExerciseRecommendationResult.serializer()),
        list
    )
}

private suspend fun loadParticipantIds(
    supabase: SupabaseClient,
    workoutId: Int,
    me: String?,
    ownerId: String
): Set<String> {
    val uids = runCatching {
        val r = supabase.from(BackendContracts.Tables.WORKOUT_PARTICIPANTS)
            .select { filter { eq("workout_id", workoutId) } }
        if (r.data.isBlank()) return@runCatching emptyList()
        val ja = JSONArray(jsonArrayData(r.data))
        (0 until ja.length()).mapNotNull { i ->
            ja.getJSONObject(i).optString("user_id", "").ifBlank { null }
        }
    }.getOrDefault(emptyList())
    var set = uids.toMutableList()
    if (me != null && me != ownerId && me in set) {
        set.remove(me)
        if (ownerId !in set) {
            set.add(ownerId)
        }
    }
    return set.mapNotNull { it.takeIf { id -> me == null || id != me } }.toSet()
}

/**
 * Carga [sportStats] + Hyrox + enums para [WorkoutDetailViewModel] (misma fuente que duplicar en Add).
 */
suspend fun loadSportEditEnrichment(
    supabase: SupabaseClient,
    workoutId: Int,
    sessionId: Int,
    spFromSession: String
): SportEditEnrichment {
    val vRes = runCatching {
        supabase.from(BackendContracts.Views.VW_SPORT_SESSION_FULL)
            .select { filter { eq("workout_id", workoutId) } }
    }.getOrNull() ?: return SportEditEnrichment.empty()
    val full = firstObjectFromSelect(vRes.data) ?: return SportEditEnrichment.empty()
    val dummy = AddDuplicateFormPrefill(
        title = "",
        notes = "",
        startedAtIso = "",
        scheduleEndedEnabled = false,
        endedAtIso = "",
        addState = AddWorkoutState.PUBLISHED,
        intensity = AddWorkoutIntensity.MODERATE,
        kind = AddWorkoutKind.SPORT,
        cardioActivity = AddCardioActivity.RUN,
        cardioDistanceKm = "",
        cardioDurH = "",
        cardioDurM = "",
        cardioDurS = "",
        cardioDurationSecFallback = "",
        didEditCardioDuration = false,
        didEditSportDuration = false,
        cardioAvgHr = "",
        cardioMaxHr = "",
        cardioAvgPaceSecPerKm = "",
        cardioElevationGainM = "",
        cardioStats = emptyMap(),
        sportType = AddSportType.PADEL,
        footballPosition = AddFootballPosition.FORWARD,
        racketMode = AddRacketMode.SINGLES,
        racketFormat = AddRacketFormat.BEST_OF_3,
        sportDurationMin = "",
        sportScoreFor = "",
        sportScoreAgainst = "",
        sportMatchScoreText = "",
        sportLocation = "",
        sportSessionNotes = "",
        sportMatchResult = AddMatchResult.UNFINISHED,
        hyroxExercisesJson = "[]",
        sportStats = emptyMap()
    )
    val merged = mergeSportVw(dummy, full, supabase, sessionId, spFromSession)
    return SportEditEnrichment(
        sportStats = merged.sportStats,
        hyroxExercisesJson = merged.hyroxExercisesJson,
        footballPosition = merged.footballPosition,
        racketMode = merged.racketMode,
        racketFormat = merged.racketFormat
    )
}
