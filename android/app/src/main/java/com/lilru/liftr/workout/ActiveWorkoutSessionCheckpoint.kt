package com.lilru.liftr.workout

import android.content.Context
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import java.time.Instant

@Serializable
enum class ActiveWorkoutCheckpointKind {
    @SerialName("strength") STRENGTH,
    @SerialName("cardio") CARDIO,
    @SerialName("sport") SPORT
}

@Serializable
data class PerformedSetSnapshot(
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null,
    val configId: Int,
    val segmentsInRow: Int = 1,
    val weightSegmentsJson: String? = null
)

@Serializable
data class SetRowSnapshot(
    val id: Int,
    @SerialName("workout_exercise_id") val workoutExerciseId: Int,
    @SerialName("set_number") val setNumber: Int,
    @SerialName("order_index") val orderIndex: Int? = null,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null,
    val weightSegmentsJson: String? = null
)

@Serializable
data class StrengthCheckpointPayload(
    val currentExerciseIndex: Int = 0,
    val currentSetIndex: Int = 0,
    val currentSetIndexByExercise: Map<Int, Int> = emptyMap(),
    val performedSetsByExercise: Map<Int, List<PerformedSetSnapshot>> = emptyMap(),
    val setsByExercise: Map<Int, List<SetRowSnapshot>> = emptyMap(),
    val restEndEpochByExercise: Map<Int, Long> = emptyMap(),
    val isResting: Boolean = false,
    val guestWorkoutId: Int? = null,
    val guest2WorkoutId: Int? = null,
    val guestPerformedSetsByExercise: Map<Int, List<PerformedSetSnapshot>> = emptyMap(),
    val guest2PerformedSetsByExercise: Map<Int, List<PerformedSetSnapshot>> = emptyMap(),
    val guestCurrentSetIndexByExercise: Map<Int, Int> = emptyMap(),
    val guest2CurrentSetIndexByExercise: Map<Int, Int> = emptyMap(),
    val showCountdown: Boolean = true
)

@Serializable
data class CardioCheckpointPayload(
    val elapsedSec: Int = 0,
    val isSessionRunning: Boolean = false,
    val distanceText: String = "",
    val routePoints: List<List<Double>> = emptyList(),
    val kmSplitCumulativeSec: List<Int> = emptyList(),
    val timerMode: String = "stopwatch",
    val remainingSec: Int = 0,
    val initialTargetSec: Int = 0,
    val gpsProfileRaw: String = "balanced",
    val showCountdown: Boolean = true
)

@Serializable
data class SportHyroxExerciseSnapshot(
    val id: Int,
    @SerialName("exercise_code") val exerciseCode: String,
    @SerialName("exercise_order") val exerciseOrder: Int,
    @SerialName("distance_m") val distanceM: Int? = null,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("height_cm") val heightCm: Int? = null,
    @SerialName("implement_count") val implementCount: Int? = null,
    @SerialName("calories_kcal") val caloriesKcal: Double? = null,
    val notes: String? = null,
    @SerialName("custom_display_name") val customDisplayName: String? = null
)

@Serializable
data class SportCheckpointPayload(
    val elapsedSec: Int = 0,
    val isSessionRunning: Boolean = false,
    val remainingSec: Int = 0,
    val initialTargetSec: Int = 0,
    val timerMode: String = "stopwatch",
    val showCountdown: Boolean = true,
    val hyroxExerciseIndex: Int = 0,
    val completedHyroxExerciseIds: List<Int> = emptyList(),
    val hyroxExercises: List<SportHyroxExerciseSnapshot> = emptyList(),
    val scoreForText: String = "",
    val scoreAgainstText: String = "",
    val matchResultRaw: String = "unfinished",
    val matchScoreText: String = "",
    val locationText: String = "",
    val sessionNotesText: String = "",
    val climbingSportStats: Map<String, String> = emptyMap(),
    val climbingRoutesJson: String = "[]"
)

