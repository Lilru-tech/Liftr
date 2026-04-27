package com.lilru.liftr.ui.add

import com.lilru.liftr.hyrox.HyroxExerciseFormatting
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * [p_stats] compartido entre Add ([AddWorkoutViewModel.createSportWorkout]) y
 * detalle — edición de metadatos ([WorkoutDetailViewModel.updateSportWorkoutMeta]), alineado con iOS
 * [AddWorkoutSheet] / [EditWorkoutMetaSheet] `buildSportStatsJSON`.
 */
object SportStatsPayloadBuilder {
    private val json = Json { ignoreUnknownKeys = true }

    fun build(
        sport: AddSportType,
        durationMinText: String,
        footballPosition: AddFootballPosition,
        racketMode: AddRacketMode,
        racketFormat: AddRacketFormat,
        sportStats: Map<String, String>,
        hyroxExercisesText: String
    ) = buildJsonObject {
        fun parseIntLocal(value: String): Int? = value.trim().toIntOrNull()
        fun parseDoubleLocal(value: String): Double? =
            value.trim().replace(",", ".").toDoubleOrNull()
        fun statInt(key: String): Int? = parseIntLocal(sportStats[key].orEmpty())
        fun statDouble(key: String): Double? = parseDoubleLocal(sportStats[key].orEmpty())
        fun statString(key: String): String? = sportStats[key]?.trim()?.takeIf { it.isNotEmpty() }
        fun parseJsonObject(text: String): Map<String, JsonElement>? {
            if (text.isBlank()) return null
            return runCatching {
                json.parseToJsonElement(text.trim()).jsonObject.toMap()
            }.getOrNull()
        }
        when (sport) {
            AddSportType.FOOTBALL -> {
                put("position", footballPosition.wire)
                parseIntLocal(durationMinText)?.let { put("minutes_played", it) }
                statInt("assists")?.let { put("assists", it) }
                statInt("shots_on_target")?.let { put("shots_on_target", it) }
                statInt("passes_completed")?.let { put("passes_completed", it) }
                statInt("tackles")?.let { put("tackles", it) }
                statInt("saves")?.let { put("saves", it) }
                statInt("yellow_cards")?.let { put("yellow_cards", it) }
                statInt("red_cards")?.let { put("red_cards", it) }
            }
            AddSportType.BASKETBALL -> {
                listOf("points", "rebounds", "assists", "steals", "blocks", "turnovers", "fouls")
                    .forEach { key -> statInt(key)?.let { put(key, it) } }
            }
            AddSportType.PADEL, AddSportType.TENNIS, AddSportType.BADMINTON, AddSportType.SQUASH, AddSportType.TABLE_TENNIS -> {
                parseJsonObject(sportStats["racket_stats_raw"].orEmpty())?.forEach { (k, v) -> put(k, v) }
                listOf(
                    "aces", "double_faults", "winners", "unforced_errors", "sets_won", "sets_lost",
                    "games_won", "games_lost", "break_points_won", "break_points_total",
                    "net_points_won", "net_points_total"
                ).forEach { key -> statInt(key)?.let { put(key, it) } }
                put("racket_mode", racketMode.wire)
                put("racket_format", racketFormat.wire)
            }
            AddSportType.VOLLEYBALL -> {
                listOf("points", "aces", "blocks", "digs")
                    .forEach { key -> statInt(key)?.let { put(key, it) } }
            }
            AddSportType.HANDBALL -> {
                parseJsonObject(sportStats["raw_stats_json"].orEmpty())?.forEach { (k, v) -> put(k, v) }
                statString("position")?.let { put("position", it) }
                parseIntLocal(durationMinText)?.let { put("minutes_played", it) }
                listOf(
                    "goals", "shots", "shots_on_target", "assists", "steals", "blocks",
                    "turnovers_lost", "seven_m_goals", "seven_m_attempts", "saves",
                    "yellow_cards", "two_min_suspensions", "red_cards"
                ).forEach { key -> statInt(key)?.let { put(key, it) } }
            }
            AddSportType.HOCKEY -> {
                parseJsonObject(sportStats["raw_stats_json"].orEmpty())?.forEach { (k, v) -> put(k, v) }
                statString("position")?.let { put("position", it) }
                parseIntLocal(durationMinText)?.let { put("minutes_played", it) }
                listOf(
                    "goals", "assists", "shots_on_goal", "plus_minus", "hits", "blocks",
                    "faceoffs_won", "faceoffs_total", "saves", "penalty_minutes"
                ).forEach { key -> statInt(key)?.let { put(key, it) } }
            }
            AddSportType.RUGBY -> {
                parseJsonObject(sportStats["raw_stats_json"].orEmpty())?.forEach { (k, v) -> put(k, v) }
                statString("position")?.let { put("position", it) }
                parseIntLocal(durationMinText)?.let { put("minutes_played", it) }
                listOf(
                    "tries", "conversions_made", "conversions_attempted", "penalty_goals_made",
                    "penalty_goals_attempted", "runs", "meters_gained", "offloads",
                    "tackles_made", "tackles_missed", "turnovers_won", "yellow_cards", "red_cards"
                ).forEach { key -> statInt(key)?.let { put(key, it) } }
            }
            AddSportType.HYROX -> {
                parseJsonObject(sportStats["raw_stats_json"].orEmpty())?.forEach { (k, v) -> put(k, v) }
                listOf("division", "category", "age_group")
                    .forEach { key -> statString(key)?.let { put(key, it) } }
                listOf(
                    "official_time_sec", "rank_overall", "rank_category", "no_reps",
                    "penalty_time_sec", "avg_hr", "max_hr"
                ).forEach { key -> statInt(key)?.let { put(key, it) } }
                put("exercises", buildHyroxExercisesStatsPayload(hyroxExercisesText))
            }
            AddSportType.SKI -> {
                parseJsonObject(sportStats["raw_stats_json"].orEmpty())?.forEach { (k, v) -> put(k, v) }
                statDouble("total_distance_km")?.let { put("total_distance_km", it) }
                statDouble("max_speed_kmh")?.let { put("max_speed_kmh", it) }
                statDouble("avg_speed_kmh")?.let { put("avg_speed_kmh", it) }
                listOf("runs_count", "vertical_drop_m", "moving_time_sec", "paused_time_sec")
                    .forEach { key -> statInt(key)?.let { put(key, it) } }
                listOf("resort_name", "snow_condition", "weather")
                    .forEach { key -> statString(key)?.let { put(key, it) } }
            }
        }
    }

