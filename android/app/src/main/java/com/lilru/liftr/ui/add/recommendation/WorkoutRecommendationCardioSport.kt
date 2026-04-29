package com.lilru.liftr.ui.add.recommendation

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlin.math.max
import kotlin.math.min
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
private data class CardioStatRow(
    @SerialName("session_id") val sessionId: Int,
    val stats: CardioStatsPayload? = null
)

@Serializable
private data class CardioStatsPayload(
    @SerialName("cadence_rpm") val cadenceRpm: Int? = null,
    @SerialName("watts_avg") val wattsAvg: Int? = null,
    @SerialName("incline_pct") val inclinePct: Double? = null,
    @SerialName("swim_laps") val swimLaps: Int? = null,
    @SerialName("pool_length_m") val poolLengthM: Int? = null,
    @SerialName("swim_style") val swimStyle: String? = null,
    @SerialName("split_sec_per_500m") val splitSecPer500m: Int? = null
)

private data class HyroxExRow(
    @SerialName("exercise_code") val exerciseCode: String,
    @SerialName("exercise_order") val exerciseOrder: Int? = null,
    @SerialName("distance_m") val distanceM: Int? = null,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("height_cm") val heightCm: Int? = null,
    @SerialName("implement_count") val implementCount: Int? = null,
    @SerialName("exercise_display_name") val exerciseDisplayName: String? = null
)

/**
 * Cardio + sport branches of iOS [WorkoutRecommendationService] (separate file for size).
 */
object WorkoutRecommendationCardioSport {
    private const val lookback = 10

    private fun medianInt(arr: List<Int>): Int {
        if (arr.isEmpty()) return 3600
        val s = arr.sorted()
        return s[s.size / 2]
    }

    private fun medianIntOpt(arr: List<Int>): Int? {
        if (arr.isEmpty()) return null
        val s = arr.sorted()
        return s[s.size / 2]
    }

    private fun medianDoubleOpt(arr: List<Double>): Double? {
        if (arr.isEmpty()) return null
        val s = arr.sorted()
        return s[s.size / 2]
    }

    private fun medianSportMinutes(arr: List<Int>): Int {
        if (arr.isEmpty()) return 60
        val s = arr.sorted()
        return max(15, s[s.size / 2])
    }

