package com.lilru.liftr.ui.add

/** Row context for the shared exercise catalog sheet on [AddWorkoutTabScreen]. */
sealed class StrengthExercisePickTarget {
    data class WorkoutForm(val draftId: String) : StrengthExercisePickTarget()
    data class RoutineTemplate(val draftId: String) : StrengthExercisePickTarget()
}
