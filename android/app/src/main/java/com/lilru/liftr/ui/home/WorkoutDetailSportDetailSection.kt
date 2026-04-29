package com.lilru.liftr.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.hyrox.HyroxExerciseFormatting
import com.lilru.liftr.ui.add.AddSportType
import com.lilru.liftr.ui.active.normalizeSportMatchResult
import java.util.Locale

private fun humanizeUnderscore(s: String): String =
    s.replace('_', ' ').split(' ').joinToString(" ") { w ->
        w.replaceFirstChar { c ->
            if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
        }
    }

@Composable
private fun DetailStatRow(label: String, value: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(workoutDetailInsetFieldColor())
            .padding(10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun WorkoutDetailSportDetailSection(
    session: SportSessionDetail?,
    stats: WorkoutSportDetailStatsBundle,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(workoutDetailFieldPanelColor())
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            stringResource(R.string.workout_detail_sport_block_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        val r = session
        if (r == null) {
            Text(
                stringResource(R.string.home_detail_sport_no_session),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
        val spLower = r.sport.lowercase()
        DetailStatRow(
            stringResource(R.string.workout_detail_sport_kind_row),
            r.sport.replaceFirstChar { c ->
                if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
            }
        )
        r.durationSec?.takeIf { it > 0 }?.let { sec ->
            DetailStatRow(
                stringResource(R.string.workout_detail_label_duration),
                formatDurationFromSec(sec)
            )
        }
        if (spLower != AddSportType.SKI.wire && !r.matchResult.isNullOrBlank()) {
            val mr = normalizeSportMatchResult(r.matchResult)
            val label = when (mr.lowercase()) {
                "win" -> stringResource(R.string.match_result_win)
                "loss" -> stringResource(R.string.match_result_loss)
                "draw" -> stringResource(R.string.match_result_draw)
                "forfeit" -> stringResource(R.string.match_result_forfeit)
                "unfinished" -> stringResource(R.string.match_result_unfinished)
                else -> mr
            }
            DetailStatRow(stringResource(R.string.active_sport_match_result), label)
        }
        if (sportUsesNumericScore(spLower) && r.scoreFor != null && r.scoreAgainst != null) {
            DetailStatRow(
                stringResource(R.string.home_detail_sport_score).substringBefore(":").trim(),
                "${r.scoreFor} – ${r.scoreAgainst}"
            )
        }
        if (sportUsesSetText(spLower) && !r.matchScoreText.isNullOrBlank()) {
            DetailStatRow(stringResource(R.string.workout_detail_sport_sets_label), r.matchScoreText)
        }
        r.location?.takeIf { it.isNotBlank() }?.let {
            DetailStatRow(stringResource(R.string.active_sport_location), it)
        }
        r.notes?.takeIf { it.isNotBlank() }?.let {
            DetailStatRow(stringResource(R.string.active_sport_session_notes), it)
        }

        stats.football?.let { s ->
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(stringResource(R.string.workout_detail_football_stats), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            s.position?.takeIf { it.isNotBlank() }?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_position), humanizeUnderscore(it))
            }
            s.minutesPlayed?.let { DetailStatRow(stringResource(R.string.workout_detail_label_minutes_played), "$it") }
            s.goals?.let { DetailStatRow(stringResource(R.string.workout_detail_label_goals), "$it") }
            s.assists?.let { DetailStatRow(stringResource(R.string.workout_detail_label_assists), "$it") }
            s.shotsOnTarget?.let { DetailStatRow(stringResource(R.string.workout_detail_label_shots_on_target), "$it") }
            if (s.passesCompleted != null && s.passesAttempted != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_passes), "${s.passesCompleted}/${s.passesAttempted}")
            } else s.passesCompleted?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_passes_completed), "$it")
            }
            s.tackles?.let { DetailStatRow(stringResource(R.string.workout_detail_label_tackles), "$it") }
            s.interceptions?.let { DetailStatRow(stringResource(R.string.workout_detail_label_interceptions), "$it") }
            s.saves?.let { DetailStatRow(stringResource(R.string.workout_detail_label_saves), "$it") }
            s.yellowCards?.let { DetailStatRow(stringResource(R.string.workout_detail_label_yellow_cards), "$it") }
            s.redCards?.let { DetailStatRow(stringResource(R.string.workout_detail_label_red_cards), "$it") }
        }

        stats.handball?.let { s ->
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(stringResource(R.string.workout_detail_handball_stats), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            s.position?.takeIf { it.isNotBlank() }?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_position), humanizeUnderscore(it))
            }
            s.minutesPlayed?.let { DetailStatRow(stringResource(R.string.workout_detail_label_minutes_played), "$it") }
            s.goals?.let { DetailStatRow(stringResource(R.string.workout_detail_label_goals), "$it") }
            s.shots?.let { DetailStatRow(stringResource(R.string.workout_detail_label_shots), "$it") }
            s.shotsOnTarget?.let { DetailStatRow(stringResource(R.string.workout_detail_label_shots_on_target), "$it") }
            s.assists?.let { DetailStatRow(stringResource(R.string.workout_detail_label_assists), "$it") }
            s.steals?.let { DetailStatRow(stringResource(R.string.workout_detail_label_steals), "$it") }
            s.blocks?.let { DetailStatRow(stringResource(R.string.workout_detail_label_blocks), "$it") }
            s.turnoversLost?.let { DetailStatRow(stringResource(R.string.workout_detail_label_turnovers_lost), "$it") }
            if (s.sevenMGoals != null && s.sevenMAttempts != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_7m_goals), "${s.sevenMGoals}/${s.sevenMAttempts}")
            } else s.sevenMGoals?.let { DetailStatRow(stringResource(R.string.workout_detail_label_7m_goals), "$it") }
            s.saves?.let { DetailStatRow(stringResource(R.string.workout_detail_label_saves), "$it") }
            s.yellowCards?.let { DetailStatRow(stringResource(R.string.workout_detail_label_yellow_cards), "$it") }
            s.twoMinSuspensions?.let { DetailStatRow(stringResource(R.string.workout_detail_label_2min_suspensions), "$it") }
            s.redCards?.let { DetailStatRow(stringResource(R.string.workout_detail_label_red_cards), "$it") }
        }

        stats.hockey?.let { s ->
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(stringResource(R.string.workout_detail_hockey_stats), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            s.position?.takeIf { it.isNotBlank() }?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_position), humanizeUnderscore(it))
            }
            s.minutesPlayed?.let { DetailStatRow(stringResource(R.string.workout_detail_label_minutes_played), "$it") }
            s.goals?.let { DetailStatRow(stringResource(R.string.workout_detail_label_goals), "$it") }
            s.assists?.let { DetailStatRow(stringResource(R.string.workout_detail_label_assists), "$it") }
            s.shotsOnGoal?.let { DetailStatRow(stringResource(R.string.workout_detail_label_shots_on_goal), "$it") }
            s.plusMinus?.let { DetailStatRow(stringResource(R.string.workout_detail_label_plus_minus), "$it") }
            s.hits?.let { DetailStatRow(stringResource(R.string.workout_detail_label_hits), "$it") }
            s.blocks?.let { DetailStatRow(stringResource(R.string.workout_detail_label_blocks), "$it") }
            if (s.faceoffsWon != null && s.faceoffsTotal != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_faceoffs), "${s.faceoffsWon}/${s.faceoffsTotal}")
            }
            s.saves?.let { DetailStatRow(stringResource(R.string.workout_detail_label_saves), "$it") }
            s.penaltyMinutes?.let { DetailStatRow(stringResource(R.string.workout_detail_label_penalty_minutes), "$it") }
        }

        stats.rugby?.let { s ->
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(stringResource(R.string.workout_detail_rugby_stats), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            s.position?.takeIf { it.isNotBlank() }?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_position), humanizeUnderscore(it))
            }
            s.minutesPlayed?.let { DetailStatRow(stringResource(R.string.workout_detail_label_minutes_played), "$it") }
            s.tries?.let { DetailStatRow(stringResource(R.string.workout_detail_label_tries), "$it") }
            if (s.conversionsMade != null && s.conversionsAttempted != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_conversions), "${s.conversionsMade}/${s.conversionsAttempted}")
            } else s.conversionsMade?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_conversions_made), "$it")
            }
            if (s.penaltyGoalsMade != null && s.penaltyGoalsAttempted != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_penalty_goals), "${s.penaltyGoalsMade}/${s.penaltyGoalsAttempted}")
            } else s.penaltyGoalsMade?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_penalty_goals_made), "$it")
            }
            s.runs?.let { DetailStatRow(stringResource(R.string.workout_detail_label_runs), "$it") }
            s.metersGained?.let { DetailStatRow(stringResource(R.string.workout_detail_label_meters_gained), "$it") }
            s.offloads?.let { DetailStatRow(stringResource(R.string.workout_detail_label_offloads), "$it") }
            s.tacklesMade?.let { DetailStatRow(stringResource(R.string.workout_detail_label_tackles_made), "$it") }
            s.tacklesMissed?.let { DetailStatRow(stringResource(R.string.workout_detail_label_tackles_missed), "$it") }
            s.turnoversWon?.let { DetailStatRow(stringResource(R.string.workout_detail_label_turnovers_won), "$it") }
            s.yellowCards?.let { DetailStatRow(stringResource(R.string.workout_detail_label_yellow_cards), "$it") }
            s.redCards?.let { DetailStatRow(stringResource(R.string.workout_detail_label_red_cards), "$it") }
        }

        stats.basketball?.let { s ->
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(stringResource(R.string.workout_detail_basketball_stats), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            s.points?.let { DetailStatRow(stringResource(R.string.workout_detail_label_points), "$it") }
            s.rebounds?.let { DetailStatRow(stringResource(R.string.workout_detail_label_rebounds), "$it") }
            s.assists?.let { DetailStatRow(stringResource(R.string.workout_detail_label_assists), "$it") }
            s.steals?.let { DetailStatRow(stringResource(R.string.workout_detail_label_steals), "$it") }
            s.blocks?.let { DetailStatRow(stringResource(R.string.workout_detail_label_blocks), "$it") }
            if (s.fgMade != null && s.fgAttempted != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_fg), "${s.fgMade}/${s.fgAttempted}")
            }
            if (s.threeMade != null && s.threeAttempted != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_3pt), "${s.threeMade}/${s.threeAttempted}")
            }
            if (s.ftMade != null && s.ftAttempted != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_ft), "${s.ftMade}/${s.ftAttempted}")
            }
            s.turnovers?.let { DetailStatRow(stringResource(R.string.workout_detail_label_turnovers), "$it") }
            s.fouls?.let { DetailStatRow(stringResource(R.string.workout_detail_label_fouls), "$it") }
        }

        stats.racket?.let { s ->
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(stringResource(R.string.workout_detail_racket_stats), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            s.mode?.takeIf { it.isNotBlank() }?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_mode), humanizeUnderscore(it))
            }
            s.format?.takeIf { it.isNotBlank() }?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_format), humanizeUnderscore(it))
            }
            if (s.setsWon != null && s.setsLost != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_sets_wl), "${s.setsWon}–${s.setsLost}")
            }
            if (s.gamesWon != null && s.gamesLost != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_games_wl), "${s.gamesWon}–${s.gamesLost}")
            }
            s.aces?.let { DetailStatRow(stringResource(R.string.workout_detail_label_aces), "$it") }
            s.doubleFaults?.let { DetailStatRow(stringResource(R.string.workout_detail_label_double_faults), "$it") }
            s.winners?.let { DetailStatRow(stringResource(R.string.workout_detail_label_winners), "$it") }
            s.unforcedErrors?.let { DetailStatRow(stringResource(R.string.workout_detail_label_unforced_errors), "$it") }
            if (s.breakPointsWon != null && s.breakPointsTotal != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_break_points), "${s.breakPointsWon}/${s.breakPointsTotal}")
            }
            if (s.netPointsWon != null && s.netPointsTotal != null) {
                DetailStatRow(stringResource(R.string.workout_detail_label_net_points), "${s.netPointsWon}/${s.netPointsTotal}")
            }
        }

        stats.volleyball?.let { s ->
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(stringResource(R.string.workout_detail_volleyball_stats), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            s.points?.let { DetailStatRow(stringResource(R.string.workout_detail_label_points), "$it") }
            s.aces?.let { DetailStatRow(stringResource(R.string.workout_detail_label_aces), "$it") }
            s.blocks?.let { DetailStatRow(stringResource(R.string.workout_detail_label_blocks), "$it") }
            s.digs?.let { DetailStatRow(stringResource(R.string.workout_detail_label_digs), "$it") }
        }

        if (spLower == "hyrox") {
            stats.hyrox?.let { hy ->
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                Text(stringResource(R.string.workout_detail_hyrox_stats_title), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                hy.division?.takeIf { it.isNotBlank() }?.let { DetailStatRow(stringResource(R.string.workout_detail_hyrox_division), it) }
                hy.category?.takeIf { it.isNotBlank() }?.let { DetailStatRow(stringResource(R.string.workout_detail_hyrox_category), it) }
                hy.ageGroup?.takeIf { it.isNotBlank() }?.let { DetailStatRow(stringResource(R.string.workout_detail_hyrox_age_group), it) }
                hy.officialTimeSec?.let {
                    DetailStatRow(stringResource(R.string.workout_detail_hyrox_official_time), formatDurationFromSec(it))
                }
                hy.rankOverall?.let {
                    DetailStatRow(stringResource(R.string.workout_detail_hyrox_rank_overall), stringResource(R.string.workout_detail_rank_hash, it))
                }
                hy.rankCategory?.let {
                    DetailStatRow(stringResource(R.string.workout_detail_hyrox_rank_category), stringResource(R.string.workout_detail_rank_hash, it))
                }
                hy.noReps?.let { DetailStatRow(stringResource(R.string.workout_detail_hyrox_no_reps), "$it") }
                hy.penaltyTimeSec?.let {
                    DetailStatRow(stringResource(R.string.workout_detail_hyrox_penalty_time), formatDurationFromSec(it))
                }
                hy.avgHr?.let { DetailStatRow(stringResource(R.string.workout_detail_hyrox_avg_hr), stringResource(R.string.workout_detail_bpm_fmt, it)) }
                hy.maxHr?.let { DetailStatRow(stringResource(R.string.workout_detail_hyrox_max_hr), stringResource(R.string.workout_detail_bpm_fmt, it)) }
            }
            if (stats.hyroxExercises.isNotEmpty()) {
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                Text(stringResource(R.string.workout_detail_hyrox_exercises_title), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                stats.hyroxExercises.sortedBy { it.exerciseOrder }.forEach { ex ->
                    val exerciseTitle = HyroxExerciseFormatting.label(
                        ex.exerciseCode,
                        ex.exerciseDisplayName,
                        ex.notes
                    )
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(workoutDetailInsetFieldColor())
                            .padding(10.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text("${ex.exerciseOrder}. $exerciseTitle", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        ex.distanceM?.let { DetailStatRow(stringResource(R.string.workout_detail_stat_distance_m), stringResource(R.string.workout_detail_m_fmt, it)) }
                        ex.reps?.let { DetailStatRow(stringResource(R.string.workout_detail_stat_reps), "$it") }
                        ex.weightKg?.let {
                            DetailStatRow(stringResource(R.string.workout_detail_stat_weight), stringResource(R.string.workout_detail_kg_fmt, it))
                        }
                        ex.durationSec?.let {
                            DetailStatRow(stringResource(R.string.workout_detail_stat_duration), formatDurationFromSec(it))
                        }
                        ex.heightCm?.let { DetailStatRow(stringResource(R.string.workout_detail_stat_height), stringResource(R.string.workout_detail_cm_fmt, it)) }
                        ex.implementCount?.let { DetailStatRow(stringResource(R.string.workout_detail_stat_implements), "$it") }
                        ex.notes?.trim()?.takeIf { it.isNotEmpty() }?.let { n ->
                            if (n != exerciseTitle.trim()) {
                                DetailStatRow(stringResource(R.string.workout_detail_stat_notes), n)
                            }
                        }
                    }
                }
            }
        }

        stats.ski?.let { s ->
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(stringResource(R.string.workout_detail_ski_stats), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            s.totalDistanceKm?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_total_distance), stringResource(R.string.workout_detail_km_fmt, it))
            }
            s.runsCount?.let { DetailStatRow(stringResource(R.string.workout_detail_label_runs_count), "$it") }
            s.maxSpeedKmh?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_max_speed), stringResource(R.string.workout_detail_kmh_fmt, it))
            }
            s.avgSpeedKmh?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_avg_speed), stringResource(R.string.workout_detail_kmh_fmt, it))
            }
            s.verticalDropM?.let { DetailStatRow(stringResource(R.string.workout_detail_label_vertical_drop), stringResource(R.string.workout_detail_m_fmt, it)) }
            s.movingTimeSec?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_moving_time), formatDurationFromSec(it))
            }
            s.pausedTimeSec?.let {
                DetailStatRow(stringResource(R.string.workout_detail_label_paused_time), formatDurationFromSec(it))
            }
            s.resortName?.takeIf { it.isNotBlank() }?.let { DetailStatRow(stringResource(R.string.workout_detail_label_resort), it) }
            s.snowCondition?.takeIf { it.isNotBlank() }?.let { DetailStatRow(stringResource(R.string.workout_detail_label_snow), it) }
            s.weather?.takeIf { it.isNotBlank() }?.let { DetailStatRow(stringResource(R.string.workout_detail_label_weather), it) }
        }
        }
    }
}