    suspend fun recommendCardio(
        supabase: SupabaseClient,
        json: Json,
        userId: String,
        source: RecommendationDataSource
    ): CardioRecommendationResult {
        @Serializable
        data class WRow(val id: Int)
        val wRes = supabase.from(BackendContracts.Tables.WORKOUTS)
            .select(Columns.raw("id")) {
                filter {
                    eq("user_id", userId)
                    eq("kind", "cardio")
                    eq("state", "published")
                }
                order("started_at", Order.DESCENDING)
                limit(lookback.toLong())
            }
        val wRows = json.decodeFromString<List<WRow>>(wRes.data)
        if (wRows.isEmpty()) {
            if (source == RecommendationDataSource.FULL_CATALOG) {
                return beginnerWalkCardio()
            }
            throw WorkoutRecommendationError.NoWorkoutsInWindow
        }
        val ids = wRows.map { it.id.toString() }
        @Serializable
        data class CS(
            val id: Int,
            val modality: String? = null,
            @SerialName("activity_code") val activityCode: String? = null,
            @SerialName("duration_sec") val durationSec: Int? = null,
            @SerialName("distance_km") val distanceKm: Double? = null,
            @SerialName("avg_hr") val avgHr: Int? = null,
            @SerialName("max_hr") val maxHr: Int? = null,
            @SerialName("elevation_gain_m") val elevationGainM: Int? = null
        )
        val res = supabase.from(BackendContracts.Tables.CARDIO_SESSIONS)
            .select(
                Columns.raw(
                    "id, workout_id, modality, activity_code, duration_sec, distance_km, avg_hr, max_hr, elevation_gain_m"
                )
            ) {
                filter { isIn("workout_id", ids) }
            }
        val rows = json.decodeFromString<List<CS>>(res.data)
        data class Enriched(
            val id: Int,
            val code: String,
            val duration: Int,
            val distance: Double?,
            val elevationM: Int?,
            val avgHr: Int?,
            val maxHr: Int?
        )
        val sessions = rows.map { cs ->
            val code = (cs.activityCode ?: cs.modality ?: "run").lowercase()
            val dur = cs.durationSec ?: 3600
            Enriched(
                id = cs.id,
                code = code,
                duration = dur,
                distance = cs.distanceKm,
                elevationM = cs.elevationGainM,
                avgHr = cs.avgHr,
                maxHr = cs.maxHr
            )
        }
        if (sessions.isEmpty()) {
            if (source == RecommendationDataSource.FULL_CATALOG) {
                return beginnerWalkCardio()
            }
            throw WorkoutRecommendationError.LoadFailed("No cardio session rows.")
        }
        val counts = sessions.groupingBy { it.code }.eachCount()
        val allCodes = listOf(
            "run", "walk", "hike", "treadmill", "bike", "e_bike", "mtb",
            "indoor_cycling", "rowerg", "swim_pool", "swim_open_water"
        )
        val candidateCodes = when (source) {
            RecommendationDataSource.RECENT_HISTORY,
            RecommendationDataSource.HYROX,
            RecommendationDataSource.HYROX_RACE -> sessions.map { it.code }.distinct()
            RecommendationDataSource.FULL_CATALOG -> allCodes
        }
        val sortedByRare = candidateCodes.sortedBy { counts[it] ?: 0 }
        val pickedCode = sortedByRare.firstOrNull() ?: "walk"
        val matching = sessions.filter { it.code == pickedCode }
        val usedCrossActivityFallback = matching.isEmpty()
        val scalarPool = if (usedCrossActivityFallback) sessions else matching
        val durs = matching.map { it.duration }
        val medianDur = medianInt(if (durs.isEmpty()) sessions.map { it.duration } else durs)
        val distancePool = when {
            !usedCrossActivityFallback -> matching
            pickedCode == "swim_pool" || pickedCode == "swim_open_water" -> {
                val swim = sessions.filter { it.code == "swim_pool" || it.code == "swim_open_water" }
                if (swim.isEmpty()) sessions else swim
            }
            else -> sessions
        }
        val medianDist = medianDoubleOpt(distancePool.mapNotNull { it.distance })
        val showElev = pickedCode !in setOf("swim_pool", "swim_open_water", "rowerg", "indoor_cycling", "treadmill")
        val medianElev = if (showElev) {
            medianIntOpt(scalarPool.mapNotNull { it.elevationM })
        } else {
            null
        }
        val medAvg = medianIntOpt(scalarPool.mapNotNull { it.avgHr })
        val medMax = medianIntOpt(scalarPool.mapNotNull { it.maxHr })
        val statIds = (if (usedCrossActivityFallback) sessions else matching).map { it.id }
        val statsBySession: Map<Int, CardioStatsPayload> = if (statIds.isEmpty()) {
            emptyMap()
        } else {
            runCatching {
                val stRes = supabase.from(BackendContracts.Tables.CARDIO_SESSION_STATS)
                    .select(Columns.raw("session_id, stats")) {
                        filter { isIn("session_id", statIds.map { it.toString() }) }
                    }
                val parsed = json.decodeFromString<List<CardioStatRow>>(stRes.data)
                parsed.mapNotNull { row -> row.stats?.let { row.sessionId to it } }.toMap()
            }.getOrDefault(emptyMap())
        }
        val showIncline = pickedCode == "treadmill"
        val showCadW = pickedCode in setOf("indoor_cycling", "bike", "e_bike", "mtb", "rowerg")
        val showWatts = pickedCode in setOf("indoor_cycling", "rowerg", "bike", "mtb")
        val showSplit = pickedCode == "rowerg"
        val showSwim = pickedCode == "swim_pool"
        val incl = if (showIncline) {
            medianDoubleOpt(scalarPool.mapNotNull { statsBySession[it.id]?.inclinePct })
        } else {
            null
        }
        val cad = if (showCadW) {
            medianIntOpt(scalarPool.mapNotNull { statsBySession[it.id]?.cadenceRpm })
        } else {
            null
        }
        val watts = if (showWatts) {
            medianIntOpt(scalarPool.mapNotNull { statsBySession[it.id]?.wattsAvg })
        } else {
            null
        }
        val sp500 = if (showSplit) {
            medianIntOpt(scalarPool.mapNotNull { statsBySession[it.id]?.splitSecPer500m })
        } else {
            null
        }
        val laps = if (showSwim) {
            medianIntOpt(scalarPool.mapNotNull { statsBySession[it.id]?.swimLaps })
        } else {
            null
        }
        val poolL = if (showSwim) {
            medianIntOpt(scalarPool.mapNotNull { statsBySession[it.id]?.poolLengthM })
        } else {
            null
        }
        val style = if (showSwim) {
            scalarPool.mapNotNull { statsBySession[it.id]?.swimStyle }
                .firstOrNull { it.isNotBlank() }
        } else {
            null
        }
        var rationale = "Among ${if (source == RecommendationDataSource.FULL_CATALOG) "all app activities" else "activities you logged"}, this one was least frequent in your last $lookback cardio workouts."
        if (usedCrossActivityFallback) {
            rationale += " Values are estimated from your other cardio in this window, since you haven't logged this activity yet."
        }
        return CardioRecommendationResult(
            activityWire = pickedCode,
            durationSec = medianDur,
            distanceKm = medianDist,
            elevationGainM = medianElev,
            avgHr = medAvg,
            maxHr = medMax,
            inclinePercent = incl,
            cadenceRpm = cad,
            wattsAvg = watts,
            splitSecPer500m = sp500,
            swimLaps = laps,
            poolLengthM = poolL,
            swimStyle = style,
            rationale = rationale
        )
    }

