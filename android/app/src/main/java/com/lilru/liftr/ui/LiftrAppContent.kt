package com.lilru.liftr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.google.android.gms.tasks.Tasks
import com.google.firebase.messaging.FirebaseMessaging
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import com.lilru.liftr.navigation.NotificationRouter
import com.lilru.liftr.navigation.OpenWorkoutIntentStore
import com.lilru.liftr.push.FcmTokenUploader
import com.lilru.liftr.push.PushIntentStore
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.auth.AuthViewModel
import com.lilru.liftr.auth.AuthViewModelFactory
import com.lilru.liftr.auth.PasswordRecoveryGate
import com.lilru.liftr.data.PremiumStatusStore
import com.lilru.liftr.ui.auth.ResetPasswordScreen
import com.lilru.liftr.ui.main.MainShellScreen
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.SupabaseClient

@Composable
fun LiftrAppContent(
    supabase: SupabaseClient
) {
    val viewModel: AuthViewModel = viewModel(factory = AuthViewModelFactory(supabase))
    val status by viewModel.sessionStatus.collectAsStateWithLifecycle()
    val recoveryPending by PasswordRecoveryGate.pending.collectAsStateWithLifecycle()

    if (recoveryPending) {
        ResetPasswordScreen(viewModel = viewModel)
        return
    }

    when (val s = status) {
        is SessionStatus.Initializing -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    Text(
                        text = stringResource(R.string.auth_loading),
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
        is SessionStatus.Authenticated -> {
            LaunchedEffect(supabase) {
                withContext(Dispatchers.IO) {
                    runCatching { PremiumStatusStore.refresh(supabase) }
                    runCatching {
                        val t = Tasks.await(FirebaseMessaging.getInstance().token)
                        FcmTokenUploader.updateFcmToken(supabase, t)
                    }
                }
                val p = PushIntentStore.take()
                if (p != null) {
                    val me = supabase.auth.currentUserOrNull()?.id
                    var o = NotificationRouter.overlayFromFcmData(p, me)
                    if (o is MainOverlay.WorkoutDetail && o.ownerId == null) {
                        val oid = NotificationRouter.resolveWorkoutOwnerId(supabase, o.workoutId)
                        o = MainOverlay.WorkoutDetail(o.workoutId, oid)
                    }
                    o?.let { AppNavEvents.send(it) }
                }
                val w = OpenWorkoutIntentStore.takeWorkoutId()
                if (w != null) {
                    val oid = NotificationRouter.resolveWorkoutOwnerId(supabase, w)
                    AppNavEvents.send(MainOverlay.WorkoutDetail(w, oid))
                }
            }
            MainShellScreen(
                supabase = supabase,
                onSignOut = viewModel::signOut,
                isAuthenticated = true,
                authViewModel = viewModel
            )
        }
        is SessionStatus.NotAuthenticated,
        is SessionStatus.RefreshFailure -> {
            LaunchedEffect(Unit) {
                PremiumStatusStore.clear()
            }
            MainShellScreen(
                supabase = supabase,
                onSignOut = { },
                isAuthenticated = false,
                authViewModel = viewModel
            )
        }
    }
}
