package com.lilru.liftr.workout

import android.content.Context
import com.lilru.liftr.ui.active.ActiveStrengthExerciseLine
import com.lilru.liftr.ui.home.StrengthReadonlyDetail
import com.lilru.liftr.ui.home.StrengthReadonlyExerciseLine
import com.lilru.liftr.ui.home.StrengthReadonlySetLine
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class CachedWorkoutSet(
    val setNumber: Int,
    val reps: Int? = null,
    val weightKg: Double? = null,
    val rpe: Double? = null,
    val restSec: Int? = null
)

@Serializable
data class CachedWorkoutExercise(
    val workoutExerciseId: Int,
    val orderIndex: Int,
    val displayName: String,
    val notes: String? = null,
    val sets: List<CachedWorkoutSet> = emptyList()
)

@Serializable
data class WorkoutProgramCacheEntry(
    val workoutId: Int,
    val cachedAtEpochMs: Long,
    val exercises: List<CachedWorkoutExercise>
)

object WorkoutProgramCache {
    private const val PREFS = "liftr_workout_program_cache"
    private val json = Json { ignoreUnknownKeys = true }
    private val memory = mutableMapOf<Int, WorkoutProgramCacheEntry>()

    fun store(context: Context, detail: StrengthReadonlyDetail, workoutId: Int) {
        if (detail.exercises.isEmpty()) return
        val entry = WorkoutProgramCacheEntry(
            workoutId = workoutId,
            cachedAtEpochMs = System.currentTimeMillis(),
            exercises = detail.exercises.map { line ->
                CachedWorkoutExercise(
                    workoutExerciseId = line.id,
                    orderIndex = line.orderIndex,
                    displayName = line.title,
                    notes = line.notes,
                    sets = line.sets.map { s ->
                        CachedWorkoutSet(
                            setNumber = s.setNumber,
                            reps = s.reps,
                            weightKg = s.weightKg,
                            rpe = s.rpe,
                            restSec = s.restSec
                        )
                    }
                )
            }
        )
        memory[workoutId] = entry
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(key(workoutId), json.encodeToString(WorkoutProgramCacheEntry.serializer(), entry))
            .apply()
    }

    fun entry(context: Context, workoutId: Int): WorkoutProgramCacheEntry? {
        memory[workoutId]?.let { return it }
        val raw = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(key(workoutId), null)
            ?: return null
        return runCatching {
            json.decodeFromString(WorkoutProgramCacheEntry.serializer(), raw)
        }.onSuccess { memory[workoutId] = it }
            .getOrNull()
    }

    fun hasProgram(context: Context, workoutId: Int): Boolean {
        return entry(context, workoutId)?.exercises?.isNotEmpty() == true
    }

    fun storeFromActiveExercises(context: Context, workoutId: Int, lines: List<ActiveStrengthExerciseLine>) {
        if (lines.isEmpty()) return
        val entry = WorkoutProgramCacheEntry(
            workoutId = workoutId,
            cachedAtEpochMs = System.currentTimeMillis(),
            exercises = lines.map { line ->
                CachedWorkoutExercise(
                    workoutExerciseId = line.workoutExerciseId,
                    orderIndex = line.orderIndex,
                    displayName = line.displayName,
                    sets = line.sets.map { s ->
                        CachedWorkoutSet(
                            setNumber = s.setNumber,
                            reps = s.reps,
                            weightKg = s.weightKg,
                            rpe = s.rpe,
                            restSec = s.restSec
                        )
                    }
                )
            }
        )
        memory[workoutId] = entry
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(key(workoutId), json.encodeToString(WorkoutProgramCacheEntry.serializer(), entry))
            .apply()
    }

    private fun key(workoutId: Int) = "program.$workoutId"
}