    private fun buildHyroxExercisesStatsPayload(hyroxExercisesText: String) = buildJsonArray {
        val root = runCatching { json.parseToJsonElement(hyroxExercisesText.trim()).jsonArray }
            .getOrNull() ?: error("Invalid Hyrox exercises JSON.")
        if (root.isEmpty()) error("Hyrox needs at least one station.")
        root.forEachIndexed { index, el ->
            val o = el as? JsonObject
                ?: error("Each Hyrox exercise must be a JSON object.")
            add(buildHyroxExerciseStatsObject(o, index))
        }
    }

    private fun buildHyroxExerciseStatsObject(o: JsonObject, index: Int): JsonObject {
        val code = jsonStringFromObject(o, "exercise_code", "exerciseCode")
            ?: error("Missing exercise_code (row ${index + 1}).")
        val custom = (
            o["custom_display_name"]?.jsonPrimitive?.contentOrNull
                ?: o["exercise_display_name"]?.jsonPrimitive?.contentOrNull
                ?: ""
        ).trim()
        val notesRaw = o["notes"]?.jsonPrimitive?.contentOrNull ?: ""
        val p = HyroxExerciseFormatting.persistedPayload(code, custom, notesRaw)
        return buildJsonObject {
            put("exercise_code", p.code)
            p.displayName?.let { put("exercise_display_name", it) }
            put("exercise_order", index + 1)
            jsonIntFromObject(o, "distance_m", "distanceM")?.let { put("distance_m", it) }
            jsonIntFromObject(o, "reps")?.let { put("reps", it) }
            jsonDoubleFromObject(o, "weight_kg", "weightKg")?.let { put("weight_kg", it) }
            jsonIntFromObject(o, "duration_sec", "durationSec")?.let { put("duration_sec", it) }
            jsonIntFromObject(o, "height_cm", "heightCm")?.let { put("height_cm", it) }
            jsonIntFromObject(o, "implement_count", "implementCount")?.let { put("implement_count", it) }
            if (notesRaw.isNotBlank()) {
                put("notes", notesRaw.trim())
            }
        }
    }

    private fun jsonStringFromObject(o: JsonObject, vararg keys: String): String? {
        for (k in keys) {
            o[k]?.jsonPrimitive?.contentOrNull?.let { t ->
                val s = t.trim()
                if (s.isNotEmpty()) return s
            }
        }
        return null
    }

    private fun jsonIntFromObject(o: JsonObject, vararg keys: String): Int? {
        for (k in keys) {
            val p = o[k]?.jsonPrimitive ?: continue
            p.contentOrNull?.replace(",", ".")?.trim()?.toIntOrNull()?.let { return it }
        }
        return null
    }

    private fun jsonDoubleFromObject(o: JsonObject, vararg keys: String): Double? {
        for (k in keys) {
            val p = o[k]?.jsonPrimitive ?: continue
            p.contentOrNull?.replace(",", ".")?.trim()?.toDoubleOrNull()?.let { return it }
        }
        return null
    }
}
