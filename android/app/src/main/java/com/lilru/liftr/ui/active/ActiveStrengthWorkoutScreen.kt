package com.lilru.liftr.ui.active

import com.lilru.liftr.ui.add.StrengthRoutineOverwriteBottomSheet
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.matchParentSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.draw.scale
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.lilru.liftr.BuildConfig
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ongoing.OngoingWorkoutService
import com.lilru.liftr.ongoing.OngoingWorkoutWidgetPrefs
import com.lilru.liftr.ui.components.LiftrAvatar
import io.github.jan.supabase.SupabaseClient
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import java.util.Locale
import kotlinx.coroutines.delay

/** Sector de descanso con vértice en el centro (paridad con iOS `RestDarkClockWedge`). */
private fun DrawScope.drawRestClockWedgeFromCenter(totalSec: Int, restSec: Int, color: Color) {
    if (restSec <= 0) return
    val total = max(totalSec, max(restSec, 1))
    val elapsedFrac = (total - restSec).toFloat() / total.toFloat()
    val restFrac = restSec.toFloat() / total.toFloat()
    val path = Path()
    val cx = size.width / 2f
    val cy = size.height / 2f
    path.moveTo(cx, cy)
    val startDeg = -90f + 360f * elapsedFrac
    path.arcTo(
        rect = Rect(0f, 0f, size.width, size.height),
        startAngleDegrees = startDeg,
        sweepAngleDegrees = -360f * restFrac,
        forceMoveTo = false
    )
    path.close()
    drawPath(path, color)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActiveStrengthWorkoutScreen(
    supabase: SupabaseClient,
    workoutId: Int,
    dualGuestWorkoutId: Int? = null,
    dualGuest2WorkoutId: Int? = null,
    dualGuestAvatarUrl: String? = null,
    dualGuest2AvatarUrl: String? = null,
    dualHostAvatarUrl: String? = null,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: ActiveStrengthWorkoutViewModel = viewModel(
        key = "active-strength-$workoutId-g${dualGuestWorkoutId ?: 0}-g2${dualGuest2WorkoutId ?: 0}",
        factory = ActiveStrengthWorkoutViewModelFactory(
            supabase,
            workoutId,
            dualGuestWorkoutId,
            dualGuest2WorkoutId
        )
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val appCtx = ctx.applicationContext
    var isPremium by remember { mutableStateOf(LiftrPreferences.isPremium(appCtx)) }
    var showNavHint by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        showNavHint = !LiftrPreferences.activeStrengthNavHintSeen(appCtx)
        isPremium = LiftrPreferences.isPremium(appCtx)
    }
    val ongoingSubtitle = stringResource(R.string.active_strength_title)
    DisposableEffect(ongoingSubtitle, workoutId) {
        OngoingWorkoutService.start(ctx, ongoingSubtitle, trackLocation = false, workoutId = workoutId)
        onDispose { OngoingWorkoutService.stop(ctx) }
    }
    LaunchedEffect(
        workoutId,
        ui.exercises,
        ui.currentExerciseIndex,
        ui.currentSetIndex,
        ui.sessionElapsedSec,
        ui.isResting,
        ui.restSecondsLeft,
        ui.loading
    ) {
        if (ui.exercises.isNotEmpty() && !ui.loading) {
            val ex = ui.exercises.getOrNull(ui.currentExerciseIndex)
            val t = formatElapsed(ui.sessionElapsedSec)
            val exLine = ex?.let { e ->
                val clampedSetIndex = ui.currentSetIndex.coerceIn(0, e.sets.size)
                val tSets = e.sets.size.coerceAtLeast(1)
                val sNum = if (clampedSetIndex >= tSets) tSets else (clampedSetIndex + 1).coerceAtLeast(1)
                "${e.displayName} · $sNum/$tSets"
            } ?: "—"
            val rest = if (ui.isResting) " · rest ${ui.restSecondsLeft}s" else ""
            OngoingWorkoutWidgetPrefs.setActive(
                ctx.applicationContext,
                workoutId,
                ctx.getString(R.string.active_strength_title),
                exLine + " · $t$rest"
            )
        }
    }

    var guestSetProgress by remember { mutableStateOf<Map<Int, Int>>(emptyMap()) }
    var guestExercisesUi by remember { mutableStateOf<List<ActiveStrengthExerciseLine>>(emptyList()) }
    var guestCurrentExerciseIndex by rememberSaveable { mutableStateOf(0) }
    var guestNavEmphasisLockWeId by rememberSaveable { mutableStateOf<Int?>(null) }
    /** Fin de descanso (epoch ms) por workout_exercise_id del invitado; la burbuja sigue al día al cambiar de ejercicio. */
    var guestRestEndMsByExerciseId by remember { mutableStateOf(mapOf<Int, Long>()) }
    /** Duración total del descanso del invitado al iniciarlo (sector en avatar/burbuja). */
    var guestRestPlannedTotalSecByExerciseId by remember { mutableStateOf(mapOf<Int, Int>()) }
    var activeLane by rememberSaveable { mutableStateOf(0) } // 0 host, 1 guest
    var didAutoSwitchFromHostRest by remember { mutableStateOf(false) }
    LaunchedEffect(workoutId) {
        guestNavEmphasisLockWeId = null
        vm.resetSessionProgress()
    }
    LaunchedEffect(ui.guestExercises) {
        if (ui.guestExercises.isNotEmpty()) {
            guestExercisesUi = ui.guestExercises
            guestSetProgress = ui.guestExercises.associate { it.workoutExerciseId to 0 }
            guestCurrentExerciseIndex = guestCurrentExerciseIndex.coerceIn(0, ui.guestExercises.lastIndex)
        } else {
            activeLane = 0
            guestExercisesUi = emptyList()
            guestSetProgress = emptyMap()
            guestCurrentExerciseIndex = 0
            guestRestEndMsByExerciseId = emptyMap()
            guestRestPlannedTotalSecByExerciseId = emptyMap()
            guestNavEmphasisLockWeId = null
        }
    }
    LaunchedEffect(ui.isResting, ui.guestExercises.size) {
        if (ui.guestExercises.isEmpty()) return@LaunchedEffect
        if (ui.isResting && !didAutoSwitchFromHostRest) {
            activeLane = 1
            didAutoSwitchFromHostRest = true
        }
        if (!ui.isResting) {
            didAutoSwitchFromHostRest = false
        }
    }

    var showEditSheet by remember { mutableStateOf(false) }
    var guestEditRepsText by remember { mutableStateOf("") }
    var guestEditWeightText by remember { mutableStateOf("") }
    var guestEditRestText by remember { mutableStateOf("") }
    /** Pager del host: preview al deslizar sin cambiar el ejercicio de trabajo (VM). */
    var hostPagerDisplayIndex by rememberSaveable(workoutId) { mutableIntStateOf(0) }
    var lastSyncedHostWorkIndex by remember { mutableIntStateOf(-1) }
    var prevWorkoutIdForPager by remember { mutableIntStateOf(workoutId) }
    LaunchedEffect(workoutId, ui.currentExerciseIndex) {
        if (prevWorkoutIdForPager != workoutId) {
            prevWorkoutIdForPager = workoutId
            lastSyncedHostWorkIndex = -1
        }
        if (lastSyncedHostWorkIndex == -1) {
            lastSyncedHostWorkIndex = ui.currentExerciseIndex
            return@LaunchedEffect
        }
        if (ui.currentExerciseIndex != lastSyncedHostWorkIndex) {
            hostPagerDisplayIndex = ui.currentExerciseIndex
            lastSyncedHostWorkIndex = ui.currentExerciseIndex
        }
    }
    val laneExercises = if (activeLane == 1 && ui.guestExercises.isNotEmpty()) guestExercisesUi else ui.exercises
    val laneExerciseIndex = if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
        guestCurrentExerciseIndex.coerceIn(0, laneExercises.lastIndex.coerceAtLeast(0))
    } else {
        hostPagerDisplayIndex.coerceIn(0, laneExercises.lastIndex.coerceAtLeast(0))
    }
    val laneProgressMap = if (activeLane == 1 && ui.guestExercises.isNotEmpty()) guestSetProgress else ui.currentSetIndexByExerciseId
    val ex = laneExercises.getOrNull(laneExerciseIndex)
    val currentSetIndex = ex?.let { laneProgressMap[it.workoutExerciseId] ?: 0 } ?: 0
    val set = ex?.sets?.getOrNull(currentSetIndex)
    val guestRestSecByExerciseId = remember(ui.sessionElapsedSec, guestRestEndMsByExerciseId) {
        val n = System.currentTimeMillis()
        guestRestEndMsByExerciseId.mapValues { (_, endMs) ->
            max(0, ceil((endMs - n) / 1000.0).toInt())
        }.filterValues { it > 0 }
    }
    LaunchedEffect(ui.sessionElapsedSec) {
        val n = System.currentTimeMillis()
        if (guestRestEndMsByExerciseId.isNotEmpty()) {
            val pruned = guestRestEndMsByExerciseId.filterValues { it > n }
            if (pruned.size != guestRestEndMsByExerciseId.size) {
                guestRestEndMsByExerciseId = pruned
                val keep = pruned.keys
                guestRestPlannedTotalSecByExerciseId = guestRestPlannedTotalSecByExerciseId.filterKeys { it in keep }
            }
        }
    }
    val laneIsResting = if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
        ex?.workoutExerciseId?.let { (guestRestSecByExerciseId[it] ?: 0) > 0 } == true
    } else {
        ui.isResting
    }
    val laneRestSec = if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
        ex?.workoutExerciseId?.let { guestRestSecByExerciseId[it] } ?: 0
    } else {
        ui.restSecondsLeft
    }
    val isGuestLaneActive = activeLane == 1 && ui.guestExercises.isNotEmpty()
    val hostPagerPreviewWeId = ui.exercises.getOrNull(
        hostPagerDisplayIndex.coerceIn(0, ui.exercises.lastIndex.coerceAtLeast(0))
    )?.workoutExerciseId
    val hostBubbleEmphasisWeId = ui.navEmphasisLockWorkoutExerciseId ?: hostPagerPreviewWeId
    val guestPagerPreviewWeId = guestExercisesUi.getOrNull(
        guestCurrentExerciseIndex.coerceIn(0, guestExercisesUi.lastIndex.coerceAtLeast(0))
    )?.workoutExerciseId
    val guestBubbleEmphasisWeId = guestNavEmphasisLockWeId ?: guestPagerPreviewWeId
    val allSetsDoneCurrent = ex != null && currentSetIndex >= ex.sets.size
    val isLastExercise = laneExerciseIndex == laneExercises.lastIndex
    val allExercisesDone = laneExercises.isNotEmpty() && laneExercises.all { line ->
        (laneProgressMap[line.workoutExerciseId] ?: 0) >= line.sets.size
    }
    var waveIndex by remember { mutableStateOf(-1) }
    LaunchedEffect(allExercisesDone, ui.exercises.size) {
        if (!allExercisesDone) {
            waveIndex = -1
            return@LaunchedEffect
        }
        while (true) {
            for (i in ui.exercises.indices) {
                waveIndex = i
                delay(120L)
            }
            for (i in ui.exercises.indices.reversed()) {
                waveIndex = i
                delay(120L)
            }
        }
    }
    LaunchedEffect(isGuestLaneActive, laneExerciseIndex, currentSetIndex, set?.setId) {
        if (!isGuestLaneActive) return@LaunchedEffect
        guestEditRepsText = set?.reps?.toString() ?: ""
        guestEditWeightText = set?.weightKg?.let { v ->
            if (v == v.toInt().toDouble()) v.toInt().toString() else String.format(Locale.US, "%.1f", v)
        } ?: ""
        guestEditRestText = set?.restSec?.toString() ?: ""
    }
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFFBDF7FF))
    ) {
        when {
            ui.loading -> {
                Column(
                    Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) { CircularProgressIndicator() }
            }

            ui.error != null && ui.exercises.isEmpty() -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(text = ui.error ?: "", color = MaterialTheme.colorScheme.error)
                    Button(onClick = { vm.load() }, modifier = Modifier.padding(top = 8.dp)) {
                        Text(stringResource(R.string.home_retry))
                    }
                }
            }

            ui.exercises.isEmpty() -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(stringResource(R.string.active_strength_no_exercises))
                    Button(
                        onClick = onClose,
                        modifier = Modifier
                            .padding(top = 12.dp)
                            .fillMaxWidth()
                    ) { Text(stringResource(R.string.active_strength_back)) }
                }
            }

            else -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextButton(onClick = onClose, enabled = !ui.showElborblaCelebration) {
                            Text(stringResource(R.string.active_strength_back))
                        }
                        Card(colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.85f))) {
                            Text(
                                text = "⏱ ${formatElapsed(ui.sessionElapsedSec)}",
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                style = MaterialTheme.typography.labelLarge
                            )
                        }
                    }

                    if (showNavHint) {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp),
                            colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.55f))
                        ) {
                            Row(
                                modifier = Modifier.padding(10.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    stringResource(R.string.active_strength_nav_hint),
                                    style = MaterialTheme.typography.bodySmall,
                                    modifier = Modifier.weight(1f)
                                )
                                TextButton(
                                    onClick = {
                                        LiftrPreferences.setActiveStrengthNavHintSeen(appCtx, true)
                                        showNavHint = false
                                    }
                                ) { Text(stringResource(R.string.active_strength_nav_hint_ok)) }
                            }
                        }
                    }

                    if (ui.guestExercises.isNotEmpty()) {
                        val hostAvatarRestPulse = remember { Animatable(1f) }
                        var hostAvatarRestPrev by remember { mutableIntStateOf(0) }
                        LaunchedEffect(ui.restSecondsLeft) {
                            val was = hostAvatarRestPrev
                            hostAvatarRestPrev = ui.restSecondsLeft
                            if (was > 0 && ui.restSecondsLeft == 0) {
                                hostAvatarRestPulse.snapTo(1f)
                                hostAvatarRestPulse.animateTo(1.11f, spring(dampingRatio = 0.52f, stiffness = 420f))
                                hostAvatarRestPulse.animateTo(1f, spring(dampingRatio = 0.72f, stiffness = 320f))
                                hostAvatarRestPulse.animateTo(1.07f, spring(dampingRatio = 0.50f, stiffness = 440f))
                                hostAvatarRestPulse.animateTo(1f, spring(dampingRatio = 0.80f, stiffness = 280f))
                            }
                        }
                        val guestExIdForAvatar = guestExercisesUi.getOrNull(guestCurrentExerciseIndex)?.workoutExerciseId
                        val guestAvatarRestSec =
                            guestExIdForAvatar?.let { guestRestSecByExerciseId[it] } ?: 0
                        val guestAvatarRestPulse = remember { Animatable(1f) }
                        var guestAvatarRestPrev by remember { mutableIntStateOf(0) }
                        LaunchedEffect(guestAvatarRestSec) {
                            val was = guestAvatarRestPrev
                            guestAvatarRestPrev = guestAvatarRestSec
                            if (was > 0 && guestAvatarRestSec == 0) {
                                guestAvatarRestPulse.snapTo(1f)
                                guestAvatarRestPulse.animateTo(1.11f, spring(dampingRatio = 0.52f, stiffness = 420f))
                                guestAvatarRestPulse.animateTo(1f, spring(dampingRatio = 0.72f, stiffness = 320f))
                                guestAvatarRestPulse.animateTo(1.07f, spring(dampingRatio = 0.50f, stiffness = 440f))
                                guestAvatarRestPulse.animateTo(1f, spring(dampingRatio = 0.80f, stiffness = 280f))
                            }
                        }
                        Card(
                            modifier = Modifier
                                .padding(top = 8.dp)
                                .align(Alignment.CenterHorizontally),
                            colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.45f))
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                val hostDp = if (activeLane == 0) 42.dp else 34.dp
                                Box(
                                    modifier = Modifier
                                        .clickable { activeLane = 0 }
                                        .scale(hostAvatarRestPulse.value)
                                ) {
                                    Box(Modifier.size(hostDp)) {
                                        LiftrAvatar(
                                            imageUrl = dualHostAvatarUrl,
                                            displayName = "H",
                                            size = hostDp
                                        )
                                        if (ui.isResting && ui.restSecondsLeft > 0) {
                                            val hostWe = ui.exercises.getOrNull(ui.currentExerciseIndex)?.workoutExerciseId
                                            val plannedHost = hostWe?.let { ui.restPlannedTotalSecByExerciseId[it] }
                                                ?: ui.restSecondsLeft
                                            val totalPie = max(plannedHost, ui.restSecondsLeft).coerceAtLeast(1)
                                            Canvas(
                                                Modifier
                                                    .matchParentSize()
                                                    .clip(CircleShape)
                                            ) {
                                                drawRestClockWedgeFromCenter(
                                                    totalSec = totalPie,
                                                    restSec = ui.restSecondsLeft,
                                                    color = Color.Black.copy(alpha = 0.56f)
                                                )
                                            }
                                            Text(
                                                text = "${ui.restSecondsLeft}s",
                                                modifier = Modifier.align(Alignment.Center),
                                                color = Color.White,
                                                style = MaterialTheme.typography.labelSmall,
                                                fontWeight = FontWeight.Bold
                                            )
                                        }
                                    }
                                }
                                Spacer(Modifier.size(6.dp))
                                val guestDp = if (activeLane == 1) 42.dp else 34.dp
                                Box(
                                    modifier = Modifier
                                        .clickable { activeLane = 1 }
                                        .scale(guestAvatarRestPulse.value)
                                ) {
                                    Box(Modifier.size(guestDp)) {
                                        LiftrAvatar(
                                            imageUrl = dualGuestAvatarUrl,
                                            displayName = "G",
                                            size = guestDp
                                        )
                                        if (guestAvatarRestSec > 0) {
                                            val plannedGuest = guestExIdForAvatar?.let { guestRestPlannedTotalSecByExerciseId[it] }
                                                ?: guestAvatarRestSec
                                            val totalPieG = max(plannedGuest, guestAvatarRestSec).coerceAtLeast(1)
                                            Canvas(
                                                Modifier
                                                    .matchParentSize()
                                                    .clip(CircleShape)
                                            ) {
                                                drawRestClockWedgeFromCenter(
                                                    totalSec = totalPieG,
                                                    restSec = guestAvatarRestSec,
                                                    color = Color.Black.copy(alpha = 0.56f)
                                                )
                                            }
                                            Text(
                                                text = "${guestAvatarRestSec}s",
                                                modifier = Modifier.align(Alignment.Center),
                                                color = Color.White,
                                                style = MaterialTheme.typography.labelSmall,
                                                fontWeight = FontWeight.Bold
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 10.dp),
                        horizontalArrangement = Arrangement.Center
                    ) {
                        val isSolo = ui.guestExercises.isEmpty()
                        laneExercises.forEachIndexed { index, bubbleEx ->
                            val total = bubbleEx.sets.size.coerceAtLeast(1)
                            val done = (laneProgressMap[bubbleEx.workoutExerciseId] ?: 0).coerceIn(0, total)
                            val progress = done.toFloat() / total.toFloat()
                            val completed = done >= total
                            val bubbleEmphasisWeId =
                                if (isGuestLaneActive) guestBubbleEmphasisWeId else hostBubbleEmphasisWeId
                            val isEmphasized =
                                bubbleEmphasisWeId != null && bubbleEx.workoutExerciseId == bubbleEmphasisWeId
                            val bubbleRestSec =
                                if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                    guestRestSecByExerciseId[bubbleEx.workoutExerciseId] ?: 0
                                } else {
                                    ui.restSecondsLeftByExerciseId[bubbleEx.workoutExerciseId] ?: 0
                                }
                            val bubblePlannedTotal = bubbleEx.workoutExerciseId.let { wid ->
                                if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                    guestRestPlannedTotalSecByExerciseId[wid]
                                } else {
                                    ui.restPlannedTotalSecByExerciseId[wid]
                                }
                            }
                            val showRestOnBubble = bubbleRestSec > 0
                            val restPulse = remember(bubbleEx.workoutExerciseId) { Animatable(1f) }
                            var restSecPrev by remember(bubbleEx.workoutExerciseId) { mutableIntStateOf(0) }
                            LaunchedEffect(bubbleRestSec) {
                                val was = restSecPrev
                                restSecPrev = bubbleRestSec
                                if (was > 0 && bubbleRestSec == 0) {
                                    restPulse.snapTo(1f)
                                    restPulse.animateTo(1.11f, spring(dampingRatio = 0.52f, stiffness = 420f))
                                    restPulse.animateTo(1f, spring(dampingRatio = 0.72f, stiffness = 320f))
                                    restPulse.animateTo(1.07f, spring(dampingRatio = 0.50f, stiffness = 440f))
                                    restPulse.animateTo(1f, spring(dampingRatio = 0.80f, stiffness = 280f))
                                }
                            }
                            val bubbleScale by animateFloatAsState(
                                targetValue = when {
                                    allExercisesDone && waveIndex == index -> 1.22f
                                    completed -> 1.08f
                                    isEmphasized && isSolo -> 1.12f
                                    else -> 1f
                                },
                                animationSpec = tween(durationMillis = 220),
                                label = "bubbleScale$index"
                            )
                            Box(
                                modifier = Modifier
                                    .padding(horizontal = 4.dp)
                                    .size(34.dp)
                                    .scale(bubbleScale * restPulse.value)
                                    .background(
                                        color = when {
                                            allExercisesDone -> Color(0xFFFFD54F)
                                            completed -> Color(0xFF49A9FF)
                                            index == laneExercises.lastIndex -> Color(0xFF6CE78D)
                                            else -> Color.White.copy(alpha = 0.58f)
                                        },
                                        shape = CircleShape
                                    )
                                    .padding(if (isEmphasized) 0.dp else 2.dp)
                                    .background(
                                        color = if (isEmphasized) Color.White else Color.Transparent,
                                        shape = CircleShape
                                    )
                                    .padding(if (isEmphasized) 2.dp else 0.dp)
                                    .clickable {
                                        if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                            guestCurrentExerciseIndex = index
                                        } else {
                                            vm.goToExercise(index)
                                        }
                                    }
                            ) {
                                CircularProgressIndicator(
                                    progress = { progress },
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .padding(2.dp),
                                    color = Color(0xFF2A7CF7),
                                    trackColor = Color.Transparent,
                                    strokeWidth = 2.dp
                                )
                                if (!showRestOnBubble) {
                                    Text(
                                        text = "${index + 1}",
                                        modifier = Modifier.align(Alignment.Center),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = Color.Black
                                    )
                                }
                                if (showRestOnBubble) {
                                    val totalPie = max(bubblePlannedTotal ?: bubbleRestSec, bubbleRestSec).coerceAtLeast(1)
                                    Canvas(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .padding(2.dp)
                                    ) {
                                        drawRestClockWedgeFromCenter(
                                            totalSec = totalPie,
                                            restSec = bubbleRestSec,
                                            color = Color.Black.copy(alpha = 0.56f)
                                        )
                                    }
                                    Text(
                                        text = "${bubbleRestSec}s",
                                        modifier = Modifier.align(Alignment.Center),
                                        style = MaterialTheme.typography.labelMedium,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 11.sp,
                                        color = Color.White
                                    )
                                }
                            }
                        }
                    }

                    Box(
                        modifier = Modifier
                            .weight(1f, fill = true)
                            .padding(top = 14.dp)
                    ) {
                        val prevEx = laneExercises.getOrNull(laneExerciseIndex - 1)
                        val nextEx = laneExercises.getOrNull(laneExerciseIndex + 1)
                        if (prevEx != null) {
                            Card(
                                modifier = Modifier
                                    .align(Alignment.TopCenter)
                                    .fillMaxWidth()
                                    .padding(horizontal = 20.dp),
                                colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.24f))
                            ) {
                                Text(
                                    text = prevEx.displayName,
                                    modifier = Modifier.padding(12.dp),
                                    color = Color.Black.copy(alpha = 0.5f)
                                )
                            }
                        }
                        if (nextEx != null) {
                            Card(
                                modifier = Modifier
                                    .align(Alignment.BottomCenter)
                                    .fillMaxWidth()
                                    .padding(horizontal = 20.dp),
                                colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.24f))
                            ) {
                                Text(
                                    text = nextEx.displayName,
                                    modifier = Modifier.padding(12.dp),
                                    color = Color.Black.copy(alpha = 0.5f)
                                )
                            }
                        }

                        Card(
                            modifier = Modifier
                                .align(Alignment.Center)
                                .fillMaxWidth()
                                .padding(horizontal = 8.dp)
                                .pointerInput(laneExerciseIndex, currentSetIndex, activeLane, hostPagerDisplayIndex) {
                                    var totalDrag = 0f
                                    detectVerticalDragGestures(
                                        onVerticalDrag = { _, dragAmount -> totalDrag += dragAmount },
                                        onDragEnd = {
                                            if (abs(totalDrag) > 80f) {
                                                if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                                    if (totalDrag < 0f && guestCurrentExerciseIndex < laneExercises.lastIndex) guestCurrentExerciseIndex++
                                                    if (totalDrag > 0f && guestCurrentExerciseIndex > 0) guestCurrentExerciseIndex--
                                                } else {
                                                    if (totalDrag < 0f && hostPagerDisplayIndex < laneExercises.lastIndex) {
                                                        hostPagerDisplayIndex++
                                                    }
                                                    if (totalDrag > 0f && hostPagerDisplayIndex > 0) {
                                                        hostPagerDisplayIndex--
                                                    }
                                                }
                                            }
                                        }
                                    )
                                },
                            colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.52f))
                        ) {
                            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(
                                    text = ex?.displayName.orEmpty(),
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.Bold
                                )

                                Card(colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.72f))) {
                                    Column(
                                        Modifier
                                            .fillMaxWidth()
                                            .padding(14.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        if (!allSetsDoneCurrent && set != null) {
                                            Text(
                                                text = stringResource(
                                                    R.string.active_strength_set_progress,
                                                    currentSetIndex + 1,
                                                    ex?.sets?.size ?: 0
                                                ),
                                                style = MaterialTheme.typography.titleMedium
                                            )
                                            Text("${set.reps ?: 0} reps", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(top = 2.dp))
                                            Text(
                                                "${set.weightKg?.let { String.format("%.1f", it) } ?: "0.0"} kg",
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                modifier = Modifier.padding(top = 2.dp)
                                            )
                                            set.rpe?.let {
                                                Text(
                                                    "Target RPE ${String.format("%.1f", it)}",
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                        } else {
                                            Text(stringResource(R.string.active_strength_all_sets_done))
                                            Text("Great job! Move on when ready.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                }

                                if (!allSetsDoneCurrent) {
                                    OutlinedButton(
                                        onClick = { showEditSheet = true },
                                        enabled = set != null && !laneIsResting && !ui.finishing,
                                        modifier = Modifier.fillMaxWidth()
                                    ) { Text("Edit reps, weight & rest") }

                                    if (laneIsResting) {
                                        Button(
                                            onClick = {
                                                if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                                    ex?.workoutExerciseId?.let { wid ->
                                                        guestRestEndMsByExerciseId =
                                                            guestRestEndMsByExerciseId.filterKeys { it != wid }
                                                        guestRestPlannedTotalSecByExerciseId =
                                                            guestRestPlannedTotalSecByExerciseId.filterKeys { it != wid }
                                                    }
                                                } else {
                                                    vm.skipRest()
                                                }
                                            },
                                            modifier = Modifier.fillMaxWidth()
                                        ) { Text("Rest ${laneRestSec}s · Skip") }
                                    } else {
                                        Button(
                                            onClick = {
                                                if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                                    val exLocal = ex ?: return@Button
                                                    val doneLocal = (guestSetProgress[exLocal.workoutExerciseId] ?: 0).coerceAtMost(exLocal.sets.size)
                                                    val setLocal = exLocal.sets.getOrNull(doneLocal) ?: return@Button
                                                    if (guestNavEmphasisLockWeId == null) {
                                                        guestNavEmphasisLockWeId = exLocal.workoutExerciseId
                                                    }
                                                    guestSetProgress = guestSetProgress.toMutableMap().apply {
                                                        put(exLocal.workoutExerciseId, (doneLocal + 1).coerceAtMost(exLocal.sets.size))
                                                    }
                                                    val rest = setLocal.restSec?.takeIf { it > 0 } ?: 0
                                                    if (rest > 0) {
                                                        val endMs = System.currentTimeMillis() + rest * 1000L
                                                        guestRestEndMsByExerciseId =
                                                            guestRestEndMsByExerciseId.toMutableMap().apply {
                                                                put(exLocal.workoutExerciseId, endMs)
                                                            }
                                                        guestRestPlannedTotalSecByExerciseId =
                                                            guestRestPlannedTotalSecByExerciseId.toMutableMap().apply {
                                                                put(exLocal.workoutExerciseId, rest)
                                                            }
                                                        activeLane = 0
                                                    }
                                                } else {
                                                    vm.onSetDone()
                                                }
                                            },
                                            enabled = set != null && !ui.finishing,
                                            modifier = Modifier.fillMaxWidth()
                                        ) {
                                            val rest = set?.restSec?.takeIf { it > 0 }
                                            Text(if (rest != null) "Rest ${rest}s" else stringResource(R.string.active_strength_set_done))
                                        }
                                    }
                                }

                                OutlinedButton(
                                    onClick = {
                                        if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                            val exLocal = ex ?: return@OutlinedButton
                                            val nextEx = exLocal.copy(sets = appendOneSetToExpandedSets(exLocal.sets))
                                            val idx = laneExerciseIndex
                                            guestExercisesUi = guestExercisesUi.toMutableList().apply {
                                                if (idx in indices) this[idx] = nextEx
                                            }
                                        } else {
                                            vm.addSetToCurrentExercise()
                                        }
                                    },
                                    enabled = !ui.finishing && (!laneIsResting || allSetsDoneCurrent),
                                    modifier = Modifier.fillMaxWidth()
                                ) { Text("Add set") }

                                OutlinedButton(
                                    onClick = {
                                        if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                            val exLocal = ex ?: return@OutlinedButton
                                            if (exLocal.sets.size <= 1) return@OutlinedButton
                                            val nextSets = removeOneSetFromExpandedSets(exLocal.sets)
                                            val oldDone = guestSetProgress[exLocal.workoutExerciseId] ?: 0
                                            val nextDone = oldDone.coerceAtMost(nextSets.size)
                                            val nextEx = exLocal.copy(sets = nextSets)
                                            val idx = laneExerciseIndex
                                            guestExercisesUi = guestExercisesUi.toMutableList().apply {
                                                if (idx in indices) this[idx] = nextEx
                                            }
                                            guestSetProgress = guestSetProgress.toMutableMap().apply {
                                                put(exLocal.workoutExerciseId, nextDone)
                                            }
                                        } else {
                                            vm.removeSetFromCurrentExercise()
                                        }
                                    },
                                    enabled = !ui.finishing && !laneIsResting && ((ex?.sets?.size ?: 0) > 1),
                                    modifier = Modifier.fillMaxWidth()
                                ) { Text("Remove set", color = Color(0xFFD94343)) }

                                if (allSetsDoneCurrent && !isLastExercise) {
                                    Button(
                                        onClick = {
                                            if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                                if (guestCurrentExerciseIndex < laneExercises.lastIndex) {
                                                    guestNavEmphasisLockWeId = null
                                                    guestCurrentExerciseIndex++
                                                }
                                            } else {
                                                vm.goToNextExercise()
                                            }
                                        },
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        Text("Next exercise")
                                    }
                                }
                            }
                        }
                    }

                    if (isLastExercise) {
                        Button(
                            onClick = { vm.finishWorkout(onClose) },
                            enabled = !ui.finishing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp)
                        ) {
                            Text(if (ui.finishing) stringResource(R.string.active_strength_saving) else stringResource(R.string.active_strength_finish))
                        }
                    }
                    if (!isPremium) {
                        AndroidView(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(50.dp)
                                .padding(top = 8.dp),
                            factory = { adCtx ->
                                AdView(adCtx).apply {
                                    setAdSize(AdSize.BANNER)
                                    adUnitId = BuildConfig.AD_BANNER_UNIT_ID
                                    loadAd(AdRequest.Builder().build())
                                }
                            }
                        )
                    }
                }
            }
        }
        if (showEditSheet && set != null) {
            Card(
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(20.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Edit reps, weight & rest", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = if (isGuestLaneActive) guestEditRepsText else ui.editRepsText,
                        onValueChange = {
                            if (isGuestLaneActive) {
                                guestEditRepsText = it
                            } else {
                                vm.setEditRepsText(it)
                            }
                        },
                        label = { Text(stringResource(R.string.active_strength_field_reps)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                    )
                    OutlinedTextField(
                        value = if (isGuestLaneActive) guestEditWeightText else ui.editWeightText,
                        onValueChange = {
                            if (isGuestLaneActive) {
                                guestEditWeightText = it
                            } else {
                                vm.setEditWeightText(it)
                            }
                        },
                        label = { Text(stringResource(R.string.active_strength_field_weight_kg)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                    )
                    OutlinedTextField(
                        value = if (isGuestLaneActive) guestEditRestText else ui.editRestText,
                        onValueChange = {
                            if (isGuestLaneActive) {
                                guestEditRestText = it
                            } else {
                                vm.setEditRestText(it)
                            }
                        },
                        label = { Text("Rest (sec)") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(onClick = { showEditSheet = false }, modifier = Modifier.weight(1f)) {
                            Text("Cancel")
                        }
                        Button(
                            onClick = {
                                if (isGuestLaneActive) {
                                    val exLocal = guestExercisesUi.getOrNull(guestCurrentExerciseIndex)
                                        ?: return@Button
                                    val setIndex = (guestSetProgress[exLocal.workoutExerciseId] ?: 0)
                                    val reps = guestEditRepsText.trim().toIntOrNull()
                                    val weight = guestEditWeightText.trim().replace(',', '.').toDoubleOrNull()
                                    val rest = guestEditRestText.trim().toIntOrNull()?.coerceAtLeast(0)
                                    val nextSets = updateBlockForExpandedIndex(
                                        sets = exLocal.sets,
                                        expandedIndex = setIndex,
                                        reps = reps,
                                        weightKg = weight,
                                        rpe = exLocal.sets.getOrNull(setIndex)?.rpe,
                                        restSec = rest
                                    )
                                    val nextEx = exLocal.copy(sets = nextSets)
                                    guestExercisesUi = guestExercisesUi.toMutableList().apply {
                                        if (guestCurrentExerciseIndex in indices) {
                                            this[guestCurrentExerciseIndex] = nextEx
                                        }
                                    }
                                } else {
                                    vm.applyCurrentSetEdits()
                                }
                                showEditSheet = false
                            },
                            modifier = Modifier.weight(1f)
                        ) { Text("Save") }
                    }
                }
            }
        }
    }
    ui.strengthRoutineOverwritePrompt?.let { prompt ->
        StrengthRoutineOverwriteBottomSheet(
            prompt = prompt,
            onDismissRequest = { vm.dismissStrengthRoutineOverwrite() },
            onOverwriteTemplate = { vm.confirmStrengthRoutineOverwrite(true) },
            onNotNow = { vm.confirmStrengthRoutineOverwrite(false) }
        )
    }
    if (ui.showElborblaCelebration) {
        ElborblaFinishCelebrationOverlay(
            onContinue = { vm.dismissElborblaCelebration(onClose) }
        )
    }
}

@Composable
private fun ElborblaFinishCelebrationOverlay(
    onContinue: () -> Unit
) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.72f))
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            verticalArrangement = Arrangement.SpaceBetween,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                stringResource(R.string.elborbla_finish_title),
                style = MaterialTheme.typography.titleLarge,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "🎉",
                fontSize = 72.sp,
                modifier = Modifier.height(200.dp)
            )
            Spacer(Modifier.height(8.dp))
            Button(
                onClick = onContinue,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.elborbla_finish_continue))
            }
        }
    }
}

private fun formatElapsed(totalSec: Int): String {
    if (totalSec < 0) return "0:00"
    val m = totalSec / 60
    val s = totalSec % 60
    return String.format("%d:%02d", m, s)
}
