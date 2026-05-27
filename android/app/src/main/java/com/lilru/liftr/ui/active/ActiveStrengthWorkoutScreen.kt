package com.lilru.liftr.ui.active

import com.lilru.liftr.ui.add.StrengthRoutineOverwriteBottomSheet
import com.lilru.liftr.workout.StrengthFinishConfirmationCopy
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.ui.add.ExercisePickerSortMode
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.lilru.liftr.BuildConfig
import com.lilru.liftr.R
import com.lilru.liftr.ui.AppSnackbar
import com.lilru.liftr.data.PremiumStatusStore
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.workout.WorkoutStartSync
import com.lilru.liftr.ongoing.OngoingWorkoutService
import com.lilru.liftr.ongoing.OngoingWorkoutWidgetPrefs
import com.lilru.liftr.ui.add.StrengthSegmentPayload
import com.lilru.liftr.ui.chat.MessagesFloatingButton
import com.lilru.liftr.ui.components.LiftrAvatar
import io.github.jan.supabase.SupabaseClient
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

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
    val isPremium by PremiumStatusStore.isPremium.collectAsStateWithLifecycle()
    var showNavHint by remember { mutableStateOf(true) }
    var showFinishConfirm by remember { mutableStateOf(false) }
    val finishConfirmMessage = remember(
        ui.exercises,
        ui.currentSetIndexByExerciseId,
        ui.guestExercises,
        ui.guest2Exercises,
        ui.completedEntirely
    ) {
        StrengthFinishConfirmationCopy.message(
            incomplete = vm.strengthFinishIncompleteCounts(),
            standardBody = ctx.getString(R.string.active_strength_finish_standard_body)
        )
    }
    val runFinishWorkout: () -> Unit = {
        vm.finishWorkout { offlineQueued ->
            if (offlineQueued) {
                AppSnackbar.showSuccess(
                    ctx.getString(R.string.active_workout_finish_saved_offline)
                )
            }
            onClose()
        }
    }
    val requestFinishWorkout: () -> Unit = {
        val incomplete = vm.strengthFinishIncompleteCounts()
        if (incomplete.exercises > 0 && incomplete.sets > 0) {
            showFinishConfirm = true
        } else {
            runFinishWorkout()
        }
    }
    LaunchedEffect(Unit) {
        showNavHint = !LiftrPreferences.activeStrengthNavHintSeen(appCtx)
        vm.updateStartSyncStatus(WorkoutStartSync.status(workoutId))
    }
    val syncListener: (Int, WorkoutStartSync.Status) -> Unit = remember(workoutId) {
        { wid, status ->
            if (wid == workoutId) vm.updateStartSyncStatus(status)
        }
    }
    DisposableEffect(workoutId, syncListener) {
        WorkoutStartSync.addListener(syncListener)
        onDispose { WorkoutStartSync.removeListener(syncListener) }
    }
    val ongoingSubtitle = stringResource(R.string.active_strength_title)
    DisposableEffect(ongoingSubtitle, workoutId) {
        OngoingWorkoutService.start(ctx, ongoingSubtitle, trackLocation = false, workoutId = workoutId)
        onDispose { OngoingWorkoutService.stop(ctx) }
    }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                vm.onScreenResumed()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    val connectionUnstableMsg = stringResource(R.string.active_strength_connection_unstable)
    LaunchedEffect(ui.toastMessage) {
        val msg = ui.toastMessage ?: return@LaunchedEffect
        AppSnackbar.showInfo(msg)
        vm.clearToast()
    }
    LaunchedEffect(
        workoutId,
        ui.exercises,
        ui.currentExerciseIndex,
        ui.currentSetIndex,
        ui.sessionElapsedSec,
        ui.isSessionPaused,
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
    var applyEditToRemainingSets by remember { mutableStateOf(false) }
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
            hostPagerDisplayIndex = pagerAnchorExerciseIndex(ui.currentExerciseIndex, ui.exercises)
            lastSyncedHostWorkIndex = ui.currentExerciseIndex
        }
    }
    val laneExercises = if (activeLane == 1 && ui.guestExercises.isNotEmpty()) guestExercisesUi else ui.exercises
    val laneExerciseIndex = if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
        guestCurrentExerciseIndex.coerceIn(0, laneExercises.lastIndex.coerceAtLeast(0))
    } else {
        hostPagerDisplayIndex.coerceIn(0, laneExercises.lastIndex.coerceAtLeast(0))
    }
    val isGuestLaneActive = activeLane == 1 && ui.guestExercises.isNotEmpty()
    val laneDisplayGroups = strengthDisplayGroups(laneExercises)
    val laneGroupIndex = displayGroupIndexForExerciseIndex(laneExerciseIndex, laneExercises) ?: 0
    val currentDisplayGroup = laneDisplayGroups.getOrNull(laneGroupIndex)
    val isSupersetCard = currentDisplayGroup?.isSuperset == true && !isGuestLaneActive
    val laneProgressMap = if (activeLane == 1 && ui.guestExercises.isNotEmpty()) guestSetProgress else ui.currentSetIndexByExerciseId
    val workExerciseIndex = if (isGuestLaneActive) {
        guestCurrentExerciseIndex.coerceIn(0, laneExercises.lastIndex.coerceAtLeast(0))
    } else {
        ui.currentExerciseIndex.coerceIn(0, laneExercises.lastIndex.coerceAtLeast(0))
    }
    val ex = laneExercises.getOrNull(
        if (isSupersetCard) workExerciseIndex else laneExerciseIndex
    )
    val currentSetIndex = ex?.let { laneProgressMap[it.workoutExerciseId] ?: 0 } ?: 0
    val set = ex?.sets?.getOrNull(currentSetIndex)
    var editingExpandedIndex by remember { mutableStateOf<Int?>(null) }
    var editingWorkoutExerciseId by remember { mutableStateOf<Int?>(null) }
    var editDraftsByWorkoutExerciseId by remember { mutableStateOf<Map<Int, SetEditDraft>>(emptyMap()) }

    fun populateEditFieldsFromSet(visitedSet: ActiveStrengthSetLine) {
        vm.setEditRepsText(visitedSet.reps?.toString() ?: "")
        vm.setEditWeightText(
            visitedSet.weightKg?.let { v ->
                if (v == v.toInt().toDouble()) v.toInt().toString()
                else String.format(Locale.US, "%.1f", v)
            } ?: ""
        )
        vm.setEditRestText(visitedSet.restSec?.toString() ?: "")
        vm.setEditRpeText(visitedSet.rpe?.toString() ?: "")
    }

    fun currentEditDraft(): SetEditDraft = SetEditDraft(
        repsText = if (isGuestLaneActive) guestEditRepsText else ui.editRepsText,
        weightText = if (isGuestLaneActive) guestEditWeightText else ui.editWeightText,
        rpeText = if (isGuestLaneActive) "" else ui.editRpeText,
        restText = if (isGuestLaneActive) guestEditRestText else ui.editRestText
    )

    fun stashCurrentEditDraft() {
        val id = editingWorkoutExerciseId ?: return
        editDraftsByWorkoutExerciseId = editDraftsByWorkoutExerciseId + (id to currentEditDraft())
    }

    fun editShowsRestField(anchor: ActiveStrengthExerciseLine?): Boolean {
        if (isGuestLaneActive || anchor == null) return true
        val members = supersetMembers(anchor, ui.exercises)
        if (members.size <= 1) return true
        val setIndex = editingExpandedIndex ?: currentSetIndex
        val available = members.filter { it.sets.size > setIndex }
        return available.lastOrNull()?.workoutExerciseId == editingWorkoutExerciseId
    }

    fun openEditSet(exerciseIndex: Int, expandedIndex: Int) {
        val targetEx = ui.exercises.getOrNull(exerciseIndex) ?: return
        val visitedSet = targetEx.sets.getOrNull(expandedIndex) ?: return
        if (!showEditSheet) {
            editDraftsByWorkoutExerciseId = emptyMap()
            applyEditToRemainingSets = false
        }
        populateEditFieldsFromSet(visitedSet)
        editingExpandedIndex = expandedIndex
        editingWorkoutExerciseId = targetEx.workoutExerciseId
        showEditSheet = true
    }

    fun switchEditSupersetMember(memberIndex: Int, expandedIndex: Int) {
        stashCurrentEditDraft()
        val targetEx = ui.exercises.getOrNull(memberIndex) ?: return
        editingExpandedIndex = expandedIndex
        editingWorkoutExerciseId = targetEx.workoutExerciseId
        val draft = editDraftsByWorkoutExerciseId[targetEx.workoutExerciseId]
        if (draft != null) {
            vm.setEditRepsText(draft.repsText)
            vm.setEditWeightText(draft.weightText)
            vm.setEditRpeText(draft.rpeText)
            vm.setEditRestText(draft.restText)
        } else {
            val visitedSet = targetEx.sets.getOrNull(expandedIndex) ?: return
            populateEditFieldsFromSet(visitedSet)
        }
    }
    var snapToCurrentSignal by remember(ex?.workoutExerciseId, activeLane) { mutableIntStateOf(0) }
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
    val hostPagerPreviewWeId = ui.exercises.getOrNull(
        hostPagerDisplayIndex.coerceIn(0, ui.exercises.lastIndex.coerceAtLeast(0))
    )?.workoutExerciseId
    val hostBubbleEmphasisWeId = ui.navEmphasisLockWorkoutExerciseId ?: hostPagerPreviewWeId
    val guestPagerPreviewWeId = guestExercisesUi.getOrNull(
        guestCurrentExerciseIndex.coerceIn(0, guestExercisesUi.lastIndex.coerceAtLeast(0))
    )?.workoutExerciseId
    val guestBubbleEmphasisWeId = guestNavEmphasisLockWeId ?: guestPagerPreviewWeId
    val allSetsDoneCurrent = ex != null && currentSetIndex >= ex.sets.size
    val isLastExercise = laneGroupIndex == laneDisplayGroups.lastIndex
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
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        stringResource(R.string.active_strength_no_exercises),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        stringResource(R.string.active_strength_add_exercise_hint),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                    Button(
                        onClick = { vm.startAddExercise() },
                        modifier = Modifier
                            .padding(top = 16.dp)
                            .fillMaxWidth()
                    ) { Text(stringResource(R.string.active_strength_add_exercise)) }
                    OutlinedButton(
                        onClick = onClose,
                        modifier = Modifier
                            .padding(top = 8.dp)
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
                    when (ui.startSyncStatus) {
                        WorkoutStartSync.Status.PENDING,
                        WorkoutStartSync.Status.SYNCING -> {
                            Text(
                                text = stringResource(R.string.active_workout_syncing_start),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(bottom = 8.dp)
                            )
                        }
                        WorkoutStartSync.Status.WILL_RETRY -> {
                            Text(
                                text = stringResource(R.string.active_workout_sync_will_retry),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(bottom = 8.dp)
                            )
                        }
                        else -> Unit
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextButton(onClick = onClose, enabled = !ui.showElborblaCelebration) {
                            Text(stringResource(R.string.active_strength_back))
                        }
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Card(colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.85f))) {
                                Text(
                                    text = "⏱ ${formatElapsed(ui.sessionElapsedSec)}",
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                    style = MaterialTheme.typography.labelLarge
                                )
                            }
                            IconButton(
                                onClick = { vm.toggleSessionPause() },
                                enabled = !ui.finishing && !ui.loading
                            ) {
                                Icon(
                                    imageVector = if (ui.isSessionPaused) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                                    contentDescription = stringResource(
                                        if (ui.isSessionPaused) R.string.active_strength_resume else R.string.active_strength_pause
                                    )
                                )
                            }
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
                        val bubbleGroups = if (isGuestLaneActive) {
                            laneExercises.mapIndexed { i, _ ->
                                StrengthDisplayGroup("exercise-$i", null, listOf(i))
                            }
                        } else {
                            strengthDisplayGroups(laneExercises)
                        }
                        bubbleGroups.forEach { bubbleGroup ->
                            val bubbleIndices = bubbleGroup.exerciseIndices
                            val bubbleGroupContent: @Composable () -> Unit = {
                                bubbleIndices.forEach { index ->
                                    val bubbleEx = laneExercises[index]
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
                                            hostPagerDisplayIndex = pagerAnchorExerciseIndex(index, ui.exercises)
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
                            if (bubbleGroup.isSuperset) {
                                Row(
                                    modifier = Modifier
                                        .padding(horizontal = 4.dp)
                                        .clip(RoundedCornerShape(20.dp))
                                        .background(Color.White.copy(alpha = 0.35f))
                                        .padding(horizontal = 6.dp, vertical = 4.dp),
                                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    bubbleGroupContent()
                                }
                            } else {
                                bubbleGroupContent()
                            }
                        }
                    }

                    Box(
                        modifier = Modifier
                            .weight(1f, fill = true)
                            .padding(top = 14.dp)
                    ) {
                        val prevEx = laneDisplayGroups.getOrNull(laneGroupIndex - 1)
                            ?.exerciseIndices?.firstOrNull()
                            ?.let { laneExercises.getOrNull(it) }
                        val nextEx = laneDisplayGroups.getOrNull(laneGroupIndex + 1)
                            ?.exerciseIndices?.firstOrNull()
                            ?.let { laneExercises.getOrNull(it) }
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
                                .pointerInput(laneExerciseIndex, currentSetIndex, activeLane, hostPagerDisplayIndex, isSupersetCard) {
                                    if (isSupersetCard) return@pointerInput
                                    var totalDrag = 0f
                                    detectVerticalDragGestures(
                                        onVerticalDrag = { _, dragAmount -> totalDrag += dragAmount },
                                        onDragEnd = {
                                            if (abs(totalDrag) > 80f) {
                                                if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                                    if (totalDrag < 0f && guestCurrentExerciseIndex < laneExercises.lastIndex) guestCurrentExerciseIndex++
                                                    if (totalDrag > 0f && guestCurrentExerciseIndex > 0) guestCurrentExerciseIndex--
                                                } else {
                                                    val gi = laneGroupIndex
                                                    if (totalDrag < 0f && gi + 1 < laneDisplayGroups.size) {
                                                        laneDisplayGroups[gi + 1].exerciseIndices.firstOrNull()?.let {
                                                            hostPagerDisplayIndex = it
                                                            vm.goToExercise(it)
                                                        }
                                                    }
                                                    if (totalDrag > 0f && gi > 0) {
                                                        laneDisplayGroups[gi - 1].exerciseIndices.firstOrNull()?.let {
                                                            hostPagerDisplayIndex = it
                                                            vm.goToExercise(it)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    )
                                },
                            colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.52f))
                        ) {
                            Column(
                                Modifier.padding(if (isSupersetCard) 18.dp else 14.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                if (isSupersetCard && currentDisplayGroup != null) {
                                    ActiveStrengthSupersetCard(
                                        group = currentDisplayGroup,
                                        exercises = laneExercises,
                                        activeExerciseIndex = workExerciseIndex,
                                        setProgress = laneProgressMap,
                                        completedSetsByExerciseId = ui.completedSetsByExerciseId,
                                        restSecondsByExerciseId = if (isGuestLaneActive) {
                                            guestRestSecByExerciseId
                                        } else {
                                            ui.restSecondsLeftByExerciseId
                                        },
                                        finishing = ui.finishing,
                                        onMemberTap = { idx ->
                                            hostPagerDisplayIndex = pagerAnchorExerciseIndex(idx, ui.exercises)
                                            vm.goToExercise(idx)
                                        },
                                        onEditSet = { exerciseIndex, roundIndex ->
                                            openEditSet(exerciseIndex, roundIndex)
                                        },
                                        editEnabled = !isGuestLaneActive,
                                        onSetDone = { vm.onSetDone() },
                                        onSkipRest = {
                                            if (isGuestLaneActive) {
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
                                        onNextExercise = { vm.goToNextExercise() },
                                        showNextExercise = !isLastExercise
                                    )
                                } else {
                                Text(
                                    text = ex?.displayName.orEmpty(),
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.Bold
                                )

                                val laneCompletedMap = if (activeLane == 1 && ui.guestExercises.isNotEmpty()) {
                                    emptyMap()
                                } else {
                                    ui.completedSetsByExerciseId
                                }
                                val totalSetsForEx = ex?.sets?.size ?: 0
                                val sliderEnabled = ex != null && totalSetsForEx > 0 && !allSetsDoneCurrent
                                var visitedSetIndexForActions by remember(ex?.workoutExerciseId, activeLane) {
                                    mutableIntStateOf(currentSetIndex.coerceIn(0, max(0, totalSetsForEx - 1)))
                                }
                                val sliderEx = if (sliderEnabled) ex else null

                                if (sliderEx != null) {
                                    key(sliderEx.workoutExerciseId, activeLane) {
                                        val pagerState = rememberPagerState(
                                            initialPage = currentSetIndex.coerceIn(0, max(0, totalSetsForEx - 1)),
                                            pageCount = { totalSetsForEx }
                                        )
                                        LaunchedEffect(currentSetIndex, totalSetsForEx) {
                                            val target = currentSetIndex.coerceIn(0, max(0, totalSetsForEx - 1))
                                            if (pagerState.currentPage != target) {
                                                pagerState.animateScrollToPage(target)
                                            }
                                        }
                                        LaunchedEffect(pagerState.currentPage) {
                                            visitedSetIndexForActions = pagerState.currentPage
                                        }
                                        LaunchedEffect(snapToCurrentSignal) {
                                            if (snapToCurrentSignal > 0) {
                                                val target = currentSetIndex.coerceIn(0, max(0, totalSetsForEx - 1))
                                                if (pagerState.currentPage != target) {
                                                    pagerState.animateScrollToPage(target)
                                                }
                                            }
                                        }

                                        HorizontalPager(
                                            state = pagerState,
                                            modifier = Modifier.fillMaxWidth()
                                        ) { page ->
                                            val plannedSet = sliderEx.sets.getOrNull(page)
                                            val isPast = page < currentSetIndex
                                            val isCurrent = page == currentSetIndex
                                            val performed = laneCompletedMap[sliderEx.workoutExerciseId]?.getOrNull(page)
                                            val displayReps: Int? = if (isPast) (performed?.reps ?: plannedSet?.reps) else plannedSet?.reps
                                            val displayWeight: Double? = if (isPast) (performed?.weightKg ?: plannedSet?.weightKg) else plannedSet?.weightKg
                                            val displayRpe: Double? = if (isPast) (performed?.rpe ?: plannedSet?.rpe) else plannedSet?.rpe
                                            val displaySegs = if (isPast) (performed?.weightSegments ?: plannedSet?.weightSegments) else plannedSet?.weightSegments
                                            val statusLabel = when {
                                                isPast -> "Completed"
                                                isCurrent -> "Current"
                                                else -> "Upcoming"
                                            }
                                            val statusColor = when {
                                                isPast -> Color(0xFF666666)
                                                isCurrent -> MaterialTheme.colorScheme.primary
                                                else -> Color(0xFFD08A1B)
                                            }

                                            Card(
                                                colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.72f)),
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .padding(horizontal = 4.dp)
                                            ) {
                                                Column(
                                                    Modifier
                                                        .fillMaxWidth()
                                                        .padding(14.dp),
                                                    horizontalAlignment = Alignment.CenterHorizontally,
                                                    verticalArrangement = Arrangement.spacedBy(4.dp)
                                                ) {
                                                    Row(
                                                        verticalAlignment = Alignment.CenterVertically,
                                                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                                                    ) {
                                                        Text(
                                                            text = statusLabel.uppercase(),
                                                            color = statusColor,
                                                            style = MaterialTheme.typography.labelSmall,
                                                            fontWeight = FontWeight.Bold,
                                                            modifier = Modifier
                                                                .clip(CircleShape)
                                                                .background(statusColor.copy(alpha = 0.15f))
                                                                .padding(horizontal = 8.dp, vertical = 3.dp)
                                                        )
                                                    }
                                                    Text(
                                                        text = stringResource(
                                                            R.string.active_strength_set_progress,
                                                            page + 1,
                                                            totalSetsForEx
                                                        ),
                                                        style = MaterialTheme.typography.titleMedium
                                                    )
                                                    if (displaySegs != null && displaySegs.size >= 2) {
                                                        Text("Drop set", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                                        Column(
                                                            horizontalAlignment = Alignment.CenterHorizontally,
                                                            verticalArrangement = Arrangement.spacedBy(4.dp),
                                                            modifier = Modifier.padding(top = 2.dp)
                                                        ) {
                                                            displaySegs.forEach { el ->
                                                                val o = el.jsonObject
                                                                val r = o["reps"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0
                                                                val w = o["weight_kg"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: 0.0
                                                                Text(
                                                                    "$r reps · ${String.format(Locale.US, "%.1f", w)} kg",
                                                                    style = MaterialTheme.typography.titleLarge,
                                                                    textAlign = TextAlign.Center
                                                                )
                                                            }
                                                        }
                                                    } else {
                                                        Text(
                                                            "${displayReps ?: 0} reps",
                                                            style = MaterialTheme.typography.headlineSmall,
                                                            modifier = Modifier.padding(top = 2.dp)
                                                        )
                                                        Text(
                                                            "${displayWeight?.let { String.format(Locale.US, "%.1f", it) } ?: "0.0"} kg",
                                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                            modifier = Modifier.padding(top = 2.dp)
                                                        )
                                                    }
                                                    displayRpe?.let {
                                                        Text(
                                                            "Target RPE ${String.format(Locale.US, "%.1f", it)}",
                                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                                        )
                                                    }
                                                    val plannedRest = plannedSet?.restSec ?: 0
                                                    if (isCurrent && !laneIsResting && plannedRest > 0) {
                                                        Text(
                                                            "Rest ${plannedRest}s after set",
                                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                                        )
                                                    }
                                                }
                                            }
                                        }

                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .padding(top = 4.dp),
                                            horizontalArrangement = Arrangement.Center,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            for (i in 0 until totalSetsForEx) {
                                                val isVisited = i == pagerState.currentPage
                                                val isCurrentDot = i == currentSetIndex
                                                val dotColor = when {
                                                    isVisited -> MaterialTheme.colorScheme.primary
                                                    isCurrentDot -> MaterialTheme.colorScheme.primary.copy(alpha = 0.55f)
                                                    else -> Color.Black.copy(alpha = 0.25f)
                                                }
                                                Box(
                                                    Modifier
                                                        .padding(horizontal = 3.dp)
                                                        .size(if (isCurrentDot || isVisited) 9.dp else 7.dp)
                                                        .clip(CircleShape)
                                                        .background(dotColor)
                                                )
                                            }
                                        }
                                    }
                                } else {
                                    Card(colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.72f))) {
                                        Column(
                                            Modifier
                                                .fillMaxWidth()
                                                .padding(14.dp),
                                            horizontalAlignment = Alignment.CenterHorizontally
                                        ) {
                                            Text(stringResource(R.string.active_strength_all_sets_done))
                                            Text("Great job! Move on when ready.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                }

                                val isVisitingCurrent = visitedSetIndexForActions == currentSetIndex
                                val visitedIsPast = sliderEnabled && visitedSetIndexForActions < currentSetIndex

                                if (!allSetsDoneCurrent) {
                                    if (!visitedIsPast) {
                                        OutlinedButton(
                                            onClick = {
                                                val visitedSet = ex?.sets?.getOrNull(visitedSetIndexForActions)
                                                if (visitedSet != null && !isGuestLaneActive) {
                                                    openEditSet(workExerciseIndex, visitedSetIndexForActions)
                                                } else if (visitedSet != null && isGuestLaneActive) {
                                                    if (!showEditSheet) {
                                                        applyEditToRemainingSets = false
                                                    }
                                                    editingExpandedIndex = visitedSetIndexForActions
                                                    editingWorkoutExerciseId = null
                                                    guestEditRepsText = visitedSet.reps?.toString() ?: ""
                                                    guestEditWeightText = visitedSet.weightKg?.let { v ->
                                                        if (v == v.toInt().toDouble()) v.toInt().toString()
                                                        else String.format(Locale.US, "%.1f", v)
                                                    } ?: ""
                                                    guestEditRestText = visitedSet.restSec?.toString() ?: ""
                                                    showEditSheet = true
                                                }
                                            },
                                            enabled = ex?.sets?.getOrNull(visitedSetIndexForActions) != null && !laneIsResting && !ui.finishing,
                                            modifier = Modifier.fillMaxWidth()
                                        ) { Text("Edit reps, weight & rest") }
                                    }

                                    if (laneIsResting) {
                                        Column(
                                            modifier = Modifier.fillMaxWidth(),
                                            verticalArrangement = Arrangement.spacedBy(10.dp)
                                        ) {
                                            ActiveStrengthRestTimerRow(restSec = laneRestSec)
                                            ActiveStrengthSkipRestOutlinedButton(
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
                                                enabled = !ui.finishing
                                            )
                                        }
                                    } else if (!isVisitingCurrent && sliderEnabled) {
                                        Button(
                                            onClick = { snapToCurrentSignal += 1 },
                                            modifier = Modifier.fillMaxWidth()
                                        ) { Text("Back to current set") }
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
                                            val label = if (set != null && ex != null) {
                                                primarySetActionLabel(
                                                    ex = ex,
                                                    exercises = ui.exercises,
                                                    setIndex = currentSetIndex,
                                                    setProgress = ui.currentSetIndexByExerciseId,
                                                    currentSet = set
                                                )
                                            } else {
                                                stringResource(R.string.active_strength_set_done)
                                            }
                                            Text(label)
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
                                        Text(stringResource(R.string.active_strength_next_exercise))
                                    }
                                }
                                }
                            }
                        }
                    }

                    if (isLastExercise) {
                        Button(
                            onClick = requestFinishWorkout,
                            enabled = !ui.finishing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp)
                        ) {
                            Text(if (ui.finishing) stringResource(R.string.active_strength_saving) else stringResource(R.string.active_strength_finish))
                        }
                    } else if (!ui.completedEntirely) {
                        Button(
                            onClick = requestFinishWorkout,
                            enabled = !ui.finishing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF34C759))
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
        val editTargetEx = editingWorkoutExerciseId?.let { wid ->
            ui.exercises.firstOrNull { it.workoutExerciseId == wid }
        } ?: ex
        val editingSet = run {
            val idx = editingExpandedIndex ?: currentSetIndex
            editTargetEx?.sets?.getOrNull(idx) ?: set
        }
        val editSupersetMembers = remember(editingWorkoutExerciseId, showEditSheet, ui.exercises) {
            val anchor = editTargetEx ?: return@remember emptyList()
            supersetMembers(anchor, ui.exercises).takeIf { it.size > 1 }.orEmpty()
        }
        val editStartIndex = editingExpandedIndex ?: currentSetIndex
        val editSetsForRemaining = editTargetEx?.sets ?: ex?.sets
        val editLastSetIndex = editSetsForRemaining?.lastIndex?.coerceAtLeast(0) ?: 0
        val showApplyToRemainingToggle = editStartIndex < editLastSetIndex
        if (showEditSheet && editingSet != null) {
        var showConvertToNormal by remember(showEditSheet, editingSet.setId) { mutableStateOf(false) }
        var convertNormalRepsText by remember(showEditSheet, editingSet.setId) { mutableStateOf("") }
        var convertNormalWeightText by remember(showEditSheet, editingSet.setId) { mutableStateOf("") }

        val initialDropSegs = remember(showEditSheet, editingSet.setId) {
            val arr = editingSet.weightSegments
            if (arr == null || arr.size < 2) {
                mutableListOf<Pair<String, String>>()
            } else {
                arr.mapNotNull { el ->
                    val o = el.jsonObject
                    val r = o["reps"]?.jsonPrimitive?.content ?: return@mapNotNull null
                    val w = o["weight_kg"]?.jsonPrimitive?.content ?: return@mapNotNull null
                    (r to w)
                }.toMutableList()
            }
        }
        var dropSegs by remember(showEditSheet, editingSet.setId) { mutableStateOf(initialDropSegs) }

            Card(
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(20.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Edit reps, weight & rest", style = MaterialTheme.typography.titleMedium)

                if (editSupersetMembers.isNotEmpty() && !isGuestLaneActive) {
                    Text("Exercise", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        editSupersetMembers.forEach { member ->
                            val memberIndex = ui.exercises.indexOfFirst { it.workoutExerciseId == member.workoutExerciseId }
                            if (memberIndex < 0) return@forEach
                            val selected = editingWorkoutExerciseId == member.workoutExerciseId
                            OutlinedButton(
                                onClick = {
                                    switchEditSupersetMember(memberIndex, editingExpandedIndex ?: currentSetIndex)
                                },
                                border = if (selected) {
                                    androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.primary)
                                } else null
                            ) {
                                Text(member.displayName, maxLines = 1)
                            }
                        }
                    }
                }

                val isDropSet = !isGuestLaneActive && (dropSegs.size >= 2)
                if (isDropSet) {
                    Text("Drop set", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    dropSegs.forEachIndexed { idx, pair ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            OutlinedTextField(
                                value = pair.first,
                                onValueChange = { t ->
                                    dropSegs = dropSegs.toMutableList().apply { this[idx] = (t to this[idx].second) }
                                },
                                label = { Text(stringResource(R.string.active_strength_field_reps)) },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = pair.second,
                                onValueChange = { t ->
                                    dropSegs = dropSegs.toMutableList().apply { this[idx] = (this[idx].first to t) }
                                },
                                label = { Text(stringResource(R.string.active_strength_field_weight_kg)) },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = {
                                val last = dropSegs.lastOrNull() ?: ("10" to "0")
                                dropSegs = dropSegs.toMutableList().apply { add(last) }
                            },
                            modifier = Modifier.weight(1f)
                        ) { Text("Add step") }
                        OutlinedButton(
                            onClick = {
                                if (dropSegs.size > 2) dropSegs = dropSegs.toMutableList().apply { removeLast() }
                            },
                            enabled = dropSegs.size > 2,
                            modifier = Modifier.weight(1f)
                        ) { Text("Remove step") }
                    }
                    OutlinedButton(
                        onClick = {
                            val first = dropSegs.firstOrNull()
                            convertNormalRepsText = first?.first ?: (editingSet.reps?.toString() ?: "")
                            convertNormalWeightText = first?.second ?: (editingSet.weightKg?.toString() ?: "")
                            showConvertToNormal = true
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Convert to normal set") }
                } else {
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
                    if (editShowsRestField(editTargetEx)) {
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
                    }
                val isWireDropSet = editingSet.weightSegments != null && editingSet.weightSegments.size >= 2
                if (!isGuestLaneActive && !isDropSet && !isWireDropSet) {
                        OutlinedButton(
                            onClick = {
                                vm.convertCurrentSetToDropSet(editingExpandedIndex, editingWorkoutExerciseId)
                                showEditSheet = false
                                editingExpandedIndex = null
                                editingWorkoutExerciseId = null
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Convert to drop set") }
                    }
                    if (showApplyToRemainingToggle) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                stringResource(
                                    R.string.active_strength_apply_to_remaining_sets,
                                    editStartIndex + 1,
                                    editLastSetIndex + 1
                                ),
                                modifier = Modifier.weight(1f)
                            )
                            Switch(
                                checked = applyEditToRemainingSets,
                                onCheckedChange = { applyEditToRemainingSets = it }
                            )
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = {
                                showEditSheet = false
                                editingExpandedIndex = null
                                editingWorkoutExerciseId = null
                                editDraftsByWorkoutExerciseId = emptyMap()
                                applyEditToRemainingSets = false
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Cancel")
                        }
                        Button(
                            onClick = {
                                if (isGuestLaneActive) {
                                    val exLocal = guestExercisesUi.getOrNull(guestCurrentExerciseIndex)
                                        ?: return@Button
                                    val guestCurrent = guestSetProgress[exLocal.workoutExerciseId] ?: 0
                                    val setIndex = (editingExpandedIndex ?: guestCurrent)
                                        .coerceIn(0, exLocal.sets.lastIndex.coerceAtLeast(0))
                                    val reps = guestEditRepsText.trim().toIntOrNull()
                                    val weight = guestEditWeightText.trim().replace(',', '.').toDoubleOrNull()
                                    val rest = guestEditRestText.trim().toIntOrNull()?.coerceAtLeast(0)
                                    val lastIndex = exLocal.sets.lastIndex.coerceAtLeast(0)
                                    val targetIndices = if (applyEditToRemainingSets && setIndex < lastIndex) {
                                        setIndex..lastIndex
                                    } else {
                                        listOf(setIndex)
                                    }
                                    var nextSets = exLocal.sets
                                    for (idx in targetIndices) {
                                        nextSets = updateBlockForExpandedIndex(
                                            sets = nextSets,
                                            expandedIndex = idx,
                                            reps = reps,
                                            weightKg = weight,
                                            rpe = nextSets.getOrNull(idx)?.rpe,
                                            restSec = rest
                                        )
                                    }
                                    val nextEx = exLocal.copy(sets = nextSets)
                                    guestExercisesUi = guestExercisesUi.toMutableList().apply {
                                        if (guestCurrentExerciseIndex in indices) {
                                            this[guestCurrentExerciseIndex] = nextEx
                                        }
                                    }
                                } else {
                                if (isDropSet) {
                                    val segPayload = dropSegs.mapNotNull { (rT, wT) ->
                                        val r = rT.trim().toIntOrNull() ?: return@mapNotNull null
                                        val w = wT.trim().replace(',', '.').toDoubleOrNull() ?: return@mapNotNull null
                                        StrengthSegmentPayload(r, w)
                                    }
                                    if (segPayload.size >= 2) {
                                        vm.applyCurrentDropSetEdits(
                                            segPayload,
                                            editingExpandedIndex,
                                            editingWorkoutExerciseId,
                                            applyEditToRemainingSets
                                        )
                                    }
                                } else {
                                    val mergedDrafts = editingWorkoutExerciseId?.let { wid ->
                                        editDraftsByWorkoutExerciseId + (wid to currentEditDraft())
                                    } ?: editDraftsByWorkoutExerciseId
                                    vm.applyAllSetEditDrafts(
                                        editingExpandedIndex ?: currentSetIndex,
                                        mergedDrafts,
                                        applyEditToRemainingSets
                                    )
                                }
                                }
                                showEditSheet = false
                                editingExpandedIndex = null
                                editingWorkoutExerciseId = null
                                editDraftsByWorkoutExerciseId = emptyMap()
                                applyEditToRemainingSets = false
                            },
                            modifier = Modifier.weight(1f)
                        ) { Text("Save") }
                    }
                }
                }
            }
        if (showConvertToNormal && !isGuestLaneActive) {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp)
                    .align(Alignment.BottomCenter),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Convert to normal set", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = convertNormalRepsText,
                        onValueChange = { convertNormalRepsText = it },
                        label = { Text(stringResource(R.string.active_strength_field_reps)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                    )
                    OutlinedTextField(
                        value = convertNormalWeightText,
                        onValueChange = { convertNormalWeightText = it },
                        label = { Text(stringResource(R.string.active_strength_field_weight_kg)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = { showConvertToNormal = false },
                            modifier = Modifier.weight(1f)
                        ) { Text("Cancel") }
                        Button(
                            onClick = {
                                val r = convertNormalRepsText.trim().toIntOrNull() ?: 10
                                val w = convertNormalWeightText.trim().replace(',', '.').toDoubleOrNull() ?: 0.0
                                vm.convertCurrentSetToNormalSet(r, w, editingExpandedIndex, editingWorkoutExerciseId)
                                showConvertToNormal = false
                                showEditSheet = false
                                editingExpandedIndex = null
                                editingWorkoutExerciseId = null
                            },
                            modifier = Modifier.weight(1f)
                        ) { Text("Convert") }
                    }
                }
            }
        }
        }
    }
    if (ui.showExercisePicker) {
        val pickerSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { vm.dismissExercisePicker() },
            sheetState = pickerSheetState
        ) {
            ActiveStrengthExercisePickerSheet(
                exercises = ui.pickerExercises,
                loading = ui.pickerLoading,
                loadError = ui.pickerLoadError,
                sortMode = ui.exercisePickerSortMode,
                onSortMode = { vm.setExercisePickerSortMode(it) },
                onPick = { vm.onExercisePicked(it) },
                onDismiss = { vm.dismissExercisePicker() }
            )
        }
    }
    if (ui.showExerciseSetup) {
        ActiveStrengthExerciseSetupDialog(
            drafts = ui.exerciseSetupDrafts,
            isSaving = ui.isPersistingExerciseAdd,
            error = ui.exerciseSetupError,
            onDismiss = { vm.dismissExerciseSetup() },
            onAddSet = { vm.addSetToExerciseSetupDraft() },
            onRemoveSet = { vm.removeSetFromExerciseSetupDraft() },
            onUpdateSet = vm::updateExerciseSetupSet,
            onConfirm = { vm.saveConfiguredExercise(connectionUnstableMsg) }
        )
    }
    if (showFinishConfirm) {
        AlertDialog(
            onDismissRequest = { if (!ui.finishing) showFinishConfirm = false },
            title = {
                Text(
                    stringResource(
                        if (ui.completedEntirely) {
                            R.string.active_strength_finish_confirm_title
                        } else {
                            R.string.active_strength_finish_early_title
                        }
                    )
                )
            },
            text = { Text(finishConfirmMessage) },
            confirmButton = {
                Button(
                    onClick = {
                        showFinishConfirm = false
                        runFinishWorkout()
                    },
                    enabled = !ui.finishing
                ) {
                    Text(stringResource(R.string.active_strength_finish))
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showFinishConfirm = false },
                    enabled = !ui.finishing
                ) {
                    Text(stringResource(R.string.home_guest_detail_cancel))
                }
            }
        )
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
    if (!ui.finishing) {
        MessagesFloatingButton(
            supabase = supabase,
            modifier = Modifier.fillMaxSize()
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActiveStrengthExercisePickerSheet(
    exercises: List<com.lilru.liftr.ui.add.ExerciseLite>,
    loading: Boolean,
    loadError: String?,
    sortMode: ExercisePickerSortMode,
    onSortMode: (ExercisePickerSortMode) -> Unit,
    onPick: (com.lilru.liftr.ui.add.ExerciseLite) -> Unit,
    onDismiss: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                stringResource(R.string.add_exercise_pick),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.home_guest_detail_cancel))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 8.dp)) {
            TextButton(onClick = { onSortMode(ExercisePickerSortMode.ALPHABETIC) }) {
                Text(stringResource(R.string.add_exercise_sort_a_z))
            }
            TextButton(onClick = { onSortMode(ExercisePickerSortMode.MOST_USED) }) {
                Text(stringResource(R.string.add_exercise_sort_most_used))
            }
        }
        loadError?.let { err ->
            Text(
                err,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(bottom = 8.dp)
            )
        }
        if (loading) {
            Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(360.dp)
            ) {
                items(exercises, key = { it.id }) { ex ->
                    Text(
                        ex.name,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onPick(ex) }
                            .padding(vertical = 12.dp),
                        style = MaterialTheme.typography.bodyLarge
                    )
                }
            }
        }
    }
}

