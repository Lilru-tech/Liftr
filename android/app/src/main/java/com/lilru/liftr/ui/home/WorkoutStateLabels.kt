package com.lilru.liftr.ui.home

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.lilru.liftr.R

@Composable
fun workoutStateLabel(state: String?): String {
    val s = state?.trim() ?: return "-"
    return when (s.lowercase()) {
        "planned" -> stringResource(R.string.workout_state_planned)
        "published" -> stringResource(R.string.workout_state_published)
        "draft" -> stringResource(R.string.workout_state_draft)
        else -> s
    }
}

@Composable
fun workoutKindLabel(kind: String?): String {
    val k = kind?.trim() ?: return "-"
    return when (k.lowercase()) {
        "strength" -> stringResource(R.string.home_filter_strength)
        "cardio" -> stringResource(R.string.home_filter_cardio)
        "sport" -> stringResource(R.string.home_filter_sport)
        else -> k
    }
}
