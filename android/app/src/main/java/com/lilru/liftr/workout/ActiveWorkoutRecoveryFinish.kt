package com.lilru.liftr.workout

import android.content.Context
import com.lilru.liftr.data.LiftrSupabase
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import com.lilru.liftr.ui.active.CompletedSetLine
import java.time.Instant

object ActiveWorkoutRecoveryFinish {
    suspend fun finishNow(
        context: Context,
        supabase: SupabaseClient,
        entry: ActiveWorkoutCheckpointEntry
    ): String? {
        return when (entry.kind) {
            ActiveWorkoutCheckpointKind.STRENGTH -> finishStrength(context, supabase, entry)
            ActiveWorkoutCheckpointKind.CARDIO -> finishCardio(context, supabase, entry)
            ActiveWorkoutCheckpointKind.SPORT -> finishSport(context, supabase, entry)
        }
    }

    @Serializable
    private data class WeRow(val id: Int, @SerialName("order_index") val orderIndex: Int)

    @Serializable
    private data class CardioIdRow(val id: Int)

    @Serializable
    private data class SportIdRow(val id: Int)

    @Serializable
    private data class WorkoutStateRow(val state: String? = null)

    private fun performedToCompletedLines(
        workoutExerciseId: Int,
        snaps: List<PerformedSetSnapshot>
    ): List<CompletedSetLine> {
        return snaps.map { s ->
            val segments: JsonArray? = s.weightSegmentsJson?.let { raw ->
                runCatching { Json.parseToJsonElement(raw) as JsonArray }.getOrNull()
            }
            CompletedSetLine(
                workoutExerciseId = workoutExerciseId,
                configId = s.configId,
                segmentsInRow = s.segmentsInRow,
                reps = s.reps,
                weightKg = s.weightKg,
                rpe = s.rpe,
                restSec = s.restSec,
                weightSegments = segments
            )
        }
    }

    private suspend fun finishStrength(
        context: Context,
        supabase: SupabaseClient,
        entry: ActiveWorkoutCheckpointEntry
    ): String? {
        val strength = entry.strength ?: return "Missing workout data"
        val rows = supabase.from("workout_exercises")
            .select(Columns.raw("id, order_index")) {
                filter { eq("workout_id", entry.workoutId) }
                order(column = "order_index", order = Order.ASCENDING)
            }
            .decodeList<WeRow>()
        val performedMap = strength.performedSetsByExercise.map { (weId, snaps) ->
            weId to performedToCompletedLines(weId, snaps)
        }.toMap()
        val hostExercises = StrengthWorkoutFinishCollapse.buildExercisePayloads(
            rows.sortedBy { it.orderIndex }.map { it.id },
            performedMap
        )
        var pausedSec = entry.accumulatedPausedSec
        if (entry.isSessionPaused && entry.pauseBeganAtEpochMs != null) {
            pausedSec += ((System.currentTimeMillis() - entry.pauseBeganAtEpochMs).coerceAtLeast(0L) / 1000L)
                .toInt()
        }
        val endedAtIso = Instant.now().toString()
        val res = runCatching {
            StrengthWorkoutSaveRpc.finishStrengthWorkoutV1(
                supabase = supabase,
                workoutId = entry.workoutId,
                endedAtIso = endedAtIso,
                pausedSec = pausedSec.coerceAtLeast(0),
                hostExercises = hostExercises
            )
        }
        if (res.isFailure) {
            val e = res.exceptionOrNull()!!
            if (WorkoutFinishSync.isRetriable(e)) {
                LiftrSupabase.appContext?.let { ctx ->
                    WorkoutFinishSync.enqueue(
                        ctx,
                        entry.workoutId,
                        endedAtIso,
                        pausedSec.coerceAtLeast(0),
                        hostExercises
                    )
                }
                ActiveWorkoutSessionCheckpoint.clear(context)
                return null
            }
            return e.message?.take(280) ?: e::class.java.simpleName
        }
        ActiveWorkoutSessionCheckpoint.clear(context)
        return null
    }

