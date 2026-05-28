package com.lilru.liftr.nutrition

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

class NutritionMetabolismTest {

    @Test
    fun female28yo160cm57kg_metabolicTargetIs1523() {
        val birth = LocalDate.of(1998, 1, 1)
        val ref = LocalDate.of(2026, 5, 27)
        val result = NutritionMetabolism.computeMetabolicTargetKcal(
            sex = "female",
            dateOfBirth = birth,
            heightCm = 160.0,
            weightKg = 57.0,
            today = ref
        )
        assertEquals(1523, result)
    }

    @Test
    fun missingMetrics_femaleUsesImputedBiometrics() {
        val result = NutritionMetabolism.resolveDisplayKcal(
            sex = "female",
            dateOfBirth = null,
            heightCm = null,
            weightKg = null,
            storedTarget = null,
            isManual = false
        )
        assertEquals(1562, result)
    }

    @Test
    fun missingMetrics_maleUsesImputedBiometrics() {
        val result = NutritionMetabolism.resolveDisplayKcal(
            sex = "male",
            dateOfBirth = null,
            heightCm = null,
            weightKg = null,
            storedTarget = null,
            isManual = false
        )
        assertEquals(2039, result)
    }

    @Test
    fun unknownSex_usesUnisexOffset() {
        val bmr = NutritionMetabolism.computeBmrKcal(
            sex = "prefer_not_to_say",
            dateOfBirth = null,
            heightCm = 162.0,
            weightKg = 60.0
        )
        assertEquals(1302, bmr)
    }

    @Test
    fun workoutMultiplier_tierModerate() {
        assertEquals(1.375, NutritionMetabolism.workoutActivityMultiplier(2.0), 0.001)
    }

    @Test
    fun manualOverride_usesStoredNotComputed() {
        val result = NutritionMetabolism.resolveDisplayKcal(
            sex = "female",
            dateOfBirth = LocalDate.of(1998, 1, 1),
            heightCm = 160.0,
            weightKg = 57.0,
            storedTarget = 1800,
            isManual = true
        )
        assertEquals(1800, result)
    }
}
