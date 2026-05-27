package com.lilru.liftr.ui.chat

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
internal data class RoutineShareStrengthSet(
    @SerialName("set_number") val setNumber: Int,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null,
    val notes: String? = null
)

@Serializable
internal data class RoutineShareStrengthEx(
    @SerialName("exercise_id") val exerciseId: Long,
    @SerialName("order_index") val orderIndex: Int,
    @SerialName("superset_group_id") val supersetGroupId: String? = null,
    @SerialName("superset_position") val supersetPosition: Int? = null,
    val notes: String? = null,
    @SerialName("custom_name") val customName: String? = null,
    @SerialName("strength_routine_sets") val strengthRoutineSets: List<RoutineShareStrengthSet>? = null
)

@Serializable
internal data class RoutineShareStrengthDetail(
    val id: Long,
    val name: String,
    @SerialName("strength_routine_exercises") val strengthRoutineExercises: List<RoutineShareStrengthEx>? = null
)

@Serializable
internal data class RoutineShareHyroxEx(
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
internal data class RoutineShareHyroxDetail(
    val id: Long,
    val name: String,
    @SerialName("hyrox_routine_exercises") val hyroxRoutineExercises: List<RoutineShareHyroxEx>? = null
)

private val detailJsonParser = Json { ignoreUnknownKeys = true }

internal fun decodeRoutineShareStrengthDetail(detailJson: String): RoutineShareStrengthDetail? =
    runCatching { detailJsonParser.decodeFromString(RoutineShareStrengthDetail.serializer(), detailJson) }.getOrNull()

internal fun decodeRoutineShareHyroxDetail(detailJson: String): RoutineShareHyroxDetail? =
    runCatching { detailJsonParser.decodeFromString(RoutineShareHyroxDetail.serializer(), detailJson) }.getOrNull()