@Composable
private fun ActiveStrengthExerciseSetupDialog(
    drafts: List<ActiveExerciseSetupExerciseDraft>,
    isSaving: Boolean,
    error: String?,
    onDismiss: () -> Unit,
    onAddSet: () -> Unit,
    onRemoveSet: () -> Unit,
    onUpdateSet: (draftId: String, setId: String, repsText: String?, weightText: String?, restText: String?, rpeText: String?) -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = { if (!isSaving) onDismiss() },
        title = { Text(stringResource(R.string.active_strength_configure_exercise)) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                drafts.forEach { draft ->
                    Text(draft.exercise.name, fontWeight = FontWeight.SemiBold)
                    draft.sets.forEachIndexed { idx, set ->
                        Text("Set ${idx + 1}", style = MaterialTheme.typography.labelMedium)
                        OutlinedTextField(
                            value = set.repsText,
                            onValueChange = { onUpdateSet(draft.id, set.id, it, null, null, null) },
                            label = { Text(stringResource(R.string.active_strength_field_reps)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.fillMaxWidth()
                        )
                        OutlinedTextField(
                            value = set.weightText,
                            onValueChange = { onUpdateSet(draft.id, set.id, null, it, null, null) },
                            label = { Text(stringResource(R.string.active_strength_field_weight_kg)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            modifier = Modifier.fillMaxWidth()
                        )
                        OutlinedTextField(
                            value = set.restText,
                            onValueChange = { onUpdateSet(draft.id, set.id, null, null, it, null) },
                            label = { Text("Rest (s)") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = onAddSet) { Text(stringResource(R.string.add_set_add)) }
                    TextButton(onClick = onRemoveSet) { Text("Remove set") }
                }
                error?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            Button(onClick = onConfirm, enabled = !isSaving && drafts.isNotEmpty()) {
                if (isSaving) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Text(stringResource(R.string.active_strength_add_exercise))
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isSaving) {
                Text(stringResource(R.string.home_guest_detail_cancel))
            }
        }
    )
}

private fun formatElapsed(totalSec: Int): String {
    if (totalSec < 0) return "0:00"
    val m = totalSec / 60
    val s = totalSec % 60
    return String.format("%d:%02d", m, s)
}
