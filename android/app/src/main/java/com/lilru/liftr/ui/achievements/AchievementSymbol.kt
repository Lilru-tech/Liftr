package com.lilru.liftr.ui.achievements

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DownhillSkiing
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.Pool
import androidx.compose.material.icons.filled.Sports
import androidx.compose.material.icons.filled.SportsBasketball
import androidx.compose.material.icons.filled.SportsHandball
import androidx.compose.material.icons.filled.SportsHockey
import androidx.compose.material.icons.filled.SportsMartialArts
import androidx.compose.material.icons.filled.SportsRugby
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.filled.SportsVolleyball
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.TwoWheeler
import androidx.compose.ui.graphics.vector.ImageVector

/** Paridad con iOS [Liftr/AchievementsGridView.swift] `symbolForAchievement` (Material Icons). */
fun imageVectorForAchievement(code: String, category: String): ImageVector {
    val c = code.lowercase()
    val k = category.lowercase()
    return when {
        c.startsWith("max_weight_") || c.startsWith("est_1rm_") || c.startsWith("total_volume_") ||
            c.startsWith("total_reps_") || c.startsWith("strength_workouts_") || c.startsWith("strength_pr_") ||
            c.startsWith("strength_session_streak_") || c.startsWith("strength_") -> Icons.Filled.FitnessCenter
        c.startsWith("run_") || c.startsWith("pace_") -> Icons.Filled.DirectionsRun
        c.startsWith("bike_") || c.startsWith("ebike_") || c.startsWith("mtb_") ||
            c.startsWith("indoor_cycling_") || c.startsWith("treadmill_") -> Icons.Filled.TwoWheeler
        c.startsWith("rowerg_") || c.startsWith("swim_pool_") || c.startsWith("swim_ow_") -> Icons.Filled.Pool
        c.startsWith("walk_") -> Icons.Filled.DirectionsRun
        c.startsWith("hike_") -> Icons.Filled.DirectionsRun
        c.startsWith("hyrox_") -> Icons.Filled.SportsMartialArts
        c.startsWith("cardio_") || c.startsWith("duration_") || c.startsWith("elev_gain_") -> Icons.Filled.Bolt
        c.startsWith("padel_") || c.startsWith("tennis_") || c.startsWith("table_tennis_") ||
            c.startsWith("squash_") || c.startsWith("badminton_") || c.startsWith("racket_") -> Icons.Filled.SportsTennis
        c.startsWith("handball_") -> Icons.Filled.SportsHandball
        c.startsWith("hockey_") -> Icons.Filled.SportsHockey
        c.startsWith("rugby_") -> Icons.Filled.SportsRugby
        c.startsWith("ski_") -> Icons.Filled.DownhillSkiing
        c.startsWith("football_") -> Icons.Filled.SportsSoccer
        c.startsWith("basketball_") -> Icons.Filled.SportsBasketball
        c.startsWith("volleyball_") -> Icons.Filled.SportsVolleyball
        c.startsWith("sport_") -> Icons.Filled.MilitaryTech
        c.startsWith("likes_given_") || c.startsWith("likes_received_") || c.startsWith("followers_") ||
            c.startsWith("first_follow") || c.startsWith("first_comment") || c.startsWith("comments_") ||
            c.startsWith("follows_") -> Icons.Filled.Group
        c.startsWith("ranking_") -> Icons.Filled.EmojiEvents
        c.startsWith("challenge_") -> Icons.Filled.MilitaryTech
        c.startsWith("streak_") || c.startsWith("multi_streak_") -> Icons.Filled.Bolt
        c.startsWith("first_workout") || c.startsWith("workouts_") || c.startsWith("achievements_") ||
            c.startsWith("first_fail") || c.startsWith("night_workout") || c.startsWith("morning_workout") ||
            c.startsWith("double_session") || c.startsWith("zero_day") -> Icons.Filled.Star
        k == "strength" -> Icons.Filled.FitnessCenter
        k == "cardio" -> Icons.Filled.DirectionsRun
        k == "sport" -> Icons.Filled.Sports
        k == "streak" -> Icons.Filled.Bolt
        k == "ranking" -> Icons.Filled.EmojiEvents
        k == "social" -> Icons.Filled.Group
        else -> Icons.Filled.Star
    }
}

fun prettySubtypeFromCode(code: String, fallbackCategory: String): String {
    val c = code.lowercase()
    return when {
        c.startsWith("run_") || c.startsWith("pace_") -> "Running"
        c.startsWith("bike_") -> "Cycling"
        c.startsWith("ebike_") -> "E-Bike"
        c.startsWith("mtb_") -> "MTB"
        c.startsWith("indoor_cycling_") -> "Indoor Cycling"
        c.startsWith("rowerg_") -> "RowErg"
        c.startsWith("swim_pool_") -> "Pool Swim"
        c.startsWith("swim_ow_") -> "Open-Water Swim"
        c.startsWith("walk_") -> "Walking"
        c.startsWith("hike_") -> "Hiking"
        c.startsWith("treadmill_") -> "Treadmill"
        c.startsWith("hyrox_") -> "HYROX"
        c.startsWith("sport_") -> "Multi-sport"
        c.startsWith("padel_") -> "Padel"
        c.startsWith("tennis_") -> "Tennis"
        c.startsWith("table_tennis_") -> "Table Tennis"
        c.startsWith("squash_") -> "Squash"
        c.startsWith("football_") -> "Football"
        c.startsWith("basketball_") -> "Basketball"
        c.startsWith("volleyball_") -> "Volleyball"
        c.startsWith("badminton_") -> "Badminton"
        c.startsWith("handball_") -> "Handball"
        c.startsWith("hockey_") -> "Hockey"
        c.startsWith("rugby_") -> "Rugby"
        c.startsWith("racket_") -> "Racket"
        c.startsWith("ski_") -> "Ski"
        c.startsWith("challenge_") -> "Challenges"
        c.startsWith("strength_drop_") -> "Drop sets"
        else -> fallbackCategory.replaceFirstChar { it.titlecase() }
    }
}
