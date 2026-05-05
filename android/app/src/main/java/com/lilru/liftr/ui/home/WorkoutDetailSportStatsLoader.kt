package com.lilru.liftr.ui.home

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

private val sportJson = Json { ignoreUnknownKeys = true }

@Serializable
data class FootballSessionStatsRow(
    val position: String? = null,
    @SerialName("minutes_played") val minutesPlayed: Int? = null,
    val goals: Int? = null,
    val assists: Int? = null,
    @SerialName("shots_on_target") val shotsOnTarget: Int? = null,
    @SerialName("passes_completed") val passesCompleted: Int? = null,
    @SerialName("passes_attempted") val passesAttempted: Int? = null,
    val tackles: Int? = null,
    val interceptions: Int? = null,
    val saves: Int? = null,
    @SerialName("yellow_cards") val yellowCards: Int? = null,
    @SerialName("red_cards") val redCards: Int? = null
)

@Serializable
data class BasketballSessionStatsRow(
    val points: Int? = null,
    val rebounds: Int? = null,
    val assists: Int? = null,
    val steals: Int? = null,
    val blocks: Int? = null,
    @SerialName("fg_made") val fgMade: Int? = null,
    @SerialName("fg_attempted") val fgAttempted: Int? = null,
    @SerialName("three_made") val threeMade: Int? = null,
    @SerialName("three_attempted") val threeAttempted: Int? = null,
    @SerialName("ft_made") val ftMade: Int? = null,
    @SerialName("ft_attempted") val ftAttempted: Int? = null,
    val turnovers: Int? = null,
    val fouls: Int? = null
)

@Serializable
data class RacketSessionStatsRow(
    val mode: String? = null,
    val format: String? = null,
    @SerialName("sets_won") val setsWon: Int? = null,
    @SerialName("sets_lost") val setsLost: Int? = null,
    @SerialName("games_won") val gamesWon: Int? = null,
    @SerialName("games_lost") val gamesLost: Int? = null,
    val aces: Int? = null,
    @SerialName("double_faults") val doubleFaults: Int? = null,
    val winners: Int? = null,
    @SerialName("unforced_errors") val unforcedErrors: Int? = null,
    @SerialName("break_points_won") val breakPointsWon: Int? = null,
    @SerialName("break_points_total") val breakPointsTotal: Int? = null,
    @SerialName("net_points_won") val netPointsWon: Int? = null,
    @SerialName("net_points_total") val netPointsTotal: Int? = null
)

@Serializable
data class VolleyballSessionStatsRow(
    val points: Int? = null,
    val aces: Int? = null,
    val blocks: Int? = null,
    val digs: Int? = null
)

@Serializable
data class HandballSessionStatsRow(
    val position: String? = null,
    @SerialName("minutes_played") val minutesPlayed: Int? = null,
    val goals: Int? = null,
    val shots: Int? = null,
    @SerialName("shots_on_target") val shotsOnTarget: Int? = null,
    val assists: Int? = null,
    val steals: Int? = null,
    val blocks: Int? = null,
    @SerialName("turnovers_lost") val turnoversLost: Int? = null,
    @SerialName("seven_m_goals") val sevenMGoals: Int? = null,
    @SerialName("seven_m_attempts") val sevenMAttempts: Int? = null,
    val saves: Int? = null,
    @SerialName("yellow_cards") val yellowCards: Int? = null,
    @SerialName("two_min_suspensions") val twoMinSuspensions: Int? = null,
    @SerialName("red_cards") val redCards: Int? = null
)

@Serializable
data class HockeySessionStatsRow(
    val position: String? = null,
    @SerialName("minutes_played") val minutesPlayed: Int? = null,
    val goals: Int? = null,
    val assists: Int? = null,
    @SerialName("shots_on_goal") val shotsOnGoal: Int? = null,
    @SerialName("plus_minus") val plusMinus: Int? = null,
    val hits: Int? = null,
    val blocks: Int? = null,
    @SerialName("faceoffs_won") val faceoffsWon: Int? = null,
    @SerialName("faceoffs_total") val faceoffsTotal: Int? = null,
    val saves: Int? = null,
    @SerialName("penalty_minutes") val penaltyMinutes: Int? = null
)

