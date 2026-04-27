package com.lilru.liftr.ui.home

import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lilru.liftr.R
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.delay

/**
 * Cuenta atrás 3-2-1 y texto *Start!* (~700 ms) antes de [onFinished] (paridad con iOS
 * `StartWorkoutCountdownView` en `Liftr/StartWorkoutCountdownView.swift`).
 *
 * Único sitio de composición: [WorkoutDetailScreen] (botón *Start* o flujo *planned* dual;
 * ver `android/ADD_WORKOUT_PARITY.md` → *Cuenta atrás*). Si
 * [com.lilru.liftr.prefs.LiftrPreferences.skipStartCountdown] es true, se salta esta pantalla.
 */
@Composable
fun StartWorkoutCountdownScreen(
    onFinished: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showStart by remember { mutableStateOf(false) }
    var current by remember { mutableStateOf(3) }
    val finished = remember { AtomicBoolean(false) }
    val view = LocalView.current
    fun end() {
        if (finished.compareAndSet(false, true)) onFinished()
    }

    LaunchedEffect(Unit) {
        for (c in listOf(3, 2, 1)) {
            if (finished.get()) return@LaunchedEffect
            current = c
            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            delay(1_000L)
        }
        if (finished.get()) return@LaunchedEffect
        showStart = true
        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        delay(700L)
        end()
    }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().align(Alignment.TopEnd),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = { end() }) { Text(stringResource(R.string.start_countdown_skip)) }
            }
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .align(Alignment.Center),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                AnimatedContent(
                    targetState = if (showStart) -1 else current,
                    transitionSpec = {
                        fadeIn(animationSpec = tween(150)) togetherWith
                            fadeOut(animationSpec = tween(90))
                    },
                    label = "countdown"
                ) { tick ->
                    Text(
                        text = if (tick == -1) {
                            stringResource(R.string.start_countdown_start)
                        } else {
                            tick.toString()
                        },
                        fontSize = 72.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
                Text(
                    text = if (showStart) {
                        stringResource(R.string.start_countdown_sub_go)
                    } else {
                        stringResource(R.string.start_countdown_get_ready)
                    },
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 24.dp)
                )
            }
        }
    }
}
