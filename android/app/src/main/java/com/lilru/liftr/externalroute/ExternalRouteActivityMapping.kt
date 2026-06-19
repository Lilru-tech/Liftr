package com.lilru.liftr.externalroute

import androidx.health.connect.client.records.ExerciseSessionRecord

object ExternalRouteActivityMapping {
    fun healthConnectExerciseType(activityCode: String): Int? = when (activityCode.lowercase()) {
        "run", "treadmill" -> ExerciseSessionRecord.EXERCISE_TYPE_RUNNING
        "walk" -> ExerciseSessionRecord.EXERCISE_TYPE_WALKING
        "hike" -> ExerciseSessionRecord.EXERCISE_TYPE_HIKING
        "bike", "e_bike", "mtb", "indoor_cycling" -> ExerciseSessionRecord.EXERCISE_TYPE_BIKING
        "swim_pool" -> ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL
        "swim_open_water" -> ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER
        "rowerg" -> ExerciseSessionRecord.EXERCISE_TYPE_ROWING_MACHINE
        else -> null
    }
}
