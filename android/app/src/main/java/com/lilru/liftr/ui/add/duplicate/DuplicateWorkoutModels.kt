package com.lilru.liftr.ui.add.duplicate

import com.lilru.liftr.ui.add.AddCardioActivity
import com.lilru.liftr.ui.add.AddFootballPosition
import com.lilru.liftr.ui.add.AddMatchResult
import com.lilru.liftr.ui.add.AddRacketFormat
import com.lilru.liftr.ui.add.AddRacketMode
import com.lilru.liftr.ui.add.AddSportType
import com.lilru.liftr.ui.add.AddWorkoutIntensity
import com.lilru.liftr.ui.add.AddWorkoutKind
import com.lilru.liftr.ui.add.AddWorkoutState
import com.lilru.liftr.ui.add.StrengthExerciseDraft
import org.json.JSONObject

/**
 * iOS: [Liftr.WorkoutDetailView.buildDuplicateDraft] → carga y se aplica en Add.
 * Fija metadatos locales de la pestaña (rememberSaveable) y parte del VM.
 */
data class AddDuplicateFormPrefill(
    val title: String,
    val notes: String,
    val startedAtIso: String,
    val scheduleEndedEnabled: Boolean,
    val endedAtIso: String,
    val addState: AddWorkoutState,
    val intensity: AddWorkoutIntensity,
    val kind: AddWorkoutKind,
    val cardioActivity: AddCardioActivity,
    val cardioDistanceKm: String,
    val cardioDurH: String,
    val cardioDurM: String,
    val cardioDurS: String,
    val cardioDurationSecFallback: String,
    val didEditCardioDuration: Boolean,
    val didEditSportDuration: Boolean,
    val cardioAvgHr: String,
    val cardioMaxHr: String,
    val cardioAvgPaceSecPerKm: String,
    val cardioElevationGainM: String,
    val cardioStats: Map<String, String>,
    val sportType: AddSportType,
    val footballPosition: AddFootballPosition,
    val racketMode: AddRacketMode,
    val racketFormat: AddRacketFormat,
    val sportDurationMin: String,
    val sportScoreFor: String,
    val sportScoreAgainst: String,
    val sportMatchScoreText: String,
    val sportLocation: String,
    val sportSessionNotes: String,
    val sportMatchResult: AddMatchResult,
    val hyroxExercisesJson: String,
    val sportStats: Map<String, String>
)

/**
 * Mapas + Hyrox alineados a [mergeSportVw] para reenviar [p_stats] al editar metadatos
 * (paridad con iOS `buildSportStatsJSON` en el detalle).
 */
data class SportEditEnrichment(
    val sportStats: Map<String, String>,
    val hyroxExercisesJson: String,
    val footballPosition: AddFootballPosition,
    val racketMode: AddRacketMode,
    val racketFormat: AddRacketFormat
) {
    companion object {
        fun empty() = SportEditEnrichment(
            sportStats = emptyMap(),
            hyroxExercisesJson = "[]",
            footballPosition = AddFootballPosition.FORWARD,
            racketMode = AddRacketMode.SINGLES,
            racketFormat = AddRacketFormat.BEST_OF_3
        )
    }
}

data class DuplicateWorkoutPayload(
    val strengthExercises: List<StrengthExerciseDraft>,
    val selectedParticipantIds: Set<String>,
    val prefill: AddDuplicateFormPrefill
)

/**
 * Pasa un payload desde el detalle a la pestaña Add en un paso (la composición
 * aún no existe cuando hacemos [loadDuplicateForAdd]).
 */
object AddWorkoutDuplicateStore {
    @Volatile
    private var pending: DuplicateWorkoutPayload? = null

    @Synchronized
    fun set(payload: DuplicateWorkoutPayload) {
        pending = payload
    }

    @Synchronized
    fun take(): DuplicateWorkoutPayload? {
        val p = pending
        pending = null
        return p
    }

    @Synchronized
    fun peek(): DuplicateWorkoutPayload? = pending
}

/**
 * JSON para [sportStats] (clave [racket_stats_raw]).
 */
internal fun buildRacketStatsJson(full: JSONObject): String {
    val o = JSONObject()
    o.put("sets_won", full.optInt("rk_sets_won", 0))
    o.put("sets_lost", full.optInt("rk_sets_lost", 0))
    o.put("games_won", full.optInt("rk_games_won", 0))
    o.put("games_lost", full.optInt("rk_games_lost", 0))
    o.put("aces", full.optInt("rk_aces", 0))
    o.put("double_faults", full.optInt("rk_double_faults", 0))
    o.put("winners", full.optInt("rk_winners", 0))
    o.put("unforced_errors", full.optInt("rk_unforced_errors", 0))
    o.put("break_points_won", full.optInt("rk_break_points_won", 0))
    o.put("break_points_total", full.optInt("rk_break_points_total", 0))
    o.put("net_points_won", full.optInt("rk_net_points_won", 0))
    o.put("net_points_total", full.optInt("rk_net_points_total", 0))
    return o.toString()
}