@Serializable
data class RugbySessionStatsRow(
    val position: String? = null,
    @SerialName("minutes_played") val minutesPlayed: Int? = null,
    val tries: Int? = null,
    @SerialName("conversions_made") val conversionsMade: Int? = null,
    @SerialName("conversions_attempted") val conversionsAttempted: Int? = null,
    @SerialName("penalty_goals_made") val penaltyGoalsMade: Int? = null,
    @SerialName("penalty_goals_attempted") val penaltyGoalsAttempted: Int? = null,
    val runs: Int? = null,
    @SerialName("meters_gained") val metersGained: Int? = null,
    val offloads: Int? = null,
    @SerialName("tackles_made") val tacklesMade: Int? = null,
    @SerialName("tackles_missed") val tacklesMissed: Int? = null,
    @SerialName("turnovers_won") val turnoversWon: Int? = null,
    @SerialName("yellow_cards") val yellowCards: Int? = null,
    @SerialName("red_cards") val redCards: Int? = null
)

@Serializable
data class HyroxSessionStatsRow(
    val division: String? = null,
    val category: String? = null,
    @SerialName("age_group") val ageGroup: String? = null,
    @SerialName("official_time_sec") val officialTimeSec: Int? = null,
    @SerialName("rank_overall") val rankOverall: Int? = null,
    @SerialName("rank_category") val rankCategory: Int? = null,
    @SerialName("no_reps") val noReps: Int? = null,
    @SerialName("penalty_time_sec") val penaltyTimeSec: Int? = null,
    @SerialName("avg_hr") val avgHr: Int? = null,
    @SerialName("max_hr") val maxHr: Int? = null
)

@Serializable
data class HyroxSessionExerciseRow(
    val id: Long,
    @SerialName("session_id") val sessionId: Int,
    @SerialName("exercise_code") val exerciseCode: String,
    @SerialName("exercise_order") val exerciseOrder: Int,
    @SerialName("distance_m") val distanceM: Int? = null,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("height_cm") val heightCm: Int? = null,
    @SerialName("implement_count") val implementCount: Int? = null,
    val notes: String? = null,
    @SerialName("exercise_display_name") val exerciseDisplayName: String? = null
)

@Serializable
data class SkiSessionStatsRow(
    @SerialName("session_id") val sessionId: Int? = null,
    @SerialName("total_distance_km") val totalDistanceKm: Double? = null,
    @SerialName("runs_count") val runsCount: Int? = null,
    @SerialName("max_speed_kmh") val maxSpeedKmh: Double? = null,
    @SerialName("avg_speed_kmh") val avgSpeedKmh: Double? = null,
    @SerialName("vertical_drop_m") val verticalDropM: Int? = null,
    @SerialName("moving_time_sec") val movingTimeSec: Int? = null,
    @SerialName("paused_time_sec") val pausedTimeSec: Int? = null,
    @SerialName("resort_name") val resortName: String? = null,
    @SerialName("snow_condition") val snowCondition: String? = null,
    val weather: String? = null
)

/** Paridad con [WorkoutDetailView.SportDetailBlock] `loadStats`. */
data class WorkoutSportDetailStatsBundle(
    val football: FootballSessionStatsRow? = null,
    val basketball: BasketballSessionStatsRow? = null,
    val racket: RacketSessionStatsRow? = null,
    val volleyball: VolleyballSessionStatsRow? = null,
    val handball: HandballSessionStatsRow? = null,
    val hockey: HockeySessionStatsRow? = null,
    val rugby: RugbySessionStatsRow? = null,
    val hyrox: HyroxSessionStatsRow? = null,
    val hyroxExercises: List<HyroxSessionExerciseRow> = emptyList(),
    val ski: SkiSessionStatsRow? = null
)

private inline fun <reified T> decodeOne(raw: String): T? {
    val t = raw.trim()
    if (t.isBlank()) return null
    return runCatching {
        if (t.startsWith("[")) sportJson.decodeFromString<List<T>>(t).firstOrNull()
        else sportJson.decodeFromString<T>(t)
    }.getOrNull()
}

