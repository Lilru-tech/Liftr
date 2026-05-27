package com.lilru.liftr.workout

import com.lilru.liftr.ui.active.ActiveStrengthExerciseLine
import java.util.Locale

data class StrengthFinishIncompleteCounts(
    val exercises: Int,
    val sets: Int
) {
    companion object {
        val zero = StrengthFinishIncompleteCounts(0, 0)

        fun aggregate(parts: List<StrengthFinishIncompleteCounts>): StrengthFinishIncompleteCounts {
            return StrengthFinishIncompleteCounts(
                exercises = parts.sumOf { it.exercises },
                sets = parts.sumOf { it.sets }
            )
        }
    }
}

object StrengthFinishIncompleteCounting {
    fun counts(
        exercises: List<ActiveStrengthExerciseLine>,
        completedIndexByExerciseId: Map<Int, Int>
    ): StrengthFinishIncompleteCounts {
        var incompleteSets = 0
        var incompleteExercises = 0
        for (ex in exercises) {
            val total = ex.sets.size
            if (total <= 0) continue
            val done = (completedIndexByExerciseId[ex.workoutExerciseId] ?: 0).coerceIn(0, total)
            val remaining = total - done
            incompleteSets += remaining
            if (done == 0) incompleteExercises += 1
        }
        return StrengthFinishIncompleteCounts(incompleteExercises, incompleteSets)
    }
}

object StrengthFinishConfirmationCopy {
    fun incompleteWarning(exercises: Int, sets: Int): String {
        val lang = Locale.getDefault().language
        return if (lang == "es") {
            "Tienes $exercises ejercicios y $sets series sin terminar. Si finalizas el entrenamiento ahora, se eliminarán automáticamente de tu historial."
        } else {
            "You have $exercises exercises and $sets sets left unfinished. If you finish now, they will be removed from your history automatically."
        }
    }

    fun standardEarlyFinishBody(): String {
        val lang = Locale.getDefault().language
        return if (lang == "es") {
            "No has completado todas las series planificadas. El entrenamiento se guardará solo con las series que hayas hecho. Si finalizas ahora, se publicará automáticamente."
        } else {
            "You haven't completed all planned sets. The workout will be saved with only the sets you actually performed. If you finish now, it will be published automatically."
        }
    }

    fun message(
        incomplete: StrengthFinishIncompleteCounts,
        standardBody: String
    ): String {
        val parts = mutableListOf<String>()
        if (incomplete.exercises > 0 && incomplete.sets > 0) {
            parts += incompleteWarning(incomplete.exercises, incomplete.sets)
        }
        parts += standardBody
        return parts.joinToString("\n\n")
    }
}
