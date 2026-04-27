package com.lilru.liftr.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.navigation.NotificationRouter
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private sealed class WorkoutFromNotifPhase {
    data object Loading : WorkoutFromNotifPhase()
    data class Error(val message: String) : WorkoutFromNotifPhase()
    data object Ready : WorkoutFromNotifPhase()
}

/**
 * Paridad con [WorkoutFromNotificationLoaderView] en iOS: resuelve fila de [workouts] antes del detalle
 * cuando [ownerId] no venía en el payload.
 */
@Composable
fun WorkoutDetailFromNotificationOverlay(
    supabase: SupabaseClient,
    workoutId: Int,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var phase by remember(workoutId) { mutableStateOf<WorkoutFromNotifPhase>(WorkoutFromNotifPhase.Loading) }
    LaunchedEffect(workoutId) {
        phase = WorkoutFromNotifPhase.Loading
        val oid = withContext(Dispatchers.IO) {
            NotificationRouter.resolveWorkoutOwnerId(supabase, workoutId)
        }
        phase = if (oid == null) {
            WorkoutFromNotifPhase.Error(
                "Workout $workoutId returned 0 rows (RLS or deleted)."
            )
        } else {
            WorkoutFromNotifPhase.Ready
        }
    }
    when (val p = phase) {
        is WorkoutFromNotifPhase.Loading -> {
            Box(
                modifier = modifier.fillMaxSize().padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    CircularProgressIndicator()
                    Text(
                        stringResource(R.string.workout_opening_loader),
                        style = MaterialTheme.typography.bodyLarge,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
        is WorkoutFromNotifPhase.Error -> {
            Column(
                modifier = modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    stringResource(R.string.workout_not_found_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    p.message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp)
                )
                LiftrBackTopBar(
                    onBack = onBack,
                    modifier = Modifier
                        .padding(top = 16.dp)
                        .fillMaxWidth()
                )
            }
        }
        WorkoutFromNotifPhase.Ready -> {
            WorkoutDetailScreen(
                supabase = supabase,
                workoutId = workoutId,
                onBack = onBack,
                modifier = modifier
            )
        }
    }
}