private suspend inline fun <reified T> fetchSessionRow(
    supabase: SupabaseClient,
    table: String,
    sessionId: Int
): T? {
    val res = runCatching {
        supabase.from(table).select(columns = Columns.raw("*")) {
            filter { eq("session_id", sessionId) }
        }
    }.getOrNull() ?: return null
    return decodeOne(res.data)
}

private suspend inline fun <reified T> fetchSessionRowsOrdered(
    supabase: SupabaseClient,
    table: String,
    sessionId: Int,
    orderColumn: String
): List<T> {
    val res = runCatching {
        supabase.from(table).select(columns = Columns.raw("*")) {
            filter { eq("session_id", sessionId) }
            order(orderColumn, Order.ASCENDING)
        }
    }.getOrNull() ?: return emptyList()
    val t = res.data.trim()
    if (t.isBlank()) return emptyList()
    return runCatching {
        if (t.startsWith("[")) sportJson.decodeFromString<List<T>>(t)
        else listOf(sportJson.decodeFromString<T>(t))
    }.getOrDefault(emptyList())
}

suspend fun loadWorkoutSportDetailStats(
    supabase: SupabaseClient,
    sessionId: Int,
    sport: String
): WorkoutSportDetailStatsBundle {
    return when (sport.lowercase()) {
        "football" -> WorkoutSportDetailStatsBundle(
            football = fetchSessionRow(supabase, BackendContracts.Tables.FOOTBALL_SESSION_STATS, sessionId)
        )
        "basketball" -> WorkoutSportDetailStatsBundle(
            basketball = fetchSessionRow(supabase, BackendContracts.Tables.BASKETBALL_SESSION_STATS, sessionId)
        )
        "padel", "tennis", "badminton", "squash", "table_tennis" -> WorkoutSportDetailStatsBundle(
            racket = fetchSessionRow(supabase, BackendContracts.Tables.RACKET_SESSION_STATS, sessionId)
        )
        "volleyball" -> WorkoutSportDetailStatsBundle(
            volleyball = fetchSessionRow(supabase, BackendContracts.Tables.VOLLEYBALL_SESSION_STATS, sessionId)
        )
        "handball" -> WorkoutSportDetailStatsBundle(
            handball = fetchSessionRow(supabase, BackendContracts.Tables.HANDBALL_SESSION_STATS, sessionId)
        )
        "hockey" -> WorkoutSportDetailStatsBundle(
            hockey = fetchSessionRow(supabase, BackendContracts.Tables.HOCKEY_SESSION_STATS, sessionId)
        )
        "rugby" -> WorkoutSportDetailStatsBundle(
            rugby = fetchSessionRow(supabase, BackendContracts.Tables.RUGBY_SESSION_STATS, sessionId)
        )
        "hyrox" -> {
            val main = fetchSessionRow<HyroxSessionStatsRow>(
                supabase,
                BackendContracts.Tables.HYROX_SESSION_STATS,
                sessionId
            )
            val ex = fetchSessionRowsOrdered<HyroxSessionExerciseRow>(
                supabase,
                BackendContracts.Tables.HYROX_SESSION_EXERCISES,
                sessionId,
                "exercise_order"
            )
            WorkoutSportDetailStatsBundle(hyrox = main, hyroxExercises = ex)
        }
        "ski" -> WorkoutSportDetailStatsBundle(
            ski = fetchSessionRow(supabase, BackendContracts.Tables.SKI_SESSION_STATS, sessionId)
        )
        else -> WorkoutSportDetailStatsBundle()
    }
}

fun sportUsesNumericScore(sport: String): Boolean = when (sport.lowercase()) {
    "football", "basketball", "handball", "hockey" -> true
    else -> false
}

fun sportUsesSetText(sport: String): Boolean = when (sport.lowercase()) {
    "padel", "tennis", "badminton", "squash", "table_tennis", "volleyball" -> true
    else -> false
}