    private fun beginnerWalkCardio() = CardioRecommendationResult(
        activityWire = "walk",
        durationSec = 30 * 60,
        distanceKm = 2.2,
        elevationGainM = 25,
        avgHr = 112,
        maxHr = 132,
        inclinePercent = null,
        cadenceRpm = null,
        wattsAvg = null,
        splitSecPer500m = null,
        swimLaps = null,
        poolLengthM = null,
        swimStyle = null,
        rationale = "You don't have cardio workouts in your history yet. These are easy starter targets (conversation-pace effort)—adjust any field in the form."
    )

    private data class SportSess(val id: Int, val sport: String, val durationMin: Int)

    suspend fun recommendSport(
        supabase: SupabaseClient,
        json: Json,
        userId: String,
        source: RecommendationDataSource
    ): SportRecommendationResult {
        @Serializable
        data class WRow(val id: Int)
        val wRes = supabase.from(BackendContracts.Tables.WORKOUTS)
            .select(Columns.raw("id")) {
                filter {
                    eq("user_id", userId)
                    eq("kind", "sport")
                    eq("state", "published")
                }
                order("started_at", Order.DESCENDING)
                limit(lookback.toLong())
            }
        val wRows = json.decodeFromString<List<WRow>>(wRes.data)
        if (wRows.isEmpty()) {
            return emptySportHistory(source)
        }
        val widStrings = wRows.map { it.id.toString() }
        @Serializable
        data class SS(
            val id: Int,
            val sport: String? = null,
            @SerialName("duration_sec") val durationSec: Int? = null
        )
        val res = supabase.from(BackendContracts.Tables.SPORT_SESSIONS)
            .select(Columns.raw("id, sport, duration_sec")) {
                filter { isIn("workout_id", widStrings) }
            }
        val srows = json.decodeFromString<List<SS>>(res.data)
        val sessions = srows.mapNotNull { ss ->
            val sp = ss.sport?.lowercase()?.trim()
            if (sp.isNullOrEmpty()) return@mapNotNull null
            val dm = max(1, (ss.durationSec?.div(60) ?: 60))
            SportSess(id = ss.id, sport = sp, durationMin = dm)
        }
        if (sessions.isEmpty()) {
            return emptySportHistory(source)
        }
        if (source == RecommendationDataSource.HYROX) {
            return hyroxSportMixed(supabase, json, sessions)
        }
        if (source == RecommendationDataSource.HYROX_RACE) {
            return hyroxRace(supabase, json, sessions)
        }
        val counts = sessions.groupingBy { it.sport }.eachCount()
        val allSports = listOf(
            "padel", "tennis", "football", "basketball", "badminton", "squash",
            "table_tennis", "volleyball", "handball", "hockey", "rugby", "hyrox", "ski"
        )
        val candidates = when (source) {
            RecommendationDataSource.RECENT_HISTORY -> sessions.map { it.sport }.distinct()
            RecommendationDataSource.FULL_CATALOG -> allSports
            else -> emptyList()
        }.ifEmpty { sessions.map { it.sport }.distinct() }
        val raw = candidates.minByOrNull { counts[it] ?: 0 }
            ?: throw WorkoutRecommendationError.LoadFailed("Could not pick a sport.")
        val matching = sessions.filter { it.sport == raw }
        val allM = sessions.map { it.durationMin }
        val matchM = matching.map { it.durationMin }
        val medMin = medianSportMinutes(if (matchM.isEmpty()) allM else matchM)
        var r = "Among ${if (source == RecommendationDataSource.RECENT_HISTORY) "sports you logged" else "all app sports"}, this one was least frequent in your last $lookback sessions."
        if (raw != "hyrox") {
            r += " Suggested session length only—choose whichever sport fits in the form."
            return SportRecommendationResult.DurationOnly(medMin, r)
        }
        val hyroxSessIds = sessions.filter { it.sport == "hyrox" }.map { it.id }
        var exRows: List<HyroxExRow> = emptyList()
        if (hyroxSessIds.isNotEmpty()) {
            runCatching {
                val exRes = supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES)
                    .select(
                        Columns.raw(
                            "exercise_code, exercise_order, distance_m, reps, weight_kg, duration_sec, height_cm, implement_count, exercise_display_name"
                        )
                    ) {
                        filter { isIn("session_id", hyroxSessIds.map { it.toString() }) }
                    }
                exRows = json.decodeFromString<List<HyroxExRow>>(exRes.data)
            }
        }
        val exercises = buildHyroxExerciseRecommendations(json, exRows)
        r += if (exRows.isEmpty()) {
            " No Hyrox stations in your history yet—here's a starter template you can edit."
        } else {
            " Stations lean on ones you've logged less often, using typical numbers from your Hyrox sessions."
        }
        return SportRecommendationResult.Hyrox(medMin, exercises, r)
    }

    private fun emptySportHistory(source: RecommendationDataSource): SportRecommendationResult {
        if (source == RecommendationDataSource.FULL_CATALOG) {
            return SportRecommendationResult.DurationOnly(
                60,
                "You don't have sport workouts in your history yet. Here's a session length you can use with any sport—adjust as you like."
            )
        }
        if (source == RecommendationDataSource.HYROX) {
            return SportRecommendationResult.Hyrox(
                60,
                hyroxColdStart(),
                "You don't have sport workouts in your history yet. Here's a short Hyrox block: easy run, then station, repeated—adjust distances and loads as you like."
            )
        }
        if (source == RecommendationDataSource.HYROX_RACE) {
            val ex = officialRaceHyroxWithRuns(
                HyroxWeightTier.OPEN_MEN,
                1000,
                5
            )
            return SportRecommendationResult.Hyrox(
                60,
                ex,
                "No sport history yet. Moderate race-style block (5 stations + runs). Add stations in the form when you're ready for more volume."
            )
        }
        throw WorkoutRecommendationError.NoWorkoutsInWindow
    }

    private suspend fun hyroxSportMixed(
        supabase: SupabaseClient,
        json: Json,
        sessions: List<SportSess>
    ): SportRecommendationResult {
        val hyroxS = sessions.filter { it.sport == "hyrox" }
        val allM = sessions.map { it.durationMin }
        val hM = hyroxS.map { it.durationMin }
        val medMin = medianSportMinutes(if (hM.isEmpty()) allM else hM)
        val hIds = hyroxS.map { it.id }
        var exRows: List<HyroxExRow> = emptyList()
        if (hIds.isNotEmpty()) {
            runCatching {
                val exRes = supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES)
                    .select(
                        Columns.raw(
                            "exercise_code, exercise_order, distance_m, reps, weight_kg, duration_sec, height_cm, implement_count, exercise_display_name"
                        )
                    ) {
                        filter { isIn("session_id", hIds.map { it.toString() }) }
                    }
                exRows = json.decodeFromString<List<HyroxExRow>>(exRes.data)
            }
        }
        val exercises = buildHyroxExerciseRecommendations(json, exRows)
        val rationale = when {
            hyroxS.isEmpty() ->
                "No Hyrox in your last $lookback sport sessions—duration reflects your other sports. Here's a short race-style starter (runs + stations) you can edit."
            exRows.isEmpty() ->
                "Hyrox duration from your recent Hyrox sessions; station list is a starter template until you log station details."
            else ->
                "Hyrox session built from stations you've used less often lately, using typical distances and loads from your logs."
        }
        return SportRecommendationResult.Hyrox(medMin, exercises, rationale)
    }

    private suspend fun hyroxRace(
        supabase: SupabaseClient,
        json: Json,
        sessions: List<SportSess>
    ): SportRecommendationResult {
        val hyroxS = sessions.filter { it.sport == "hyrox" }
        val allM = sessions.map { it.durationMin }
        val hM = hyroxS.map { it.durationMin }
        val rawDurationMedian = medianSportMinutes(if (hM.isEmpty()) allM else hM)
        val hIds = hyroxS.map { it.id }
        var exRows: List<HyroxExRow> = emptyList()
        if (hIds.isNotEmpty()) {
            runCatching {
                val exRes = supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES)
                    .select(
                        Columns.raw(
                            "exercise_code, exercise_order, distance_m, reps, weight_kg, duration_sec, height_cm, implement_count, exercise_display_name"
                        )
                    ) {
                        filter { isIn("session_id", hIds.map { it.toString() }) }
                    }
                exRows = json.decodeFromString<List<HyroxExRow>>(exRes.data)
            }
        }
        val tier = inferHyroxWeightTier(
            hyroxWeightMedian(exRows, "sandbag_lunges"),
            hyroxWeightMedian(exRows, "wall_ball"),
            hyroxWeightMedian(exRows, "sled_push")
        )
        val runM = medianHyroxRunM(exRows)
        val inferring = hM.isEmpty() && allM.isNotEmpty()
        val fromDur = raceFormatStationCount(rawDurationMedian)
        val cap = experienceCap(hyroxS.size, inferring)
        val stationCount = min(fromDur, cap)
        val exercises = officialRaceHyroxWithRuns(tier, runM, stationCount)
        val durationSuggested = maxOf(
            min(rawDurationMedian, stationCount * 15),
            stationCount * 9,
            35
        )
        return SportRecommendationResult.Hyrox(
            durationSuggested,
            exercises,
            "Race-style flow: $stationCount official stations in order (${tier.name} loads), easy runs between. Adjust in the form."
        )
    }

    private fun hyroxWeightMedian(rows: List<HyroxExRow>, code: String): Double? {
        val g = rows.filter { it.exerciseCode.equals(code, ignoreCase = true) }
        return medianDoubleOpt(g.mapNotNull { it.weightKg })
    }

    private fun medianHyroxRunM(rows: List<HyroxExRow>): Int {
        val runs = rows.filter { it.exerciseCode.equals("run", ignoreCase = true) }
        val dists = runs.mapNotNull { it.distanceM }.filter { it >= 100 }
        val m = medianIntOpt(dists) ?: return 1000
        if (m < 400) return 1000
        return min(m, 5000)
    }

    private fun raceFormatStationCount(medianMin: Int) = when {
        medianMin < 32 -> 3
        medianMin < 48 -> 4
        medianMin < 62 -> 5
        medianMin < 80 -> 6
        medianMin < 100 -> 7
        else -> 8
    }

    private fun experienceCap(hyroxInWindow: Int, inferringFromOther: Boolean) = when {
        inferringFromOther -> min(6, max(4, 3 + hyroxInWindow))
        hyroxInWindow == 0 -> 4
        hyroxInWindow == 1 -> 4
        hyroxInWindow == 2 -> 5
        hyroxInWindow == 3 -> 6
        hyroxInWindow == 4 -> 7
        else -> 8
    }

    private fun buildHyroxExerciseRecommendations(
        @Suppress("unused") json: Json,
        rows: List<HyroxExRow>
    ): List<HyroxExerciseRecommendationResult> {
        if (rows.isEmpty()) return hyroxColdStart()
        val byCode = rows.groupBy { it.exerciseCode.lowercase() }
        val stdOrder = listOf(
            "skierg", "sled_pull", "sled_push", "burpee_broad_jump", "row", "farmer_carry",
            "sandbag_lunges", "wall_ball", "atlas_carry", "box_jump_over", "dead_ball_over_trunk", "run"
        ).mapIndexed { i, c -> c to i }.toMap()
        val codesSorted = byCode.keys.sortedWith(compareBy(
            { byCode[it]?.size ?: 0 },
            { stdOrder[it] ?: 999 }
        ))
        val picked = codesSorted.take(6)
        return picked.mapIndexed { idx, code ->
            val group = byCode[code].orEmpty()
            val (fcode, cname) = hyroxFormFields(
                code,
                group.mapNotNull { it.exerciseDisplayName?.trim() }
                    .firstOrNull { it.isNotEmpty() }
            )
            val sanitized = sanitizeHyroxExerciseRecommendation(
                HyroxExerciseRecommendationResult(
                    exerciseCode = fcode,
                    customDisplayName = cname,
                    exerciseOrder = idx + 1,
                    distanceM = medianIntOpt(group.mapNotNull { it.distanceM }),
                    reps = medianIntOpt(group.mapNotNull { it.reps }),
                    weightKg = medianDoubleOpt(group.mapNotNull { it.weightKg }),
                    durationSec = medianIntOpt(group.mapNotNull { it.durationSec }),
                    heightCm = medianIntOpt(group.mapNotNull { it.heightCm }),
                    implementCount = medianIntOpt(group.mapNotNull { it.implementCount }),
                    notes = null
                )
            )
            sanitized
        }
    }

    private const val customCode = "custom"

    private fun hyroxFormFields(
        exerciseCode: String,
        display: String?
    ): Pair<String, String> {
        val std = setOf(
            "run", "skierg", "burpee_broad_jump", "sled_push", "sled_pull", "row",
            "farmer_carry", "sandbag_lunges", "wall_ball", "atlas_carry", "box_jump_over", "dead_ball_over_trunk"
        )
        val c = exerciseCode.lowercase()
        if (c in std) return c to ""
        if (c == customCode) return customCode to (display ?: "")
        return c to (display ?: "")
    }

    private fun hyroxColdStart() = officialRaceHyroxWithRuns(HyroxWeightTier.OPEN_MEN, 1000, 4)
}