@Serializable
data class ActiveWorkoutCheckpointEntry(
    val workoutId: Int,
    val kind: ActiveWorkoutCheckpointKind,
    val savedAtEpochMs: Long,
    val sessionStartedAtEpochMs: Long? = null,
    val accumulatedPausedSec: Int = 0,
    val isSessionPaused: Boolean = false,
    val pauseBeganAtEpochMs: Long? = null,
    val strength: StrengthCheckpointPayload? = null,
    val cardio: CardioCheckpointPayload? = null,
    val sport: SportCheckpointPayload? = null
) {
    fun summaryLine(): String {
        return when (kind) {
            ActiveWorkoutCheckpointKind.STRENGTH -> {
                val sets = strength?.performedSetsByExercise?.values?.sumOf { it.size } ?: 0
                "$sets sets completed"
            }
            ActiveWorkoutCheckpointKind.CARDIO -> {
                val min = (cardio?.elapsedSec ?: 0) / 60
                val dist = cardio?.distanceText?.trim().orEmpty()
                if (dist.isNotEmpty() && dist != "0") "$min min · $dist km" else "$min min elapsed"
            }
            ActiveWorkoutCheckpointKind.SPORT -> {
                val min = (sport?.elapsedSec ?: 0) / 60
                val hyrox = sport
                if (hyrox != null && hyrox.hyroxExercises.isNotEmpty()) {
                    "${min} min · ${hyrox.completedHyroxExerciseIds.size} stations done"
                } else {
                    "$min min elapsed"
                }
            }
        }
    }

    fun kindLabel(): String = when (kind) {
        ActiveWorkoutCheckpointKind.STRENGTH -> "strength"
        ActiveWorkoutCheckpointKind.CARDIO -> "cardio"
        ActiveWorkoutCheckpointKind.SPORT -> "sport"
    }
}

object ActiveWorkoutSessionCheckpoint {
    private const val PREFS = "liftr_active_workout_checkpoint"
    private const val KEY_ENTRY = "entry.v1"
    private val maxAgeMs = 7L * 24L * 60L * 60L * 1000L
    private val json = Json { ignoreUnknownKeys = true }

    fun load(context: Context): ActiveWorkoutCheckpointEntry? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ENTRY, null) ?: return null
        return runCatching { json.decodeFromString(ActiveWorkoutCheckpointEntry.serializer(), raw) }.getOrNull()
    }

    fun store(context: Context, entry: ActiveWorkoutCheckpointEntry) {
        val encoded = json.encodeToString(ActiveWorkoutCheckpointEntry.serializer(), entry)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ENTRY, encoded)
            .apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun clearIfWorkout(context: Context, workoutId: Int) {
        if (load(context)?.workoutId == workoutId) clear(context)
    }

    fun isStale(entry: ActiveWorkoutCheckpointEntry, nowMs: Long = System.currentTimeMillis()): Boolean {
        return nowMs - entry.savedAtEpochMs > maxAgeMs
    }

    @Serializable
    private data class WorkoutOngoingRow(
        val id: Int,
        @SerialName("user_id") val userId: String,
        @SerialName("ended_at") val endedAt: String? = null
    )

    suspend fun findRecoverable(
        context: Context,
        supabase: SupabaseClient
    ): ActiveWorkoutCheckpointEntry? {
        val entry = load(context) ?: return null
        if (isStale(entry)) {
            clear(context)
            return null
        }
        return runCatching {
            val row = supabase.from("workouts")
                .select(Columns.raw("id, user_id, ended_at")) {
                    filter { eq("id", entry.workoutId) }
                }
                .decodeSingle<WorkoutOngoingRow>()
            if (row.endedAt != null) {
                clear(context)
                return null
            }
            val uid = supabase.auth.currentUserOrNull()?.id?.toString()
            if (uid == null || row.userId != uid) {
                clear(context)
                return null
            }
            entry
        }.getOrElse { entry }
    }
}
