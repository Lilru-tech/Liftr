package com.lilru.liftr.ui.active

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.AppSnackbar
import com.lilru.liftr.workout.ActiveWorkoutCheckpointEntry
import com.lilru.liftr.workout.ActiveWorkoutCheckpointKind
import com.lilru.liftr.workout.ActiveWorkoutRecoveryFinish
import com.lilru.liftr.workout.ActiveWorkoutSessionCheckpoint
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch

@Composable
fun ActiveWorkoutRecoveryHost(
    supabase: SupabaseClient,
    isAuthenticated: Boolean
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var pendingEntry by remember { mutableStateOf<ActiveWorkoutCheckpointEntry?>(null) }
    var showDialog by remember { mutableStateOf(false) }
    var recoveryStrengthWorkoutId by remember { mutableStateOf<Int?>(null) }
    var recoveryGuestWorkoutId by remember { mutableStateOf<Int?>(null) }
    var recoveryGuest2WorkoutId by remember { mutableStateOf<Int?>(null) }
    var recoveryCardioWorkoutId by remember { mutableStateOf<Int?>(null) }
    var recoverySportWorkoutId by remember { mutableStateOf<Int?>(null) }
    var finishInFlight by remember { mutableStateOf(false) }

    LaunchedEffect(isAuthenticated, supabase) {
        if (!isAuthenticated) return@LaunchedEffect
        val entry = ActiveWorkoutSessionCheckpoint.findRecoverable(context, supabase) ?: return@LaunchedEffect
        pendingEntry = entry
        showDialog = true
    }

    val entry = pendingEntry
    if (showDialog && entry != null) {
        AlertDialog(
            onDismissRequest = {
                showDialog = false
                pendingEntry = null
            },
            title = { Text(stringResource(R.string.workout_recovery_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        stringResource(
                            R.string.workout_recovery_message,
                            entry.kindLabel(),
                            entry.summaryLine()
                        )
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDialog = false
                        when (entry.kind) {
                            ActiveWorkoutCheckpointKind.STRENGTH -> {
                                recoveryStrengthWorkoutId = entry.workoutId
                                recoveryGuestWorkoutId = entry.strength?.guestWorkoutId
                                recoveryGuest2WorkoutId = entry.strength?.guest2WorkoutId
                            }
                            ActiveWorkoutCheckpointKind.CARDIO -> {
                                recoveryCardioWorkoutId = entry.workoutId
                            }
                            ActiveWorkoutCheckpointKind.SPORT -> {
                                recoverySportWorkoutId = entry.workoutId
                            }
                        }
                        pendingEntry = null
                    }
                ) {
                    Text(stringResource(R.string.workout_recovery_resume))
                }
            },
            dismissButton = {
                Column(modifier = Modifier.fillMaxWidth()) {
                    TextButton(
                        onClick = {
                            if (finishInFlight) return@TextButton
                            finishInFlight = true
                            scope.launch {
                                val err = ActiveWorkoutRecoveryFinish.finishNow(context, supabase, entry)
                                finishInFlight = false
                                showDialog = false
                                pendingEntry = null
                                if (err != null) {
                                    AppSnackbar.showError(err)
                                } else {
                                    AppSnackbar.showSuccess(
                                        context.getString(R.string.workout_recovery_finish_success)
                                    )
                                }
                            }
                        }
                    ) {
                        Text(stringResource(R.string.workout_recovery_finish_now))
                    }
                    TextButton(
                        onClick = {
                            ActiveWorkoutSessionCheckpoint.clear(context)
                            showDialog = false
                            pendingEntry = null
                        }
                    ) {
                        Text(stringResource(R.string.workout_recovery_discard))
                    }
                }
            }
        )
    }

    recoveryStrengthWorkoutId?.let { wid ->
        ActiveStrengthWorkoutScreen(
            supabase = supabase,
            workoutId = wid,
            dualGuestWorkoutId = recoveryGuestWorkoutId,
            dualGuest2WorkoutId = recoveryGuest2WorkoutId,
            onClose = {
                recoveryStrengthWorkoutId = null
                recoveryGuestWorkoutId = null
                recoveryGuest2WorkoutId = null
            }
        )
    }
    recoveryCardioWorkoutId?.let { wid ->
        ActiveCardioWorkoutScreen(
            supabase = supabase,
            workoutId = wid,
            onClose = { recoveryCardioWorkoutId = null }
        )
    }
    recoverySportWorkoutId?.let { wid ->
        ActiveSportWorkoutScreen(
            supabase = supabase,
            workoutId = wid,
            onClose = { recoverySportWorkoutId = null }
        )
    }
}