    private suspend fun finishCardio(
        context: Context,
        supabase: SupabaseClient,
        entry: ActiveWorkoutCheckpointEntry
    ): String? {
        val cardio = entry.cardio ?: return "Missing workout data"
        val err = runCatching {
            val cardioRow = supabase.from("cardio_sessions")
                .select(Columns.raw("id")) {
                    filter { eq("workout_id", entry.workoutId) }
                }
                .decodeSingle<CardioIdRow>()
            val distKm = cardio.distanceText.replace(',', '.').toDoubleOrNull() ?: 0.0
            val routeGeo = if (cardio.routePoints.size >= 2) {
                val coords = cardio.routePoints.joinToString(",") { "[${it[1]},${it[0]}]" }
                """{"type":"LineString","coordinates":[$coords]}"""
            } else null
            @Serializable
            data class CardioPatch(
                @SerialName("duration_sec") val durationSec: Int,
                @SerialName("distance_km") val distanceKm: Double? = null,
                @SerialName("route_geojson") val routeGeojson: String? = null
            )
            supabase.from("cardio_sessions").update(
                CardioPatch(
                    durationSec = cardio.elapsedSec,
                    distanceKm = distKm.takeIf { it > 0 },
                    routeGeojson = routeGeo
                )
            ) {
                filter { eq("id", cardioRow.id) }
            }
            val stateRow = runCatching {
                supabase.from("workouts")
                    .select(Columns.raw("state")) { filter { eq("id", entry.workoutId) } }
                    .decodeSingle<WorkoutStateRow>()
            }.getOrNull()
            @Serializable
            data class WorkoutFinish(
                @SerialName("ended_at") val endedAt: String,
                val state: String? = null
            )
            supabase.from("workouts").update(
                WorkoutFinish(
                    endedAt = Instant.now().toString(),
                    state = stateRow?.state?.takeIf { it == "planned" }?.let { "published" }
                )
            ) {
                filter { eq("id", entry.workoutId) }
            }
        }.exceptionOrNull()?.message?.take(280)
        if (err != null) return err
        ActiveWorkoutSessionCheckpoint.clear(context)
        return null
    }

    private suspend fun finishSport(
        context: Context,
        supabase: SupabaseClient,
        entry: ActiveWorkoutCheckpointEntry
    ): String? {
        val sport = entry.sport ?: return "Missing workout data"
        val err = runCatching {
            val sportRow = supabase.from("sport_sessions")
                .select(Columns.raw("id")) {
                    filter { eq("workout_id", entry.workoutId) }
                }
                .decodeSingle<SportIdRow>()
            @Serializable
            data class SportPatch(
                @SerialName("duration_sec") val durationSec: Int,
                @SerialName("score_for") val scoreFor: Int? = null,
                @SerialName("score_against") val scoreAgainst: Int? = null,
                @SerialName("match_result") val matchResult: String? = null,
                @SerialName("match_score_text") val matchScoreText: String? = null,
                val location: String? = null,
                val notes: String? = null
            )
            supabase.from("sport_sessions").update(
                SportPatch(
                    durationSec = sport.elapsedSec,
                    scoreFor = sport.scoreForText.trim().toIntOrNull(),
                    scoreAgainst = sport.scoreAgainstText.trim().toIntOrNull(),
                    matchResult = sport.matchResultRaw.trim().takeIf { it.isNotEmpty() },
                    matchScoreText = sport.matchScoreText.trim().takeIf { it.isNotEmpty() },
                    location = sport.locationText.trim().takeIf { it.isNotEmpty() },
                    notes = sport.sessionNotesText.trim().takeIf { it.isNotEmpty() }
                )
            ) {
                filter { eq("id", sportRow.id) }
            }
            val stateRow = runCatching {
                supabase.from("workouts")
                    .select(Columns.raw("state")) { filter { eq("id", entry.workoutId) } }
                    .decodeSingle<WorkoutStateRow>()
            }.getOrNull()
            @Serializable
            data class WorkoutFinish(
                @SerialName("ended_at") val endedAt: String,
                val state: String? = null
            )
            supabase.from("workouts").update(
                WorkoutFinish(
                    endedAt = Instant.now().toString(),
                    state = stateRow?.state?.takeIf { it == "planned" }?.let { "published" }
                )
            ) {
                filter { eq("id", entry.workoutId) }
            }
        }.exceptionOrNull()?.message?.take(280)
        if (err != null) return err
        ActiveWorkoutSessionCheckpoint.clear(context)
        return null
    }
}
