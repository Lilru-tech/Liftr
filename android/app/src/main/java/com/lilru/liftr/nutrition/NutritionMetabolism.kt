package com.lilru.liftr.nutrition

import com.lilru.liftr.data.BackendContracts
import java.time.LocalDate
import java.time.Period
import java.time.ZoneId
import kotlin.math.roundToInt

object NutritionMetabolism {

    fun sexOffset(sex: String?): Double {
        return when (sex?.trim()?.lowercase().orEmpty()) {
            "male", "m" -> BackendContracts.NutritionMetabolism.MALE_OFFSET
            "female", "f" -> BackendContracts.NutritionMetabolism.FEMALE_OFFSET
            else -> BackendContracts.NutritionMetabolism.UNISEX_OFFSET
        }
    }

    fun workoutActivityMultiplier(workoutsPerWeek: Double): Double {
        val wpw = workoutsPerWeek.coerceAtLeast(0.0)
        return when {
            wpw < 1.5 -> BackendContracts.NutritionMetabolism.MULTIPLIER_LOW
            wpw < 3.5 -> BackendContracts.NutritionMetabolism.MULTIPLIER_MODERATE
            wpw < 5.5 -> BackendContracts.NutritionMetabolism.MULTIPLIER_ACTIVE
            else -> BackendContracts.NutritionMetabolism.MULTIPLIER_VERY_ACTIVE
        }
    }

    fun imputedHeightCm(sex: String?, heightCm: Double?): Double {
        if (heightCm != null && heightCm > 0.0) return heightCm
        return when (sex?.trim()?.lowercase().orEmpty()) {
            "male", "m" -> BackendContracts.NutritionMetabolism.DEFAULT_HEIGHT_MALE_CM
            else -> BackendContracts.NutritionMetabolism.DEFAULT_HEIGHT_FEMALE_CM
        }
    }

    fun imputedWeightKg(sex: String?, weightKg: Double?): Double {
        if (weightKg != null && weightKg > 0.0) return weightKg
        return when (sex?.trim()?.lowercase().orEmpty()) {
            "male", "m" -> BackendContracts.NutritionMetabolism.DEFAULT_WEIGHT_MALE_KG
            else -> BackendContracts.NutritionMetabolism.DEFAULT_WEIGHT_FEMALE_KG
        }
    }

    fun demographicFallbackKcal(sex: String?): Int {
        return when (sex?.trim()?.lowercase().orEmpty()) {
            "female", "f" -> BackendContracts.NutritionMetabolism.FALLBACK_KCAL_FEMALE
            "male", "m" -> BackendContracts.NutritionMetabolism.FALLBACK_KCAL_MALE
            else -> BackendContracts.NutritionMetabolism.FALLBACK_KCAL_NEUTRAL
        }
    }

    fun computeBmrKcal(
        sex: String?,
        dateOfBirth: LocalDate?,
        heightCm: Double?,
        weightKg: Double?,
        today: LocalDate = LocalDate.now(ZoneId.systemDefault())
    ): Int {
        val height = imputedHeightCm(sex, heightCm)
        val weight = imputedWeightKg(sex, weightKg)
        val ageYears = if (dateOfBirth != null) {
            Period.between(dateOfBirth, today).years
        } else {
            BackendContracts.NutritionMetabolism.IMPUTED_AGE_YEARS
        }
        val bmr = BackendContracts.NutritionMetabolism.WEIGHT_FACTOR * weight +
            BackendContracts.NutritionMetabolism.HEIGHT_FACTOR * height -
            BackendContracts.NutritionMetabolism.AGE_FACTOR * ageYears +
            sexOffset(sex)
        return bmr.roundToInt().coerceIn(
            BackendContracts.NutritionMetabolism.MIN_KCAL,
            BackendContracts.NutritionMetabolism.MAX_KCAL
        )
    }

    fun computeMetabolicTargetKcal(
        sex: String?,
        dateOfBirth: LocalDate?,
        heightCm: Double?,
        weightKg: Double?,
        workoutsPerWeek: Double = 0.0,
        today: LocalDate = LocalDate.now(ZoneId.systemDefault())
    ): Int {
        val bmr = computeBmrKcal(sex, dateOfBirth, heightCm, weightKg, today)
        val tdee = bmr * workoutActivityMultiplier(workoutsPerWeek)
        return tdee.roundToInt().coerceIn(
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
        isManual: Boolean,
        workoutsPerWeek: Double = 0.0,
        today: LocalDate = LocalDate.now(ZoneId.systemDefault())
    ): Int {
        if (isManual) {
            val stored = storedTarget ?: demographicFallbackKcal(sex)
            return stored.coerceIn(
                BackendContracts.NutritionMetabolism.MIN_KCAL,
                BackendContracts.NutritionMetabolism.MAX_KCAL
            )
        }
        return computeMetabolicTargetKcal(
            sex,
            dateOfBirth,
            heightCm,
            weightKg,
            workoutsPerWeek,
            today
        )
    }
}
