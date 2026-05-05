package com.lilru.liftr.ui.compare

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.text.Normalizer
import java.time.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * [Liftr.CompareWorkoutsView.buildSportMetrics] + [appendHyroxExerciseComparisonMetrics].
 */
object CompareSportMetrics {
    private const val HYROX_CUSTOM = "custom"
    private const val CUSTOM_SEP = "\u001E"

    suspend fun build(
        json: Json,
        supabase: SupabaseClient,
        currentWid: Int,
        otherWid: Int
    ): List<CompareMetricRow> {
        val lS = supabase.from(BackendContracts.Tables.SPORT_SESSIONS)
            .select(columns = Columns.raw("id, sport, duration_sec, score_for, score_against")) {
                filter { eq("workout_id", currentWid) }
            }
        val rS = supabase.from(BackendContracts.Tables.SPORT_SESSIONS)
            .select(columns = Columns.raw("id, sport, duration_sec, score_for, score_against")) {
                filter { eq("workout_id", otherWid) }
            }
        val lW = supabase.from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("duration_min, started_at, ended_at")) {
                filter { eq("id", currentWid) }
            }
        val rW = supabase.from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("duration_min, started_at, ended_at")) {
                filter { eq("id", otherWid) }
            }
        val L = json.decodeFromString<List<SportIdRow>>(lS.data).firstOrNull()
            ?: error("No sport session for workout $currentWid")
        val R = json.decodeFromString<List<SportIdRow>>(rS.data).firstOrNull()
            ?: error("No sport session for workout $otherWid")
        val LM = json.decodeFromString<List<MetaW>>(lW.data).firstOrNull() ?: MetaW()
        val RM = json.decodeFromString<List<MetaW>>(rW.data).firstOrNull() ?: MetaW()
        val ls = L.sport.trim().lowercase()
        val rs = R.sport.trim().lowercase()
        if (ls != rs) error("Different sports ($ls vs $rs).")
        val out = mutableListOf<CompareMetricRow>()
        val lDur = bestDurSec(L.durationSec, LM)
        val rDur = bestDurSec(R.durationSec, RM)
        out.addM("duration_sec", "sec", lDur, rDur)
        out.addM("score_for", "pts", L.scoreFor?.toDouble(), R.scoreFor?.toDouble())
        out.addM("score_against", "pts", L.scoreAgainst?.toDouble(), R.scoreAgainst?.toDouble())
        when (ls) {
            "padel", "tennis", "badminton", "squash", "table_tennis" -> {
                addRacket(json, supabase, L.id, R.id, out)
            }
            "basketball" -> addBb(json, supabase, L.id, R.id, out)
            "football" -> addFb(json, supabase, L.id, R.id, out)
            "handball" -> addHb(json, supabase, L.id, R.id, out)
            "hockey" -> addHk(json, supabase, L.id, R.id, out)
            "rugby" -> addRg(json, supabase, L.id, R.id, out)
            "hyrox" -> {
                addHx(json, supabase, L.id, R.id, out)
                appendHyroxStations(json, supabase, L.id, R.id, out)
            }
            "volleyball" -> addVb(json, supabase, L.id, R.id, out)
            else -> { }
        }
        return out
    }

    @Serializable
    private data class SportIdRow(
        val id: Int,
        val sport: String,
        @SerialName("duration_sec") val durationSec: Int? = null,
        @SerialName("score_for") val scoreFor: Int? = null,
        @SerialName("score_against") val scoreAgainst: Int? = null
    )

    @Serializable
    private data class MetaW(
        @SerialName("duration_min") val durationMin: Int? = null,
        @SerialName("started_at") val startedAt: String? = null,
        @SerialName("ended_at") val endedAt: String? = null
    )

    private fun bestDurSec(sess: Int?, meta: MetaW): Double? {
        if (sess != null && sess > 0) return sess.toDouble()
        val m = meta.durationMin
        if (m != null && m > 0) return (m * 60).toDouble()
        val s = meta.startedAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return null
        val e = meta.endedAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return null
        val sec = (e.epochSecond - s.epochSecond)
        return if (sec > 0) sec.toDouble() else null
    }

    private fun MutableList<CompareMetricRow>.addM(metric: String, unit: String, l: Double?, r: Double?) {
        if (l == null || r == null) return
        add(CompareMetricRow(key = metric, unit = unit, left = l, right = r))
    }

    @Serializable
    private data class Rk(
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

    private suspend fun addRacket(
        json: Json,
        supabase: SupabaseClient,
        lSid: Int,
        rSid: Int,
        out: MutableList<CompareMetricRow>
    ) {
        val lD = supabase.from(BackendContracts.Tables.RACKET_SESSION_STATS)
            .select { filter { eq("session_id", lSid) } }
        val rD = supabase.from(BackendContracts.Tables.RACKET_SESSION_STATS)
            .select { filter { eq("session_id", rSid) } }
        val a = json.decodeFromString<List<Rk>>(lD.data).firstOrNull() ?: return
        val b = json.decodeFromString<List<Rk>>(rD.data).firstOrNull() ?: return
        out.addM("rk_sets_won", "sets", a.setsWon?.toDouble(), b.setsWon?.toDouble())
        out.addM("rk_sets_lost", "sets", a.setsLost?.toDouble(), b.setsLost?.toDouble())
        out.addM("rk_games_won", "games", a.gamesWon?.toDouble(), b.gamesWon?.toDouble())
        out.addM("rk_games_lost", "games", a.gamesLost?.toDouble(), b.gamesLost?.toDouble())
        out.addM("rk_aces", "count", a.aces?.toDouble(), b.aces?.toDouble())
        out.addM("rk_double_faults", "count", a.doubleFaults?.toDouble(), b.doubleFaults?.toDouble())
        out.addM("rk_winners", "count", a.winners?.toDouble(), b.winners?.toDouble())
        out.addM("rk_unforced_errors", "count", a.unforcedErrors?.toDouble(), b.unforcedErrors?.toDouble())
        out.addM("rk_break_points_won", "count", a.breakPointsWon?.toDouble(), b.breakPointsWon?.toDouble())
        out.addM("rk_break_points_total", "count", a.breakPointsTotal?.toDouble(), b.breakPointsTotal?.toDouble())
        out.addM("rk_net_points_won", "count", a.netPointsWon?.toDouble(), b.netPointsWon?.toDouble())
        out.addM("rk_net_points_total", "count", a.netPointsTotal?.toDouble(), b.netPointsTotal?.toDouble())
    }

    @Serializable
    private data class Bb(
        val points: Int? = null, val rebounds: Int? = null, val assists: Int? = null,
        val steals: Int? = null, val blocks: Int? = null,
        @SerialName("fg_made") val fgMade: Int? = null,
        @SerialName("fg_attempted") val fgAttempted: Int? = null,
        @SerialName("three_made") val threeMade: Int? = null,
        @SerialName("three_attempted") val threeAttempted: Int? = null,
        @SerialName("ft_made") val ftMade: Int? = null,
        @SerialName("ft_attempted") val ftAttempted: Int? = null,
        val turnovers: Int? = null, val fouls: Int? = null
    )

    private suspend fun addBb(json: Json, s: SupabaseClient, a: Int, b: Int, out: MutableList<CompareMetricRow>) {
        val l = s.from(BackendContracts.Tables.BASKETBALL_SESSION_STATS).select { filter { eq("session_id", a) } }
        val r = s.from(BackendContracts.Tables.BASKETBALL_SESSION_STATS).select { filter { eq("session_id", b) } }
        val A = json.decodeFromString<List<Bb>>(l.data).firstOrNull() ?: return
        val B = json.decodeFromString<List<Bb>>(r.data).firstOrNull() ?: return
        out.addM("bb_points", "pts", A.points?.toDouble(), B.points?.toDouble())
        out.addM("bb_rebounds", "count", A.rebounds?.toDouble(), B.rebounds?.toDouble())
        out.addM("bb_assists", "count", A.assists?.toDouble(), B.assists?.toDouble())
        out.addM("bb_steals", "count", A.steals?.toDouble(), B.steals?.toDouble())
        out.addM("bb_blocks", "count", A.blocks?.toDouble(), B.blocks?.toDouble())
        out.addM("bb_fg_made", "count", A.fgMade?.toDouble(), B.fgMade?.toDouble())
        out.addM("bb_fg_attempted", "count", A.fgAttempted?.toDouble(), B.fgAttempted?.toDouble())
        out.addM("bb_three_made", "count", A.threeMade?.toDouble(), B.threeMade?.toDouble())
        out.addM("bb_three_attempted", "count", A.threeAttempted?.toDouble(), B.threeAttempted?.toDouble())
        out.addM("bb_ft_made", "count", A.ftMade?.toDouble(), B.ftMade?.toDouble())
        out.addM("bb_ft_attempted", "count", A.ftAttempted?.toDouble(), B.ftAttempted?.toDouble())
        out.addM("bb_turnovers", "count", A.turnovers?.toDouble(), B.turnovers?.toDouble())
        out.addM("bb_fouls", "count", A.fouls?.toDouble(), B.fouls?.toDouble())
    }

    @Serializable
    private data class Fb(
        @SerialName("minutes_played") val minutesPlayed: Int? = null,
        val goals: Int? = null, val assists: Int? = null,
        @SerialName("shots_on_target") val shotsOnTarget: Int? = null,
        @SerialName("passes_completed") val passesCompleted: Int? = null,
        @SerialName("passes_attempted") val passesAttempted: Int? = null,
        val tackles: Int? = null, val interceptions: Int? = null, val saves: Int? = null,
        @SerialName("yellow_cards") val yellowCards: Int? = null,
        @SerialName("red_cards") val redCards: Int? = null
    )

    private suspend fun addFb(json: Json, s: SupabaseClient, a: Int, b: Int, out: MutableList<CompareMetricRow>) {
        val l = s.from(BackendContracts.Tables.FOOTBALL_SESSION_STATS).select { filter { eq("session_id", a) } }
        val r = s.from(BackendContracts.Tables.FOOTBALL_SESSION_STATS).select { filter { eq("session_id", b) } }
        val A = json.decodeFromString<List<Fb>>(l.data).firstOrNull() ?: return
        val B = json.decodeFromString<List<Fb>>(r.data).firstOrNull() ?: return
        out.addM("fb_minutes_played", "min", A.minutesPlayed?.toDouble(), B.minutesPlayed?.toDouble())
        out.addM("fb_goals", "count", A.goals?.toDouble(), B.goals?.toDouble())
        out.addM("fb_assists", "count", A.assists?.toDouble(), B.assists?.toDouble())
        out.addM("fb_shots_on_target", "count", A.shotsOnTarget?.toDouble(), B.shotsOnTarget?.toDouble())
        out.addM("fb_passes_completed", "count", A.passesCompleted?.toDouble(), B.passesCompleted?.toDouble())
        out.addM("fb_passes_attempted", "count", A.passesAttempted?.toDouble(), B.passesAttempted?.toDouble())
        out.addM("fb_tackles", "count", A.tackles?.toDouble(), B.tackles?.toDouble())
        out.addM("fb_interceptions", "count", A.interceptions?.toDouble(), B.interceptions?.toDouble())
        out.addM("fb_saves", "count", A.saves?.toDouble(), B.saves?.toDouble())
        out.addM("fb_yellow_cards", "count", A.yellowCards?.toDouble(), B.yellowCards?.toDouble())
        out.addM("fb_red_cards", "count", A.redCards?.toDouble(), B.redCards?.toDouble())
    }

    @Serializable
    private data class Hb(
        @SerialName("minutes_played") val minutesPlayed: Int? = null,
        val goals: Int? = null, val shots: Int? = null,
        @SerialName("shots_on_target") val shotsOnTarget: Int? = null,
        val assists: Int? = null, val steals: Int? = null, val blocks: Int? = null,
        @SerialName("turnovers_lost") val turnoversLost: Int? = null,
        @SerialName("seven_m_goals") val sevenMGoals: Int? = null,
        @SerialName("seven_m_attempts") val sevenMAttempts: Int? = null,
        val saves: Int? = null,
        @SerialName("yellow_cards") val yellowCards: Int? = null,
        @SerialName("two_min_suspensions") val twoMin: Int? = null,
        @SerialName("red_cards") val redCards: Int? = null
    )

    private suspend fun addHb(json: Json, s: SupabaseClient, a: Int, b: Int, out: MutableList<CompareMetricRow>) {
        val l = s.from(BackendContracts.Tables.HANDBALL_SESSION_STATS).select { filter { eq("session_id", a) } }
        val r = s.from(BackendContracts.Tables.HANDBALL_SESSION_STATS).select { filter { eq("session_id", b) } }
        val A = json.decodeFromString<List<Hb>>(l.data).firstOrNull() ?: return
        val B = json.decodeFromString<List<Hb>>(r.data).firstOrNull() ?: return
        out.addM("hb_minutes_played", "min", A.minutesPlayed?.toDouble(), B.minutesPlayed?.toDouble())
        out.addM("hb_goals", "count", A.goals?.toDouble(), B.goals?.toDouble())
        out.addM("hb_shots", "count", A.shots?.toDouble(), B.shots?.toDouble())
        out.addM("hb_shots_on_target", "count", A.shotsOnTarget?.toDouble(), B.shotsOnTarget?.toDouble())
        out.addM("hb_assists", "count", A.assists?.toDouble(), B.assists?.toDouble())
        out.addM("hb_steals", "count", A.steals?.toDouble(), B.steals?.toDouble())
        out.addM("hb_blocks", "count", A.blocks?.toDouble(), B.blocks?.toDouble())
        out.addM("hb_turnovers_lost", "count", A.turnoversLost?.toDouble(), B.turnoversLost?.toDouble())
        out.addM("hb_seven_m_goals", "count", A.sevenMGoals?.toDouble(), B.sevenMGoals?.toDouble())
        out.addM("hb_seven_m_attempts", "count", A.sevenMAttempts?.toDouble(), B.sevenMAttempts?.toDouble())
        out.addM("hb_saves", "count", A.saves?.toDouble(), B.saves?.toDouble())
        out.addM("hb_yellow_cards", "count", A.yellowCards?.toDouble(), B.yellowCards?.toDouble())
        out.addM("hb_two_min_suspensions", "count", A.twoMin?.toDouble(), B.twoMin?.toDouble())
        out.addM("hb_red_cards", "count", A.redCards?.toDouble(), B.redCards?.toDouble())
    }

    @Serializable
    private data class Hk(
        @SerialName("minutes_played") val minutesPlayed: Int? = null,
        val goals: Int? = null, val assists: Int? = null,
        @SerialName("shots_on_goal") val shotsOnGoal: Int? = null,
        @SerialName("plus_minus") val plusMinus: Int? = null,
        val hits: Int? = null, val blocks: Int? = null,
        @SerialName("faceoffs_won") val faceoffsWon: Int? = null,
        @SerialName("faceoffs_total") val faceoffsTotal: Int? = null,
        val saves: Int? = null,
        @SerialName("penalty_minutes") val penaltyMinutes: Int? = null
    )

    private suspend fun addHk(json: Json, s: SupabaseClient, a: Int, b: Int, out: MutableList<CompareMetricRow>) {
        val l = s.from(BackendContracts.Tables.HOCKEY_SESSION_STATS).select { filter { eq("session_id", a) } }
        val r = s.from(BackendContracts.Tables.HOCKEY_SESSION_STATS).select { filter { eq("session_id", b) } }
        val A = json.decodeFromString<List<Hk>>(l.data).firstOrNull() ?: return
        val B = json.decodeFromString<List<Hk>>(r.data).firstOrNull() ?: return
        out.addM("hk_minutes_played", "min", A.minutesPlayed?.toDouble(), B.minutesPlayed?.toDouble())
        out.addM("hk_goals", "count", A.goals?.toDouble(), B.goals?.toDouble())
        out.addM("hk_assists", "count", A.assists?.toDouble(), B.assists?.toDouble())
        out.addM("hk_shots_on_goal", "count", A.shotsOnGoal?.toDouble(), B.shotsOnGoal?.toDouble())
        out.addM("hk_plus_minus", "count", A.plusMinus?.toDouble(), B.plusMinus?.toDouble())
        out.addM("hk_hits", "count", A.hits?.toDouble(), B.hits?.toDouble())
        out.addM("hk_blocks", "count", A.blocks?.toDouble(), B.blocks?.toDouble())
        out.addM("hk_faceoffs_won", "count", A.faceoffsWon?.toDouble(), B.faceoffsWon?.toDouble())
        out.addM("hk_faceoffs_total", "count", A.faceoffsTotal?.toDouble(), B.faceoffsTotal?.toDouble())
        out.addM("hk_saves", "count", A.saves?.toDouble(), B.saves?.toDouble())
        out.addM("hk_penalty_minutes", "min", A.penaltyMinutes?.toDouble(), B.penaltyMinutes?.toDouble())
    }

    @Serializable
    private data class Rg(
        @SerialName("minutes_played") val minutesPlayed: Int? = null,
        val tries: Int? = null,
        @SerialName("conversions_made") val convMade: Int? = null,
        @SerialName("conversions_attempted") val convAtt: Int? = null,
        @SerialName("penalty_goals_made") val penMade: Int? = null,
        @SerialName("penalty_goals_attempted") val penAtt: Int? = null,
        val runs: Int? = null, @SerialName("meters_gained") val meters: Int? = null,
        val offloads: Int? = null,
        @SerialName("tackles_made") val tackMade: Int? = null,
        @SerialName("tackles_missed") val tackMiss: Int? = null,
        @SerialName("turnovers_won") val turnovers: Int? = null,
        @SerialName("yellow_cards") val yc: Int? = null,
        @SerialName("red_cards") val rc: Int? = null
    )

    private suspend fun addRg(json: Json, s: SupabaseClient, a: Int, b: Int, out: MutableList<CompareMetricRow>) {
        val l = s.from(BackendContracts.Tables.RUGBY_SESSION_STATS).select { filter { eq("session_id", a) } }
        val r = s.from(BackendContracts.Tables.RUGBY_SESSION_STATS).select { filter { eq("session_id", b) } }
        val A = json.decodeFromString<List<Rg>>(l.data).firstOrNull() ?: return
        val B = json.decodeFromString<List<Rg>>(r.data).firstOrNull() ?: return
        out.addM("rg_minutes_played", "min", A.minutesPlayed?.toDouble(), B.minutesPlayed?.toDouble())
        out.addM("rg_tries", "count", A.tries?.toDouble(), B.tries?.toDouble())
        out.addM("rg_conversions_made", "count", A.convMade?.toDouble(), B.convMade?.toDouble())
        out.addM("rg_conversions_attempted", "count", A.convAtt?.toDouble(), B.convAtt?.toDouble())
        out.addM("rg_penalty_goals_made", "count", A.penMade?.toDouble(), B.penMade?.toDouble())
        out.addM("rg_penalty_goals_attempted", "count", A.penAtt?.toDouble(), B.penAtt?.toDouble())
        out.addM("rg_runs", "count", A.runs?.toDouble(), B.runs?.toDouble())
        out.addM("rg_meters_gained", "m", A.meters?.toDouble(), B.meters?.toDouble())
        out.addM("rg_offloads", "count", A.offloads?.toDouble(), B.offloads?.toDouble())
        out.addM("rg_tackles_made", "count", A.tackMade?.toDouble(), B.tackMade?.toDouble())
        out.addM("rg_tackles_missed", "count", A.tackMiss?.toDouble(), B.tackMiss?.toDouble())
        out.addM("rg_turnovers_won", "count", A.turnovers?.toDouble(), B.turnovers?.toDouble())
        out.addM("rg_yellow_cards", "count", A.yc?.toDouble(), B.yc?.toDouble())
        out.addM("rg_red_cards", "count", A.rc?.toDouble(), B.rc?.toDouble())
    }

    @Serializable
    private data class Hx(
        @SerialName("official_time_sec") val officialTime: Int? = null,
        @SerialName("rank_overall") val rankOverall: Int? = null,
        @SerialName("rank_category") val rankCat: Int? = null,
        @SerialName("no_reps") val noReps: Int? = null,
        @SerialName("penalty_time_sec") val penalty: Int? = null,
        @SerialName("avg_hr") val avgHr: Int? = null,
        @SerialName("max_hr") val maxHr: Int? = null
    )

    private suspend fun addHx(json: Json, s: SupabaseClient, a: Int, b: Int, out: MutableList<CompareMetricRow>) {
        val l = s.from(BackendContracts.Tables.HYROX_SESSION_STATS).select { filter { eq("session_id", a) } }
        val r = s.from(BackendContracts.Tables.HYROX_SESSION_STATS).select { filter { eq("session_id", b) } }
        val A = json.decodeFromString<List<Hx>>(l.data).firstOrNull() ?: return
        val B = json.decodeFromString<List<Hx>>(r.data).firstOrNull() ?: return
        out.addM("hx_official_time_sec", "sec", A.officialTime?.toDouble(), B.officialTime?.toDouble())
        out.addM("hx_rank_overall", "rank", A.rankOverall?.toDouble(), B.rankOverall?.toDouble())
        out.addM("hx_rank_category", "rank", A.rankCat?.toDouble(), B.rankCat?.toDouble())
        out.addM("hx_no_reps", "count", A.noReps?.toDouble(), B.noReps?.toDouble())
        out.addM("hx_penalty_time_sec", "sec", A.penalty?.toDouble(), B.penalty?.toDouble())
        out.addM("hx_avg_hr", "bpm", A.avgHr?.toDouble(), B.avgHr?.toDouble())
        out.addM("hx_max_hr", "bpm", A.maxHr?.toDouble(), B.maxHr?.toDouble())
    }

    @Serializable
    private data class Vb(
        val points: Int? = null, val aces: Int? = null, val blocks: Int? = null, val digs: Int? = null
    )

    private suspend fun addVb(json: Json, s: SupabaseClient, a: Int, b: Int, out: MutableList<CompareMetricRow>) {
        val l = s.from(BackendContracts.Tables.VOLLEYBALL_SESSION_STATS).select { filter { eq("session_id", a) } }
        val r = s.from(BackendContracts.Tables.VOLLEYBALL_SESSION_STATS).select { filter { eq("session_id", b) } }
        val A = json.decodeFromString<List<Vb>>(l.data).firstOrNull() ?: return
        val B = json.decodeFromString<List<Vb>>(r.data).firstOrNull() ?: return
        out.addM("vb_points", "count", A.points?.toDouble(), B.points?.toDouble())
        out.addM("vb_aces", "count", A.aces?.toDouble(), B.aces?.toDouble())
        out.addM("vb_blocks", "count", A.blocks?.toDouble(), B.blocks?.toDouble())
        out.addM("vb_digs", "count", A.digs?.toDouble(), B.digs?.toDouble())
    }

    @Serializable
    private data class HyEx(
        @SerialName("exercise_code") val exerciseCode: String,
        @SerialName("exercise_order") val exerciseOrder: Int = 0,
        @SerialName("distance_m") val distanceM: Int? = null,
        val reps: Int? = null,
        @SerialName("weight_kg") val weightKg: Double? = null,
        @SerialName("duration_sec") val durationSec: Int? = null,
        @SerialName("implement_count") val implementCount: Int? = null,
        @SerialName("exercise_display_name") val exerciseDisplayName: String? = null
    )

    private fun normCustom(s: String): String =
        Normalizer.normalize(s, Normalizer.Form.NFD)
            .replace("\\p{M}+".toRegex(), "")
            .lowercase()

    private fun rowsByOccurrence(rows: List<HyEx>): Map<String, HyEx> {
        val countByCode = mutableMapOf<String, Int>()
        val countByCustomNorm = mutableMapOf<String, Int>()
        val dict = linkedMapOf<String, HyEx>()
        for (r in rows.sortedBy { it.exerciseOrder }) {
            val c = r.exerciseCode.trim().lowercase()
            if (c.isEmpty()) continue
            val key = if (c == HYROX_CUSTOM) {
                val raw = r.exerciseDisplayName?.trim().orEmpty()
                if (raw.isEmpty()) continue
                val norm = normCustom(raw)
                val ord = countByCustomNorm.getOrDefault(norm, 0) + 1
                countByCustomNorm[norm] = ord
                "custom$CUSTOM_SEP$norm$CUSTOM_SEP$ord"
            } else {
                val ord = countByCode.getOrDefault(c, 0) + 1
                countByCode[c] = ord
                "${c}_$ord"
            }
            dict[key] = r
        }
        return dict
    }

    private suspend fun appendHyroxStations(
        json: Json,
        supabase: SupabaseClient,
        leftSessionId: Int,
        rightSessionId: Int,
        out: MutableList<CompareMetricRow>
    ) {
        val lQ = supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES)
            .select(
                columns = Columns.raw(
                    "exercise_code,exercise_order,distance_m,reps,weight_kg,duration_sec,implement_count,exercise_display_name"
                )
            ) {
                filter { eq("session_id", leftSessionId) }
                order("exercise_order", Order.ASCENDING)
            }
        val rQ = supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES)
            .select(
                columns = Columns.raw(
                    "exercise_code,exercise_order,distance_m,reps,weight_kg,duration_sec,implement_count,exercise_display_name"
                )
            ) {
                filter { eq("session_id", rightSessionId) }
                order("exercise_order", Order.ASCENDING)
            }
        val leftRows = json.decodeFromString<List<HyEx>>(lQ.data)
        val rightRows = json.decodeFromString<List<HyEx>>(rQ.data)
        val leftMap = rowsByOccurrence(leftRows)
        val rightMap = rowsByOccurrence(rightRows)
        val keys = (leftMap.keys.intersect(rightMap.keys.toSet())).toList().sortedBy { k -> leftMap[k]!!.exerciseOrder }
        for (key in keys) {
            val a = leftMap[key]!!; val b = rightMap[key]!!
            fun m(field: String) = "hyrox.station.$key.$field"
            out.addM(m("distance_m"), "m", a.distanceM?.toDouble(), b.distanceM?.toDouble())
            out.addM(m("reps"), "count", a.reps?.toDouble(), b.reps?.toDouble())
            out.addM(m("duration_sec"), "sec", a.durationSec?.toDouble(), b.durationSec?.toDouble())
            out.addM(m("weight_kg"), "kg", a.weightKg, b.weightKg)
            out.addM(m("implement_count"), "count", a.implementCount?.toDouble(), b.implementCount?.toDouble())
        }
    }
}
