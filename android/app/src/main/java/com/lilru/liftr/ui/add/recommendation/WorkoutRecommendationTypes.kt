package com.lilru.liftr.ui.add.recommendation

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Paridad con RecommendationDataSource y StrengthSuggestionMode (WorkoutRecommendationModels.swift).
 */
enum class RecommendationDataSource {
    RECENT_HISTORY,
    FULL_CATALOG,
    HYROX,
    HYROX_RACE;

    val title: String
        get() = when (this) {
            RECENT_HISTORY -> "My last 10 workouts"
            FULL_CATALOG -> "Full app catalog"
            HYROX -> "Hyrox — mixed"
            HYROX_RACE -> "Hyrox — race format"
        }

    val detail: String
        get() = when (this) {
            RECENT_HISTORY ->
                "Only exercises or activities you have already logged in your recent training."
            FULL_CATALOG ->
                "Include any exercise or activity from the app, not only what you have used before."
            HYROX ->
                "Picks stations you've trained less in your recent Hyrox sessions and suggests typical distances, loads, and reps for each."
            HYROX_RACE ->
                "Like race day: easy run, then each official station in order, repeated. Run length, how many stations, and loads adapt to you."
        }
}

enum class StrengthSuggestionMode {
    PRIORITIZE_UNDERTRAINED_MUSCLES,
    PRIORITIZE_FREQUENT_LIFTS;

    val title: String
        get() = when (this) {
            PRIORITIZE_UNDERTRAINED_MUSCLES -> "Balance muscle groups"
            PRIORITIZE_FREQUENT_LIFTS -> "Frequent lifts"
        }

    val detail: String
        get() = when (this) {
            PRIORITIZE_UNDERTRAINED_MUSCLES ->
                "Favor muscles you trained less in those 10 sessions."
            PRIORITIZE_FREQUENT_LIFTS ->
                "Exercises you programmed most often in those sessions—loads from your latest sets and RPE."
        }
}

sealed class WorkoutRecommendationError(message: String) : Exception(message) {
    object NotSignedIn : WorkoutRecommendationError("You need to be signed in.")
    object NoWorkoutsInWindow :
        WorkoutRecommendationError(
            "No workouts of this type in your last 10 sessions. Log one first, or choose \"Full app catalog\" for a starter template."
        )

    class LoadFailed(msg: String) : WorkoutRecommendationError(msg)
}

data class StrengthRecommendationSetResult(
    val setNumber: Int,
    val reps: Int,
    val weightKg: Double,
    val rpe: Double?,
    val restSec: Int?
)

data class StrengthRecommendationExerciseResult(
    val exerciseId: Long,
    val displayName: String,
    val musclePrimary: String?,
    val sets: List<StrengthRecommendationSetResult>
)

data class CardioRecommendationResult(
    val activityWire: String,
    val durationSec: Int,
    val distanceKm: Double?,
    val elevationGainM: Int?,
    val avgHr: Int?,
    val maxHr: Int?,
    val inclinePercent: Double?,
    val cadenceRpm: Int?,
    val wattsAvg: Int?,
    val splitSecPer500m: Int?,
    val swimLaps: Int?,
    val poolLengthM: Int?,
    val swimStyle: String?,
    val rationale: String
)

@Serializable
data class HyroxExerciseRecommendationResult(
    @SerialName("exercise_code") val exerciseCode: String,
    @SerialName("custom_display_name") val customDisplayName: String = "",
    @SerialName("exercise_order") val exerciseOrder: Int,
    @SerialName("distance_m") val distanceM: Int? = null,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("height_cm") val heightCm: Int? = null,
    @SerialName("implement_count") val implementCount: Int? = null,
    val notes: String? = null
)

sealed class SportRecommendationResult {
    data class DurationOnly(val durationMin: Int, val rationale: String) : SportRecommendationResult()
    data class Hyrox(
        val durationMin: Int,
        val exercises: List<HyroxExerciseRecommendationResult>,
        val rationale: String
    ) : SportRecommendationResult()
}
