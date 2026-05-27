package com.lilru.liftr.nutrition

import com.lilru.liftr.data.BackendContracts
import java.time.LocalDate
import java.time.Period
import java.time.ZoneId
import kotlin.math.roundToInt

object NutritionMetabolism {

    fun computeBmrKcal(
        sex: String?,
        dateOfBirth: LocalDate?,
        heightCm: Double?,
        weightKg: Double?,
        today: LocalDate = LocalDate.now(ZoneId.systemDefault())
    ): Int? {
        if (dateOfBirth == null || heightCm == null || heightCm <= 0.0 || weightKg == null || weightKg <= 0.0) {
            return null
        }
        val normalized = sex?.trim()?.lowercase().orEmpty()
        val sexOffset = when (normalized) {
            "male", "m" -> BackendContracts.NutritionMetabolism.MALE_OFFSET
            "female", "f" -> BackendContracts.NutritionMetabolism.FEMALE_OFFSET
            else -> return null
        }
        val ageYears = Period.between(dateOfBirth, today).years
        val bmr = BackendContracts.NutritionMetabolism.WEIGHT_FACTOR * weightKg +
            BackendContracts.NutritionMetabolism.HEIGHT_FACTOR * heightCm -
            BackendContracts.NutritionMetabolism.AGE_FACTOR * ageYears +
            sexOffset
        return bmr.roundToInt().coerceIn(
            BackendContracts.NutritionMetabolism.MIN_KCAL,
            BackendContracts.NutritionMetabolism.MAX_KCAL
        )
    }

    fun resolveDisplayKcal(
        sex: String?,
        dateOfBirth: LocalDate?,
        heightCm: Double?,
        weightKg: Double?,
        storedTarget: Int?,
        isManual: Boolean
    ): Int {
        if (isManual) {
            val stored = storedTarget ?: BackendContracts.NutritionMetabolism.FALLBACK_KCAL
            return stored.coerceIn(
                BackendContracts.NutritionMetabolism.MIN_KCAL,
                BackendContracts.NutritionMetabolism.MAX_KCAL
            )
        }
        return computeBmrKcal(sex, dateOfBirth, heightCm, weightKg)
            ?: BackendContracts.NutritionMetabolism.FALLBACK_KCAL
    }
}
