package com.lilru.liftr.hyrox

import java.util.Locale

/**
 * Paridad con [Liftr/HyroxExerciseFormatting.swift] (etiqueta visible para códigos estándar, custom y notas).
 */
object HyroxExerciseFormatting {
    private const val CUSTOM = "custom"

    fun label(code: String, displayName: String?, notes: String? = null): String {
        val d = displayName?.trim().orEmpty()
        if (d.isNotEmpty()) return d
        val cLower = code.trim().lowercase()
        val isNonStandard = (cLower == CUSTOM) || (cLower !in KNOWN_STANDARD)
        val noteFirst = firstLine(notes)
        if (isNonStandard && !noteFirst.isNullOrEmpty()) return noteFirst
        return when (cLower) {
            "run" -> "Run"
            "skierg" -> "SkiErg"
            "burpee_broad_jump" -> "Burpee Broad Jump"
            "sled_push" -> "Sled Push"
            "sled_pull" -> "Sled Pull"
            "row" -> "Row"
            "farmer_carry" -> "Farmer Carry"
            "sandbag_lunges" -> "Sandbag Lunges"
            "wall_ball" -> "Wall Ball"
            "atlas_carry" -> "Atlas Carry"
            "box_jump_over" -> "Box Jump Over"
            "dead_ball_over_trunk" -> "Dead Ball Over Trunk"
            else -> cLower.replace('_', ' ').split(' ').joinToString(" ") { w ->
                w.replaceFirstChar { c ->
                    if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
                }
            }
        }
    }

    private fun firstLine(notes: String?): String? {
        val n = notes?.trim().orEmpty()
        if (n.isEmpty()) return null
        val first = n.lineSequence().first().trim()
        return first.ifEmpty { null }
    }

    private val KNOWN_STANDARD: Set<String> = setOf(
        "run", "skierg", "burpee_broad_jump", "sled_push", "sled_pull", "row",
        "farmer_carry", "sandbag_lunges", "wall_ball", "atlas_carry", "box_jump_over", "dead_ball_over_trunk"
    )

    data class HyroxPersistedPayload(val code: String, val displayName: String?)

    /**
     * Paridad con [HyroxExerciseFormatting.persistedPayload] (Swift) para el RPC
     * `create_sport_workout_v2` y para decidir el patch de `exercise_display_name` en
     * [hyrox_session_exercises] tras el insert.
     */
    fun persistedPayload(
        exerciseCode: String,
        customDisplayName: String,
        notes: String?
    ): HyroxPersistedPayload {
        val trimmed = customDisplayName.trim()
        val fromNotes = firstLine(notes)
        val c = exerciseCode.trim()
        if (c in KNOWN_STANDARD) {
            return HyroxPersistedPayload(c, null)
        }
        if (c == CUSTOM) {
            val name = when {
                trimmed.isNotEmpty() -> trimmed
                fromNotes != null -> fromNotes
                else -> null
            }
            return HyroxPersistedPayload(CUSTOM, name)
        }
        val name = when {
            trimmed.isNotEmpty() -> trimmed
            fromNotes != null -> fromNotes
            else -> null
        }
        return HyroxPersistedPayload(c, name)
    }
}
