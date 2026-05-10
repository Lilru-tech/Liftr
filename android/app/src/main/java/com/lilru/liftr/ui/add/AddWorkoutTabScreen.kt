package com.lilru.liftr.ui.add

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Surface
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.serialization.json.jsonArray
import java.time.Instant
import kotlin.math.roundToInt
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.prefs.ExerciseLanguagePreferences
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import com.lilru.liftr.ui.add.duplicate.AddWorkoutDuplicateStore
import com.lilru.liftr.ui.chat.RoutineShareSnapshot
import com.lilru.liftr.ui.chat.ShareRoutineToChatSheetContent
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.add.recommendation.CardioRecommendationResult
import com.lilru.liftr.ui.add.recommendation.HyroxExerciseRecommendationResult
import com.lilru.liftr.ui.add.recommendation.SportRecommendationResult
import io.github.jan.supabase.SupabaseClient
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

@Composable
private fun AddWorkoutSignInPrompt(
    onSignIn: () -> Unit,
    modifier: Modifier = Modifier
) {
    val ctx = LocalContext.current
    val themeId = remember { LiftrPreferences.backgroundTheme(ctx) }
    Box(
        modifier
            .fillMaxSize()
            .liftrAppBackgroundGradient(themeId)
            .windowInsetsPadding(WindowInsets.safeDrawing)
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                stringResource(R.string.add_sign_in_title),
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(12.dp))
            Text(
                stringResource(R.string.add_sign_in_body),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(20.dp))
            Button(onClick = onSignIn) {
                Text(stringResource(R.string.add_sign_in_cta))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddWorkoutTabScreen(
    supabase: SupabaseClient,
    duplicateApplyNonce: Int = 0,
    kindNudge: String? = null,
    kindNudgeNonce: Int = 0,
    onWorkoutPublishedToHome: () -> Unit = {},
    isSignedIn: Boolean = true,
    onGoToSignIn: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    if (!isSignedIn) {
        AddWorkoutSignInPrompt(
            onSignIn = onGoToSignIn,
            modifier = modifier
        )
        return
    }
    val app = LocalContext.current.applicationContext as Application
    val vm: AddWorkoutViewModel = viewModel(factory = AddWorkoutViewModelFactory(supabase, app))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(ui.postPublishHomeNonce) {
        if (ui.postPublishHomeNonce > 0) {
            onWorkoutPublishedToHome()
            vm.clearPostPublishHomeNonce()
        }
    }
    LaunchedEffect(ui.pendingOpenWorkoutId) {
        val id = ui.pendingOpenWorkoutId ?: return@LaunchedEffect
        vm.consumePendingOpenWorkout()
        AppNavEvents.send(MainOverlay.WorkoutDetail(id, null))
    }
    var title by rememberSaveable { mutableStateOf("") }
    var notes by rememberSaveable { mutableStateOf("") }
    var startedAtIsoText by rememberSaveable { mutableStateOf("") }
    var scheduleEndedEnabled by rememberSaveable { mutableStateOf(false) }
    var endedAtIsoText by rememberSaveable { mutableStateOf("") }
    var selectedState by rememberSaveable { mutableStateOf(AddWorkoutState.PUBLISHED) }
    var selectedIntensity by rememberSaveable { mutableStateOf(AddWorkoutIntensity.MODERATE) }
    var selectedKind by rememberSaveable { mutableStateOf(AddWorkoutKind.STRENGTH) }
    var cardioActivity by rememberSaveable { mutableStateOf(AddCardioActivity.RUN) }
    var cardioDistanceKm by rememberSaveable { mutableStateOf("") }
    var cardioDurH by rememberSaveable { mutableStateOf("") }
    var cardioDurM by rememberSaveable { mutableStateOf("") }
    var cardioDurS by rememberSaveable { mutableStateOf("") }
    var cardioDurationSecFallback by rememberSaveable { mutableStateOf("") }
    var didEditCardioDuration by rememberSaveable { mutableStateOf(false) }
    var didEditSportDuration by rememberSaveable { mutableStateOf(false) }
    var cardioAvgHr by rememberSaveable { mutableStateOf("") }
    var cardioMaxHr by rememberSaveable { mutableStateOf("") }
    var cardioAvgPaceSecPerKm by rememberSaveable { mutableStateOf("") }
    var cardioElevationGainM by rememberSaveable { mutableStateOf("") }
    var sportType by rememberSaveable { mutableStateOf(AddSportType.PADEL) }
    var footballPosition by rememberSaveable { mutableStateOf(AddFootballPosition.FORWARD) }
    var racketMode by rememberSaveable { mutableStateOf(AddRacketMode.SINGLES) }
    var racketFormat by rememberSaveable { mutableStateOf(AddRacketFormat.BEST_OF_3) }
    var sportDurationMin by rememberSaveable { mutableStateOf("") }
    var sportScoreFor by rememberSaveable { mutableStateOf("") }
    var sportScoreAgainst by rememberSaveable { mutableStateOf("") }
    var sportMatchScoreText by rememberSaveable { mutableStateOf("") }
    var sportLocation by rememberSaveable { mutableStateOf("") }
    var sportSessionNotes by rememberSaveable { mutableStateOf("") }
    var sportMatchResult by rememberSaveable { mutableStateOf(AddMatchResult.UNFINISHED) }
    var hyroxExercisesJson by rememberSaveable { mutableStateOf("") }
    var createRoutineEnabled by rememberSaveable { mutableStateOf(false) }
    var newStrengthRoutineName by rememberSaveable { mutableStateOf("") }
    var newStrengthTemplateFolderId by rememberSaveable { mutableStateOf<Long?>(null) }
    var createHyroxRoutineEnabled by rememberSaveable { mutableStateOf(false) }
    var newHyroxRoutineName by rememberSaveable { mutableStateOf("") }
    var newHyroxRoutineFolderId by rememberSaveable { mutableStateOf<Long?>(null) }
    var showHyroxRoutinesSheet by remember { mutableStateOf(false) }
    var hyroxFolderMenuExpanded by remember { mutableStateOf(false) }
    val cardioStats = remember { mutableStateMapOf<String, String>() }
    val sportStats = remember { mutableStateMapOf<String, String>() }
    val strengthExercises = if (ui.perPersonStrength) {
        val laneId = ui.activeLaneUserId ?: ui.currentUserId
        laneId?.let { ui.laneExercisesByUser[it] }.orEmpty()
    } else {
        ui.selectedExercises
    }
    val laneOwners = buildList {
        ui.currentUserId?.let { add(it) }
        addAll(ui.selectedParticipantIds.toList())
    }
    val exerciseLangScope = rememberCoroutineScope()
    var exerciseLang by remember { mutableStateOf("en") }
    LaunchedEffect(app) {
        exerciseLang = withContext(Dispatchers.IO) { ExerciseLanguagePreferences.read(app) }
    }
    var sortMenuExpanded by remember { mutableStateOf(false) }
    var languageMenuExpanded by remember { mutableStateOf(false) }
    var folderMenuExpanded by remember { mutableStateOf(false) }

    var showRecommend by remember { mutableStateOf(false) }
    var showRoutinesSheet by remember { mutableStateOf(false) }
    var showParticipantsSheet by remember { mutableStateOf(false) }
    var participantsSearchQuery by remember { mutableStateOf("") }
    var showWorkoutHelp by rememberSaveable { mutableStateOf(false) }
    var showClearStrengthDialog by remember { mutableStateOf(false) }
    var showClearHyroxDialog by remember { mutableStateOf(false) }
    var exerciseSearch by remember { mutableStateOf("") }
    var strengthExercisePickTarget by remember { mutableStateOf<StrengthExercisePickTarget?>(null) }
    val routinesSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val hyroxRoutinesSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val participantsSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val exerciseSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val templateEditSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val workoutHelpSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var showShareRoutineSheet by remember { mutableStateOf(false) }
    var routineShareSnapshot by remember { mutableStateOf<RoutineShareSnapshot?>(null) }
    var routineShareError by remember { mutableStateOf<String?>(null) }

    var showRoutinePreviewSheet by remember { mutableStateOf(false) }
    var routinePreviewSnapshot by remember { mutableStateOf<RoutineShareSnapshot?>(null) }
    val shareRoutineSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    LaunchedEffect(showParticipantsSheet) {
        if (showParticipantsSheet) {
            participantsSearchQuery = ""
        }
    }
    val filteredExercises = remember(exerciseSearch, ui.exercises, exerciseLang) {
        val q = exerciseSearch.trim()
        if (q.isEmpty()) {
            ui.exercises
        } else {
            ui.exercises.filter { ex ->
                val label = ex.localizedPickerName(exerciseLang).lowercase()
                label.contains(q.lowercase())
            }
        }
    }

    val canSave = remember(
        selectedKind,
        strengthExercises,
        createRoutineEnabled,
        newStrengthRoutineName,
        sportType,
        hyroxExercisesJson,
        createHyroxRoutineEnabled,
        newHyroxRoutineName
    ) {
        canSaveAddWorkout(
            kind = selectedKind,
            strengthExercises = strengthExercises,
            createRoutineEnabled = createRoutineEnabled,
            newStrengthRoutineName = newStrengthRoutineName,
            sportType = sportType,
            hyroxExercisesJson = hyroxExercisesJson,
            createHyroxRoutineEnabled = createHyroxRoutineEnabled,
            newHyroxRoutineName = newHyroxRoutineName
        )
    }
    val canSaveRoutineOnly = remember(
        createRoutineEnabled,
        strengthExercises,
        newStrengthRoutineName
    ) {
        createRoutineEnabled &&
            strengthExercisesFormValidForSave(strengthExercises) &&
            newStrengthRoutineName.trim().isNotEmpty()
    }
    val canSaveHyroxRoutineOnly = remember(
        createHyroxRoutineEnabled,
        hyroxExercisesJson,
        newHyroxRoutineName
    ) {
        createHyroxRoutineEnabled &&
            hyroxExercisesJsonValid(hyroxExercisesJson) &&
            newHyroxRoutineName.trim().isNotEmpty()
    }
    LaunchedEffect(createRoutineEnabled) {
        if (!createRoutineEnabled) {
            newStrengthRoutineName = ""
            newStrengthTemplateFolderId = null
        }
    }
    LaunchedEffect(Unit) {
        if (startedAtIsoText.isBlank()) {
            startedAtIsoText = Instant.now().toString()
        }
    }
    LaunchedEffect(kindNudgeNonce) {
        if (kindNudgeNonce == 0) return@LaunchedEffect
        val k = kindNudge?.trim()?.lowercase() ?: return@LaunchedEffect
        selectedKind = when (k) {
            "cardio" -> AddWorkoutKind.CARDIO
            "sport" -> AddWorkoutKind.SPORT
            else -> AddWorkoutKind.STRENGTH
        }
    }
    LaunchedEffect(duplicateApplyNonce) {
        if (duplicateApplyNonce == 0) return@LaunchedEffect
        val payload = AddWorkoutDuplicateStore.take() ?: return@LaunchedEffect
        val f = payload.prefill
        title = f.title
        notes = f.notes
        startedAtIsoText = f.startedAtIso
        scheduleEndedEnabled = f.scheduleEndedEnabled
        endedAtIsoText = f.endedAtIso
        selectedState = f.addState
        selectedIntensity = f.intensity
        selectedKind = f.kind
        cardioActivity = f.cardioActivity
        cardioDistanceKm = f.cardioDistanceKm
        cardioDurH = f.cardioDurH
        cardioDurM = f.cardioDurM
        cardioDurS = f.cardioDurS
        cardioDurationSecFallback = f.cardioDurationSecFallback
        didEditCardioDuration = f.didEditCardioDuration
        didEditSportDuration = f.didEditSportDuration
        cardioAvgHr = f.cardioAvgHr
        cardioMaxHr = f.cardioMaxHr
        cardioAvgPaceSecPerKm = f.cardioAvgPaceSecPerKm
        cardioElevationGainM = f.cardioElevationGainM
        sportType = f.sportType
        footballPosition = f.footballPosition
        racketMode = f.racketMode
        racketFormat = f.racketFormat
        sportDurationMin = f.sportDurationMin
        sportScoreFor = f.sportScoreFor
        sportScoreAgainst = f.sportScoreAgainst
        sportMatchScoreText = f.sportMatchScoreText
        sportLocation = f.sportLocation
        sportSessionNotes = f.sportSessionNotes
        sportMatchResult = f.sportMatchResult
        hyroxExercisesJson = f.hyroxExercisesJson
        cardioStats.clear()
        f.cardioStats.forEach { (k, v) -> cardioStats[k] = v }
        sportStats.clear()
        f.sportStats.forEach { (k, v) -> sportStats[k] = v }
        vm.applyDuplicateFromDetail(payload)
    }
    LaunchedEffect(strengthExercisePickTarget) {
        if (strengthExercisePickTarget != null) {
            vm.onExercisePickerOpened()
        }
    }
    LaunchedEffect(showRoutinesSheet) {
        if (showRoutinesSheet) vm.loadStrengthRoutines()
    }
    LaunchedEffect(showHyroxRoutinesSheet) {
        if (showHyroxRoutinesSheet) vm.loadHyroxRoutines()
    }
    LaunchedEffect(ui.pendingHyroxApply) {
        val draft = ui.pendingHyroxApply ?: return@LaunchedEffect
        hyroxExercisesJson = draft.exercisesJson
        draft.sportStatsOverlay.forEach { (k, v) -> sportStats[k] = v }
        vm.consumePendingHyroxApply()
    }
    LaunchedEffect(sportType) {
        if (sportType != AddSportType.HYROX) {
            createHyroxRoutineEnabled = false
            newHyroxRoutineName = ""
            newHyroxRoutineFolderId = null
        }
    }
    LaunchedEffect(createHyroxRoutineEnabled) {
        if (!createHyroxRoutineEnabled) {
            newHyroxRoutineName = ""
            newHyroxRoutineFolderId = null
        } else {
            vm.loadHyroxRoutines()
        }
    }

    val scheduleDurationMin: Int? = remember(startedAtIsoText, endedAtIsoText, scheduleEndedEnabled) {
        if (!scheduleEndedEnabled) return@remember null
        val st = runCatching { Instant.parse(startedAtIsoText.trim()) }.getOrNull() ?: return@remember null
        val en = runCatching { Instant.parse(endedAtIsoText.trim()) }.getOrNull() ?: return@remember null
        if (!en.isAfter(st)) return@remember null
        ((en.epochSecond - st.epochSecond) / 60).toInt().coerceAtLeast(1)
    }

    val cardioDurationSecComputed = addHmsToTotalSecOrNull(cardioDurH, cardioDurM, cardioDurS)
        ?: cardioDurationSecFallback.trim().toIntOrNull()
    val cardioPaceAutoSecPerKm = addCardioAutoPaceSecPerKm(cardioDistanceKm, cardioDurationSecComputed)

    LaunchedEffect(
        scheduleEndedEnabled,
        startedAtIsoText,
        endedAtIsoText,
        selectedKind
    ) {
        if (!scheduleEndedEnabled) return@LaunchedEffect
        val st = startedAtIsoText.trim()
        val en = endedAtIsoText.trim()
        if (st.isEmpty() || en.isEmpty()) return@LaunchedEffect
        val start = runCatching { Instant.parse(st) }.getOrNull() ?: return@LaunchedEffect
        val end = runCatching { Instant.parse(en) }.getOrNull() ?: return@LaunchedEffect
        if (!end.isAfter(start)) return@LaunchedEffect
        val totalSec = (end.epochSecond - start.epochSecond).toInt()
        if (totalSec <= 0) return@LaunchedEffect
        when (selectedKind) {
            AddWorkoutKind.CARDIO -> {
                if (didEditCardioDuration) return@LaunchedEffect
                val h = totalSec / 3600
                val m = (totalSec % 3600) / 60
                val s = totalSec % 60
                cardioDurH = if (h == 0) "" else h.toString()
                cardioDurM = m.toString()
                cardioDurS = s.toString()
            }
            AddWorkoutKind.SPORT -> {
                if (didEditSportDuration) return@LaunchedEffect
                sportDurationMin = (totalSec / 60).coerceAtLeast(1).toString()
            }
            else -> Unit
        }
    }

    val showRoutinesToolbarAction =
        selectedKind == AddWorkoutKind.STRENGTH ||
            (selectedKind == AddWorkoutKind.SPORT && sportType == AddSportType.HYROX)
    Box(modifier = modifier.fillMaxSize()) {
    if (showRoutinesToolbarAction) {
        IconButton(
            onClick = {
                when {
                    selectedKind == AddWorkoutKind.STRENGTH -> showRoutinesSheet = true
                    else -> showHyroxRoutinesSheet = true
                }
            },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(4.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.Layers,
                contentDescription = stringResource(R.string.add_routines_action_content_description)
            )
        }
    }
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp)
            .padding(
                top = if (showRoutinesToolbarAction) 44.dp else 8.dp
            ),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (ui.error != null) {
            item {
                Text(
                    text = ui.error ?: "",
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
        if (ui.message != null) {
            item {
                Text(
                    text = ui.message ?: "",
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                AddSectionHeader("GENERAL")
                IconButton(
                    onClick = { showWorkoutHelp = true }
                ) {
                    Icon(
                        imageVector = Icons.Filled.Info,
                        contentDescription = stringResource(R.string.workout_help_info_content_description)
                    )
                }
            }
        }
        item {
            AddWorkoutGeneralCard(
                selectedKind = selectedKind,
                onKindChange = { k -> selectedKind = k; vm.clearStatus() },
                selectedState = selectedState,
                onStateChange = { s -> selectedState = s; vm.clearStatus() },
                title = title,
                onTitleChange = { title = it; vm.clearStatus() },
                startedAtIsoText = startedAtIsoText,
                onStartedAtChange = { startedAtIsoText = it; vm.clearStatus() },
                scheduleEndedEnabled = scheduleEndedEnabled,
                onScheduleEndedChange = { scheduleEndedEnabled = it; vm.clearStatus() },
                endedAtIsoText = endedAtIsoText,
                onEndedAtChange = { endedAtIsoText = it; vm.clearStatus() },
                scheduleDurationMin = scheduleDurationMin,
                notes = notes,
                onNotesChange = { notes = it; vm.clearStatus() },
                selectedIntensity = selectedIntensity,
                onIntensityChange = { i -> selectedIntensity = i; vm.clearStatus() }
            )
        }
        item {
            AddSectionHeader(stringResource(R.string.add_participants_label).uppercase())
        }
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    when {
                        ui.loadingFollowees -> {
                            Text(
                                text = stringResource(R.string.add_participants_loading),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        ui.selectedParticipantIds.isEmpty() && !ui.loadingFollowees -> {
                            Text(
                                text = stringResource(R.string.add_participants_none),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        else -> {
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                val selected = ui.selectedParticipantIds.toList()
                                selected.forEach { uid ->
                                    val label = ui.followees.firstOrNull { it.userId == uid }?.username ?: uid
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text(
                                            text = label,
                                            style = MaterialTheme.typography.bodyLarge,
                                            modifier = Modifier.weight(1f)
                                        )
                                        TextButton(
                                            onClick = { vm.toggleParticipant(uid) }
                                        ) { Text("✕") }
                                    }
                                }
                            }
                        }
                    }
                    TextButton(
                        onClick = { showParticipantsSheet = true },
                        enabled = !ui.loadingFollowees && ui.followees.isNotEmpty()
                    ) {
                        Text(stringResource(R.string.add_participants_add))
                    }
                    if (!ui.loadingFollowees && ui.followees.isEmpty()) {
                        Text(
                            text = stringResource(R.string.add_participants_empty),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
        if (selectedKind == AddWorkoutKind.STRENGTH && ui.selectedParticipantIds.isNotEmpty()) {
            item { AddSectionHeader(stringResource(R.string.add_group_programming_label).uppercase()) }
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        SegmentedButton(
                            selected = !ui.perPersonStrength,
                            onClick = { vm.setPerPersonStrength(false) },
                            shape = SegmentedButtonDefaults.itemShape(0, 2)
                        ) { Text(stringResource(R.string.add_group_shared)) }
                        SegmentedButton(
                            selected = ui.perPersonStrength,
                            onClick = { vm.setPerPersonStrength(true) },
                            shape = SegmentedButtonDefaults.itemShape(1, 2)
                        ) { Text(stringResource(R.string.add_group_per_person)) }
                    }
                    if (!ui.perPersonStrength) {
                        Text(
                            text = stringResource(R.string.add_group_same_session_linked_hint),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
        if (selectedKind == AddWorkoutKind.STRENGTH) {
            item {
                AddSectionHeader("EXERCISES")
            }
            if (ui.perPersonStrength && laneOwners.isNotEmpty()) {
                item {
                    Text(
                        text = stringResource(R.string.add_per_person_lane_label),
                        style = MaterialTheme.typography.titleSmall
                    )
                }
                item {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(laneOwners, key = { it }) { ownerId ->
                            val plabel = if (ownerId == ui.currentUserId) {
                                stringResource(R.string.add_per_person_lane_me)
                            } else {
                                ui.followees.firstOrNull { it.userId == ownerId }?.username ?: ownerId
                            }
                            FilterChip(
                                selected = ui.activeLaneUserId == ownerId,
                                onClick = { vm.setActiveLane(ownerId) },
                                label = { Text(plabel) }
                            )
                        }
                    }
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = vm::copyHostLaneToActiveLane,
                            enabled = !ui.creating
                        ) {
                            Text(stringResource(R.string.add_per_person_copy_host))
                        }
                        Button(
                            onClick = vm::clearActiveLane,
                            enabled = !ui.creating
                        ) {
                            Text(stringResource(R.string.add_per_person_clear_lane))
                        }
                    }
                }
            }
            item {
                val canClearAllStrength = strengthExercises.size > 1 ||
                    strengthExercises.any { it.exerciseId != null || it.exerciseName.isNotBlank() }
                StrengthExerciseDraftsEditorBlock(
                    exercises = strengthExercises,
                    loadingExercises = ui.loadingExercises,
                    showQuickActions = true,
                    onRecommendClick = { showRecommend = true },
                    onPickExerciseClick = { draftId ->
                        strengthExercisePickTarget = StrengthExercisePickTarget.WorkoutForm(draftId)
                        exerciseSearch = ""
                    },
                    onUpdateCustomName = { id, v -> vm.updateExerciseCustomName(id, v) },
                    onUpdateNotes = { id, v -> vm.updateExerciseNotes(id, v) },
                    onBumpSetNumber = { e, s, d -> vm.bumpSetNumber(e, s, d) },
                    onRemoveSet = { e, s -> vm.removeSet(e, s) },
                    onUpdateSetReps = { e, s, v -> vm.updateSetReps(e, s, v) },
                    onUpdateSetWeight = { e, s, v -> vm.updateSetWeight(e, s, v) },
                    onUpdateSetRpe = { e, s, v -> vm.updateSetRpe(e, s, v) },
                    onUpdateSetRestSec = { e, s, v -> vm.updateSetRestSec(e, s, v) },
                    onAddSet = { vm.addSet(it) },
                    onMoveExerciseUp = { vm.moveExerciseUp(it) },
                    onMoveExerciseDown = { vm.moveExerciseDown(it) },
                    onRemoveExercise = { vm.removeExercise(it) },
                    onAddBlankExercise = { vm.addBlankStrengthExercise() },
                    onClearAllExercises = { showClearStrengthDialog = true },
                    showClearAllButton = canClearAllStrength
                )
            }
            item {
                Card(
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.padding(12.dp)
                    ) {
                        Text(
                            stringResource(R.string.add_section_routine_template),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(stringResource(R.string.add_create_routine_toggle), style = MaterialTheme.typography.bodyLarge)
                            Switch(
                                checked = createRoutineEnabled,
                                onCheckedChange = { createRoutineEnabled = it }
                            )
                        }
                        if (createRoutineEnabled) {
                            OutlinedTextField(
                                value = newStrengthRoutineName,
                                onValueChange = { newStrengthRoutineName = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.add_routine_name_create_label)) },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                            ExposedDropdownMenuBox(
                                expanded = folderMenuExpanded,
                                onExpandedChange = { folderMenuExpanded = it }
                            ) {
                                val folderLabel = newStrengthTemplateFolderId?.let { id ->
                                    ui.routineFolders.firstOrNull { it.id == id }?.name
                                } ?: stringResource(R.string.add_routine_folder_none)
                                OutlinedTextField(
                                    value = folderLabel,
                                    onValueChange = {},
                                    readOnly = true,
                                    label = { Text(stringResource(R.string.add_routine_folder_label)) },
                                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = folderMenuExpanded) },
                                    modifier = Modifier
                                        .menuAnchor(
                                            type = MenuAnchorType.PrimaryNotEditable,
                                            enabled = true
                                        )
                                        .fillMaxWidth()
                                )
                                ExposedDropdownMenu(
                                    expanded = folderMenuExpanded,
                                    onDismissRequest = { folderMenuExpanded = false }
                                ) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.add_routine_folder_none)) },
                                        onClick = {
                                            newStrengthTemplateFolderId = null
                                            folderMenuExpanded = false
                                        }
                                    )
                                    ui.routineFolders.forEach { folder ->
                                        DropdownMenuItem(
                                            text = { Text(folder.name) },
                                            onClick = {
                                                newStrengthTemplateFolderId = folder.id
                                                folderMenuExpanded = false
                                            }
                                        )
                                    }
                                }
                            }
                            Button(
                                onClick = {
                                    vm.saveCurrentAsRoutine(
                                        newStrengthRoutineName,
                                        newStrengthTemplateFolderId
                                    )
                                },
                                enabled = canSaveRoutineOnly && !ui.savingRoutine,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    if (ui.savingRoutine) {
                                        stringResource(R.string.add_routine_saving)
                                    } else {
                                        stringResource(R.string.add_routine_save_without_workout)
                                    }
                                )
                            }
                            if (ui.perPersonStrength) {
                                Text(
                                    stringResource(R.string.add_routine_per_person_hint),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
        if (selectedKind == AddWorkoutKind.CARDIO) {
            item {
                AddSectionHeader("CARDIO")
            }
            item {
                AddSuggestNextSessionRow(onClick = { showRecommend = true })
            }
            item { Text(stringResource(R.string.add_cardio_activity_label), style = MaterialTheme.typography.titleSmall) }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(AddCardioActivity.values()) { activity ->
                        FilterChip(
                            selected = cardioActivity == activity,
                            onClick = { cardioActivity = activity },
                            label = { Text(activity.wire) }
                        )
                    }
                }
            }
            item {
                OutlinedTextField(
                    value = cardioDistanceKm,
                    onValueChange = {
                        cardioDistanceKm = it
                        vm.clearStatus()
                    },
                    label = { Text(stringResource(R.string.add_cardio_distance_km_label)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = stringResource(R.string.add_cardio_duration_hms_caption),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OutlinedTextField(
                            value = cardioDurH,
                            onValueChange = {
                                didEditCardioDuration = true
                                cardioDurH = it
                                vm.clearStatus()
                            },
                            label = { Text(stringResource(R.string.add_cardio_duration_h_label)) },
                            singleLine = true,
                            modifier = Modifier.width(64.dp)
                        )
                        Text(":", style = MaterialTheme.typography.bodyLarge)
                        OutlinedTextField(
                            value = cardioDurM,
                            onValueChange = {
                                didEditCardioDuration = true
                                cardioDurM = it
                                vm.clearStatus()
                            },
                            label = { Text(stringResource(R.string.add_cardio_duration_m_label)) },
                            singleLine = true,
                            modifier = Modifier.width(64.dp)
                        )
                        Text(":", style = MaterialTheme.typography.bodyLarge)
                        OutlinedTextField(
                            value = cardioDurS,
                            onValueChange = {
                                didEditCardioDuration = true
                                cardioDurS = it
                                vm.clearStatus()
                            },
                            label = { Text(stringResource(R.string.add_cardio_duration_s_label)) },
                            singleLine = true,
                            modifier = Modifier.width(64.dp)
                        )
                    }
                }
            }
            item {
                OutlinedTextField(
                    value = cardioDurationSecFallback,
                    onValueChange = {
                        didEditCardioDuration = true
                        cardioDurationSecFallback = it
                        vm.clearStatus()
                    },
                    label = { Text(stringResource(R.string.add_cardio_duration_total_sec_fallback)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = cardioAvgHr,
                        onValueChange = {
                            cardioAvgHr = it
                            vm.clearStatus()
                        },
                        label = { Text(stringResource(R.string.add_cardio_avg_hr_label)) },
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                    OutlinedTextField(
                        value = cardioMaxHr,
                        onValueChange = {
                            cardioMaxHr = it
                            vm.clearStatus()
                        },
                        label = { Text(stringResource(R.string.add_cardio_max_hr_label)) },
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
            item {
                if (cardioActivity.showsElevation) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                text = stringResource(R.string.add_cardio_pace_computed),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            val paceLabel = cardioPaceAutoSecPerKm?.let { addFormatPaceMinSecPerKm(it) }
                                ?: stringResource(R.string.add_cardio_pace_none)
                            Text(
                                text = paceLabel,
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                        }
                        OutlinedTextField(
                            value = cardioElevationGainM,
                            onValueChange = {
                                cardioElevationGainM = it
                                vm.clearStatus()
                            },
                            label = { Text(stringResource(R.string.add_cardio_elevation_m_label)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            text = stringResource(R.string.add_cardio_pace_computed),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        val paceLabel = cardioPaceAutoSecPerKm?.let { addFormatPaceMinSecPerKm(it) }
                            ?: stringResource(R.string.add_cardio_pace_none)
                        Text(
                            text = paceLabel,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }
            item {
                OutlinedTextField(
                    value = cardioAvgPaceSecPerKm,
                    onValueChange = {
                        cardioAvgPaceSecPerKm = it
                        vm.clearStatus()
                    },
                    label = { Text(stringResource(R.string.add_cardio_avg_pace_sec_label)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            if (cardioActivity.showsCadenceRpm || cardioActivity.showsWatts) {
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (cardioActivity.showsCadenceRpm) {
                            OutlinedTextField(
                                value = cardioStats["cadence_rpm"] ?: "",
                                onValueChange = { cardioStats["cadence_rpm"] = it },
                                label = { Text(stringResource(R.string.add_cardio_cadence_rpm_label)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                        }
                        if (cardioActivity.showsWatts) {
                            OutlinedTextField(
                                value = cardioStats["watts_avg"] ?: "",
                                onValueChange = { cardioStats["watts_avg"] = it },
                                label = { Text(stringResource(R.string.add_cardio_watts_avg_label)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
            }
            if (cardioActivity.showsIncline) {
                item {
                    OutlinedTextField(
                        value = cardioStats["incline_pct"] ?: "",
                        onValueChange = { cardioStats["incline_pct"] = it },
                        label = { Text(stringResource(R.string.add_cardio_incline_pct_label)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
            if (cardioActivity.showsSplit500m) {
                item {
                    OutlinedTextField(
                        value = cardioStats["split_sec_per_500m"] ?: "",
                        onValueChange = { cardioStats["split_sec_per_500m"] = it },
                        label = { Text(stringResource(R.string.add_cardio_split_500m_label)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
            if (cardioActivity.showsSwimFields) {
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = cardioStats["swim_laps"] ?: "",
                            onValueChange = { cardioStats["swim_laps"] = it },
                            label = { Text(stringResource(R.string.add_cardio_swim_laps_label)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = cardioStats["pool_length_m"] ?: "",
                            onValueChange = { cardioStats["pool_length_m"] = it },
                            label = { Text(stringResource(R.string.add_cardio_pool_length_m_label)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
                item {
                    OutlinedTextField(
                        value = cardioStats["swim_style"] ?: "",
                        onValueChange = { cardioStats["swim_style"] = it },
                        label = { Text(stringResource(R.string.add_cardio_swim_style_label)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
            if (cardioActivity.showsKmPaceSplits) {
                item {
                    OutlinedTextField(
                        value = cardioStats["km_split_pace_sec"] ?: "",
                        onValueChange = { cardioStats["km_split_pace_sec"] = it },
                        label = { Text(stringResource(R.string.add_cardio_km_split_label)) },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                        maxLines = 4
                    )
                }
            }
        }
        if (selectedKind == AddWorkoutKind.SPORT) {
            item {
                AddSectionHeader("SPORT")
            }
            item {
                AddSuggestNextSessionRow(onClick = { showRecommend = true })
            }
            item { Text(stringResource(R.string.add_sport_type_label), style = MaterialTheme.typography.titleSmall) }
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(AddSportType.values()) { candidate ->
                        FilterChip(
                            selected = sportType == candidate,
                            onClick = { sportType = candidate },
                            label = { Text(candidate.wire) }
                        )
                    }
                }
            }
            item {
                OutlinedTextField(
                    value = sportDurationMin,
                    onValueChange = {
                        didEditSportDuration = true
                        sportDurationMin = it
                        vm.clearStatus()
                    },
                    label = { Text(stringResource(R.string.add_sport_duration_min_label)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = sportScoreFor, onValueChange = { sportScoreFor = it }, label = { Text(stringResource(R.string.add_sport_score_for_label)) }, singleLine = true, modifier = Modifier.weight(1f))
                    OutlinedTextField(value = sportScoreAgainst, onValueChange = { sportScoreAgainst = it }, label = { Text(stringResource(R.string.add_sport_score_against_label)) }, singleLine = true, modifier = Modifier.weight(1f))
                }
            }
            item {
                OutlinedTextField(value = sportMatchScoreText, onValueChange = { sportMatchScoreText = it }, label = { Text(stringResource(R.string.add_sport_match_score_label)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            }
            item {
                OutlinedTextField(value = sportLocation, onValueChange = { sportLocation = it }, label = { Text(stringResource(R.string.add_sport_location_label)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            }
            item {
                OutlinedTextField(value = sportSessionNotes, onValueChange = { sportSessionNotes = it }, label = { Text(stringResource(R.string.add_sport_session_notes_label)) }, modifier = Modifier.fillMaxWidth(), minLines = 2, maxLines = 4)
            }
            if (sportType != AddSportType.SKI) {
                item { Text(stringResource(R.string.add_sport_match_result_label), style = MaterialTheme.typography.titleSmall) }
                item {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(AddMatchResult.values()) { candidate ->
                            FilterChip(
                                selected = sportMatchResult == candidate,
                                onClick = { sportMatchResult = candidate },
                                label = { Text(candidate.wire) }
                            )
                        }
                    }
                }
            }
            when (sportType) {
                AddSportType.FOOTBALL -> {
                    item { Text(stringResource(R.string.add_sport_football_position_label), style = MaterialTheme.typography.titleSmall) }
                    item {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(AddFootballPosition.values()) { pos ->
                                FilterChip(
                                    selected = footballPosition == pos,
                                    onClick = { footballPosition = pos },
                                    label = { Text(pos.wire) }
                                )
                            }
                        }
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(value = sportStats["assists"] ?: "", onValueChange = { sportStats["assists"] = it }, label = { Text(stringResource(R.string.add_stat_assists)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["shots_on_target"] ?: "", onValueChange = { sportStats["shots_on_target"] = it }, label = { Text(stringResource(R.string.add_stat_shots_on_target)) }, singleLine = true, modifier = Modifier.weight(1f))
                        }
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(value = sportStats["passes_completed"] ?: "", onValueChange = { sportStats["passes_completed"] = it }, label = { Text(stringResource(R.string.add_stat_passes_completed)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["tackles"] ?: "", onValueChange = { sportStats["tackles"] = it }, label = { Text(stringResource(R.string.add_stat_tackles)) }, singleLine = true, modifier = Modifier.weight(1f))
                        }
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(value = sportStats["saves"] ?: "", onValueChange = { sportStats["saves"] = it }, label = { Text(stringResource(R.string.add_stat_saves)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["yellow_cards"] ?: "", onValueChange = { sportStats["yellow_cards"] = it }, label = { Text(stringResource(R.string.add_stat_yellow_cards)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["red_cards"] ?: "", onValueChange = { sportStats["red_cards"] = it }, label = { Text(stringResource(R.string.add_stat_red_cards)) }, singleLine = true, modifier = Modifier.weight(1f))
                        }
                    }
                }
                AddSportType.BASKETBALL -> {
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(value = sportStats["points"] ?: "", onValueChange = { sportStats["points"] = it }, label = { Text(stringResource(R.string.add_stat_points)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["rebounds"] ?: "", onValueChange = { sportStats["rebounds"] = it }, label = { Text(stringResource(R.string.add_stat_rebounds)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["assists"] ?: "", onValueChange = { sportStats["assists"] = it }, label = { Text(stringResource(R.string.add_stat_assists)) }, singleLine = true, modifier = Modifier.weight(1f))
                        }
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(value = sportStats["steals"] ?: "", onValueChange = { sportStats["steals"] = it }, label = { Text(stringResource(R.string.add_stat_steals)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["blocks"] ?: "", onValueChange = { sportStats["blocks"] = it }, label = { Text(stringResource(R.string.add_stat_blocks)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["turnovers"] ?: "", onValueChange = { sportStats["turnovers"] = it }, label = { Text(stringResource(R.string.add_stat_turnovers)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["fouls"] ?: "", onValueChange = { sportStats["fouls"] = it }, label = { Text(stringResource(R.string.add_stat_fouls)) }, singleLine = true, modifier = Modifier.weight(1f))
                        }
                    }
                }
                AddSportType.PADEL, AddSportType.TENNIS, AddSportType.BADMINTON, AddSportType.SQUASH, AddSportType.TABLE_TENNIS -> {
                    item { Text(stringResource(R.string.add_sport_racket_mode_label), style = MaterialTheme.typography.titleSmall) }
                    item {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(AddRacketMode.values()) { mode ->
                                FilterChip(selected = racketMode == mode, onClick = { racketMode = mode }, label = { Text(mode.wire) })
                            }
                        }
                    }
                    item { Text(stringResource(R.string.add_sport_racket_format_label), style = MaterialTheme.typography.titleSmall) }
                    item {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(AddRacketFormat.values()) { format ->
                                FilterChip(selected = racketFormat == format, onClick = { racketFormat = format }, label = { Text(format.wire) })
                            }
                        }
                    }
                    item {
                        OutlinedTextField(
                            value = sportStats["racket_stats_raw"] ?: "",
                            onValueChange = { sportStats["racket_stats_raw"] = it },
                            label = { Text(stringResource(R.string.add_sport_racket_stats_raw_label)) },
                            modifier = Modifier.fillMaxWidth(),
                            minLines = 3,
                            maxLines = 6
                        )
                    }
                }
                AddSportType.VOLLEYBALL -> {
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(value = sportStats["points"] ?: "", onValueChange = { sportStats["points"] = it }, label = { Text(stringResource(R.string.add_stat_points)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["aces"] ?: "", onValueChange = { sportStats["aces"] = it }, label = { Text(stringResource(R.string.add_stat_aces)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["blocks"] ?: "", onValueChange = { sportStats["blocks"] = it }, label = { Text(stringResource(R.string.add_stat_blocks)) }, singleLine = true, modifier = Modifier.weight(1f))
                            OutlinedTextField(value = sportStats["digs"] ?: "", onValueChange = { sportStats["digs"] = it }, label = { Text(stringResource(R.string.add_stat_digs)) }, singleLine = true, modifier = Modifier.weight(1f))
                        }
                    }
                }
                AddSportType.HYROX -> {
                    item {
                        Text(
                            stringResource(R.string.workout_detail_hyrox_stats_title),
                            style = MaterialTheme.typography.titleSmall
                        )
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = sportStats["division"] ?: "",
                                onValueChange = { sportStats["division"] = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.workout_detail_hyrox_division)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = sportStats["category"] ?: "",
                                onValueChange = { sportStats["category"] = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.workout_detail_hyrox_category)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                    item {
                        OutlinedTextField(
                            value = sportStats["age_group"] ?: "",
                            onValueChange = { sportStats["age_group"] = it; vm.clearStatus() },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_age_group)) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = sportStats["official_time_sec"] ?: "",
                                onValueChange = { sportStats["official_time_sec"] = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.workout_detail_hyrox_official_time)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = sportStats["penalty_time_sec"] ?: "",
                                onValueChange = { sportStats["penalty_time_sec"] = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.workout_detail_hyrox_penalty_time)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = sportStats["no_reps"] ?: "",
                                onValueChange = { sportStats["no_reps"] = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.workout_detail_hyrox_no_reps)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = sportStats["rank_overall"] ?: "",
                                onValueChange = { sportStats["rank_overall"] = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.workout_detail_hyrox_rank_overall)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = sportStats["rank_category"] ?: "",
                                onValueChange = { sportStats["rank_category"] = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.workout_detail_hyrox_rank_category)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = sportStats["avg_hr"] ?: "",
                                onValueChange = { sportStats["avg_hr"] = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.workout_detail_hyrox_avg_hr)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = sportStats["max_hr"] ?: "",
                                onValueChange = { sportStats["max_hr"] = it; vm.clearStatus() },
                                label = { Text(stringResource(R.string.workout_detail_hyrox_max_hr)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                    item {
                        OutlinedTextField(
                            value = sportStats["raw_stats_json"] ?: "",
                            onValueChange = { sportStats["raw_stats_json"] = it },
                            label = { Text(stringResource(R.string.add_sport_raw_stats_json_label)) },
                            modifier = Modifier.fillMaxWidth(),
                            minLines = 4,
                            maxLines = 8
                        )
                    }
                    item {
                        OutlinedTextField(
                            value = hyroxExercisesJson,
                            onValueChange = { hyroxExercisesJson = it; vm.clearStatus() },
                            label = { Text(stringResource(R.string.add_sport_hyrox_exercises_json_label)) },
                            modifier = Modifier.fillMaxWidth(),
                            minLines = 4,
                            maxLines = 8
                        )
                    }
                    item {
                        val canClearAllHyrox =
                            hyroxExercisesJsonValid(hyroxExercisesJson) ||
                                hyroxExercisesJson.trim().isNotEmpty()
                        if (canClearAllHyrox) {
                            OutlinedButton(
                                onClick = { showClearHyroxDialog = true },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(stringResource(R.string.add_clear_all_exercises))
                            }
                        }
                    }
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                                modifier = Modifier.padding(12.dp)
                            ) {
                                Text(
                                    stringResource(R.string.add_section_routine_template),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        stringResource(R.string.add_create_routine_toggle),
                                        style = MaterialTheme.typography.bodyLarge
                                    )
                                    Switch(
                                        checked = createHyroxRoutineEnabled,
                                        onCheckedChange = { createHyroxRoutineEnabled = it; vm.clearStatus() }
                                    )
                                }
                                if (createHyroxRoutineEnabled) {
                                    OutlinedTextField(
                                        value = newHyroxRoutineName,
                                        onValueChange = { newHyroxRoutineName = it; vm.clearStatus() },
                                        label = { Text(stringResource(R.string.add_routine_name_create_label)) },
                                        singleLine = true,
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                    ExposedDropdownMenuBox(
                                        expanded = hyroxFolderMenuExpanded,
                                        onExpandedChange = { hyroxFolderMenuExpanded = it }
                                    ) {
                                        val hyroxFolderLabel = newHyroxRoutineFolderId?.let { id ->
                                            ui.hyroxRoutineFolders.firstOrNull { it.id == id }?.name
                                        } ?: stringResource(R.string.add_routine_folder_none)
                                        OutlinedTextField(
                                            value = hyroxFolderLabel,
                                            onValueChange = {},
                                            readOnly = true,
                                            label = { Text(stringResource(R.string.add_routine_folder_label)) },
                                            trailingIcon = {
                                                ExposedDropdownMenuDefaults.TrailingIcon(expanded = hyroxFolderMenuExpanded)
                                            },
                                            modifier = Modifier
                                                .menuAnchor(
                                                    type = MenuAnchorType.PrimaryNotEditable,
                                                    enabled = true
                                                )
                                                .fillMaxWidth()
                                        )
                                        ExposedDropdownMenu(
                                            expanded = hyroxFolderMenuExpanded,
                                            onDismissRequest = { hyroxFolderMenuExpanded = false }
                                        ) {
                                            DropdownMenuItem(
                                                text = { Text(stringResource(R.string.add_routine_folder_none)) },
                                                onClick = {
                                                    newHyroxRoutineFolderId = null
                                                    hyroxFolderMenuExpanded = false
                                                }
                                            )
                                            ui.hyroxRoutineFolders.forEach { folder ->
                                                DropdownMenuItem(
                                                    text = { Text(folder.name) },
                                                    onClick = {
                                                        newHyroxRoutineFolderId = folder.id
                                                        hyroxFolderMenuExpanded = false
                                                    }
                                                )
                                            }
                                        }
                                    }
                                    Button(
                                        onClick = {
                                            vm.saveCurrentAsHyroxRoutine(
                                                routineName = newHyroxRoutineName,
                                                folderId = newHyroxRoutineFolderId,
                                                durationMinText = sportDurationMin,
                                                sportStats = sportStats.toMap(),
                                                hyroxExercisesText = hyroxExercisesJson
                                            )
                                        },
                                        enabled = canSaveHyroxRoutineOnly && !ui.savingRoutine,
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        Text(
                                            if (ui.savingRoutine) {
                                                stringResource(R.string.add_routine_saving)
                                            } else {
                                                stringResource(R.string.add_routine_save_without_workout)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                AddSportType.HANDBALL, AddSportType.HOCKEY, AddSportType.RUGBY, AddSportType.SKI -> {
                    item {
                        OutlinedTextField(
                            value = sportStats["raw_stats_json"] ?: "",
                            onValueChange = { sportStats["raw_stats_json"] = it },
                            label = { Text(stringResource(R.string.add_sport_raw_stats_json_label)) },
                            modifier = Modifier.fillMaxWidth(),
                            minLines = 4,
                            maxLines = 8
                        )
                    }
                }
            }
        }
        item {
            Button(
                onClick = {
                    val scheduleStartIso = startedAtIsoText.trim().takeIf { it.isNotEmpty() }
                    val scheduleEndIso =
                        if (scheduleEndedEnabled) {
                            endedAtIsoText.trim().takeIf { it.isNotEmpty() }
                        } else {
                            null
                        }
                    when (selectedKind) {
                        AddWorkoutKind.STRENGTH -> {
                            val durationMin = scheduleDurationMin
                            vm.createStrengthWorkout(
                                title = title,
                                notes = notes,
                                durationMin = durationMin,
                                intensity = selectedIntensity,
                                state = selectedState,
                                startedAtIso = scheduleStartIso,
                                endedAtIso = scheduleEndIso,
                                useCustomSchedule = true,
                                scheduleEndedEnabled = scheduleEndedEnabled
                            )
                        }
                        AddWorkoutKind.CARDIO -> {
                            val paceForRpc = cardioPaceAutoSecPerKm?.toString()
                                ?: cardioAvgPaceSecPerKm.trim()
                            vm.createCardioWorkout(
                                title = title,
                                notes = notes,
                                activity = cardioActivity,
                                distanceKmText = cardioDistanceKm,
                                durationSecText = cardioDurationSecComputed?.toString() ?: "",
                                avgHrText = cardioAvgHr,
                                maxHrText = cardioMaxHr,
                                avgPaceSecPerKmText = paceForRpc,
                                elevationGainMText = cardioElevationGainM,
                                cadenceRpmText = cardioStats["cadence_rpm"].orEmpty(),
                                wattsAvgText = cardioStats["watts_avg"].orEmpty(),
                                inclinePercentText = cardioStats["incline_pct"].orEmpty(),
                                swimLapsText = cardioStats["swim_laps"].orEmpty(),
                                poolLengthMText = cardioStats["pool_length_m"].orEmpty(),
                                swimStyleText = cardioStats["swim_style"].orEmpty(),
                                splitSecPer500mText = cardioStats["split_sec_per_500m"].orEmpty(),
                                kmSplitsPaceText = cardioStats["km_split_pace_sec"].orEmpty(),
                                intensity = selectedIntensity,
                                state = selectedState,
                                startedAtIso = scheduleStartIso,
                                endedAtIso = scheduleEndIso,
                                useCustomSchedule = true,
                                scheduleEndedEnabled = scheduleEndedEnabled
                            )
                        }
                        AddWorkoutKind.SPORT -> {
                            vm.createSportWorkout(
                                title = title,
                                notes = notes,
                                sport = sportType,
                                durationMinText = sportDurationMin,
                                scoreForText = sportScoreFor,
                                scoreAgainstText = sportScoreAgainst,
                                matchScoreText = sportMatchScoreText,
                                location = sportLocation,
                                sessionNotes = sportSessionNotes,
                                matchResult = sportMatchResult,
                                footballPosition = footballPosition,
                                racketMode = racketMode,
                                racketFormat = racketFormat,
                                sportStats = sportStats,
                                hyroxExercisesText = hyroxExercisesJson,
                                intensity = selectedIntensity,
                                state = selectedState,
                                startedAtIso = scheduleStartIso,
                                endedAtIso = scheduleEndIso,
                                useCustomSchedule = true,
                                scheduleEndedEnabled = scheduleEndedEnabled,
                                saveHyroxRoutineTemplate = sportType == AddSportType.HYROX && createHyroxRoutineEnabled,
                                hyroxRoutineName = newHyroxRoutineName,
                                hyroxRoutineFolderId = newHyroxRoutineFolderId
                            )
                        }
                    }
                },
                enabled = canSave && !ui.creating,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp)
            ) {
                Text(
                    if (ui.creating) {
                        stringResource(R.string.add_creating)
                    } else {
                        stringResource(R.string.add_save)
                    }
                )
            }
        }
    }
    }
    ui.strengthRoutineOverwritePending?.let { pend ->
        StrengthRoutineOverwriteBottomSheet(
            prompt = pend.prompt,
            onDismissRequest = { vm.dismissStrengthRoutineOverwrite() },
            onOverwriteTemplate = { vm.confirmStrengthRoutineOverwrite(true) },
            onNotNow = { vm.confirmStrengthRoutineOverwrite(false) }
        )
    }
    if (showClearStrengthDialog) {
        AlertDialog(
            onDismissRequest = { showClearStrengthDialog = false },
            title = { Text(stringResource(R.string.add_clear_all_exercises)) },
            text = { Text(stringResource(R.string.add_clear_all_exercises_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showClearStrengthDialog = false
                        vm.clearAllStrengthExercises()
                    }
                ) {
                    Text(stringResource(R.string.add_clear_all_exercises_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearStrengthDialog = false }) {
                    Text(stringResource(R.string.add_routine_dialog_cancel))
                }
            }
        )
    }
    if (showClearHyroxDialog) {
        AlertDialog(
            onDismissRequest = { showClearHyroxDialog = false },
            title = { Text(stringResource(R.string.add_clear_all_hyrox_stations_title)) },
            text = { Text(stringResource(R.string.add_clear_all_hyrox_stations_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showClearHyroxDialog = false
                        hyroxExercisesJson = "[]"
                        vm.clearStatus()
                    }
                ) {
                    Text(stringResource(R.string.add_clear_all_exercises_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearHyroxDialog = false }) {
                    Text(stringResource(R.string.add_routine_dialog_cancel))
                }
            }
        )
    }
    if (showRoutinesSheet) {
        ModalBottomSheet(
            onDismissRequest = { showRoutinesSheet = false },
            sheetState = routinesSheetState
        ) {
            AddStrengthRoutinesSheetContent(
                ui = ui,
                onClose = { showRoutinesSheet = false },
                onReload = vm::loadStrengthRoutines,
                onCreateFolder = { name -> vm.createRoutineFolder(name) },
                onRenameFolder = { id, name -> vm.renameRoutineFolder(id, name) },
                onMoveFolder = { id, d -> vm.moveRoutineFolder(id, d) },
                onDeleteFolder = { id -> vm.deleteRoutineFolder(id) },
                onRenameRoutine = { id, name -> vm.renameRoutine(id, name) },
                onDuplicateRoutine = { sourceId, name, folderId ->
                    vm.duplicateStrengthRoutine(sourceId, name, folderId)
                },
                onMoveRoutine = { id, d -> vm.moveRoutine(id, d) },
                onMoveRoutineToFolder = { id, folderId -> vm.moveRoutineToFolder(id, folderId) },
                onDeleteRoutine = { id -> vm.deleteRoutine(id) },
                onPreviewRoutine = { id ->
                    exerciseLangScope.launch {
                        runCatching { vm.buildStrengthRoutineShareSnapshotForChat(id) }
                            .onSuccess { snap ->
                                routinePreviewSnapshot = snap
                                showRoutinePreviewSheet = true
                            }
                            .onFailure { e ->
                                routineShareError = e.message
                            }
                    }
                },
                onApplyRoutine = { id ->
                    vm.applyRoutine(id)
                    showRoutinesSheet = false
                },
                onShareRoutine = { id ->
                    exerciseLangScope.launch {
                        runCatching { vm.buildStrengthRoutineShareSnapshotForChat(id) }
                            .onSuccess { snap ->
                                routineShareSnapshot = snap
                                showShareRoutineSheet = true
                                showRoutinesSheet = false
                            }
                            .onFailure { e ->
                                routineShareError = e.message
                            }
                    }
                },
                onEditRoutine = { id, name -> vm.loadRoutineForEdit(id, name) }
            )
        }
    }
    ui.strengthRoutineTemplateEdit?.let { edit ->
        ModalBottomSheet(
            onDismissRequest = {
                if (!edit.saving) vm.dismissRoutineTemplateEdit()
            },
            sheetState = templateEditSheetState
        ) {
            EditStrengthRoutineTemplateSheetContent(
                edit = edit,
                loadingExercises = ui.loadingExercises,
                vm = vm,
                onRequestExercisePick = { draftId ->
                    strengthExercisePickTarget = StrengthExercisePickTarget.RoutineTemplate(draftId)
                    exerciseSearch = ""
                },
                onDismiss = { vm.dismissRoutineTemplateEdit() }
            )
        }
    }
    if (showHyroxRoutinesSheet) {
        ModalBottomSheet(
            onDismissRequest = { showHyroxRoutinesSheet = false },
            sheetState = hyroxRoutinesSheetState
        ) {
            AddHyroxRoutinesSheetContent(
                ui = ui,
                onClose = { showHyroxRoutinesSheet = false },
                onReload = vm::loadHyroxRoutines,
                onCreateFolder = { name -> vm.createHyroxRoutineFolder(name) },
                onRenameFolder = { id, name -> vm.renameHyroxRoutineFolder(id, name) },
                onMoveFolder = { id, d -> vm.moveHyroxRoutineFolder(id, d) },
                onDeleteFolder = { id -> vm.deleteHyroxRoutineFolder(id) },
                onRenameRoutine = { id, name -> vm.renameHyroxRoutine(id, name) },
                onDuplicateRoutine = { sourceId, name, folderId ->
                    vm.duplicateHyroxRoutine(sourceId, name, folderId)
                },
                onMoveRoutine = { id, d -> vm.moveHyroxRoutine(id, d) },
                onMoveRoutineToFolder = { id, folderId -> vm.moveHyroxRoutineToFolder(id, folderId) },
                onDeleteRoutine = { id -> vm.deleteHyroxRoutine(id) },
                onPreviewRoutine = { id ->
                    exerciseLangScope.launch {
                        runCatching { vm.buildHyroxRoutineShareSnapshotForChat(id) }
                            .onSuccess { snap ->
                                routinePreviewSnapshot = snap
                                showRoutinePreviewSheet = true
                            }
                            .onFailure { e ->
                                routineShareError = e.message
                            }
                    }
                },
                onApplyRoutine = { id ->
                    vm.applyHyroxRoutine(id)
                    showHyroxRoutinesSheet = false
                },
                onShareRoutine = { id ->
                    exerciseLangScope.launch {
                        runCatching { vm.buildHyroxRoutineShareSnapshotForChat(id) }
                            .onSuccess { snap ->
                                routineShareSnapshot = snap
                                showShareRoutineSheet = true
                                showHyroxRoutinesSheet = false
                            }
                            .onFailure { e ->
                                routineShareError = e.message
                            }
                    }
                }
            )
        }
    }

    if (showRoutinePreviewSheet && routinePreviewSnapshot != null) {
        ModalBottomSheet(
            onDismissRequest = {
                showRoutinePreviewSheet = false
                routinePreviewSnapshot = null
            },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            Box(Modifier.fillMaxSize()) {
                SharedRoutineFromChatScreen(
                    supabase = supabase,
                    snapshot = routinePreviewSnapshot!!,
                    onBack = {
                        showRoutinePreviewSheet = false
                        routinePreviewSnapshot = null
                    },
                    topBarActions = {
                        IconButton(onClick = {
                            showRoutinePreviewSheet = false
                            routinePreviewSnapshot = null
                        }) {
                            Icon(Icons.Filled.Close, contentDescription = null)
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }
    if (showShareRoutineSheet && routineShareSnapshot != null) {
        ModalBottomSheet(
            onDismissRequest = {
                showShareRoutineSheet = false
                routineShareSnapshot = null
            },
            sheetState = shareRoutineSheetState
        ) {
            ShareRoutineToChatSheetContent(
                supabase = supabase,
                snapshot = routineShareSnapshot!!,
                onDone = {
                    showShareRoutineSheet = false
                    routineShareSnapshot = null
                },
                modifier = Modifier.fillMaxSize()
            )
        }
    }
    routineShareError?.let { err ->
        AlertDialog(
            onDismissRequest = { routineShareError = null },
            title = { Text(stringResource(R.string.share_routine_error_title)) },
            text = { Text(err) },
            confirmButton = {
                TextButton(onClick = { routineShareError = null }) {
                    Text(stringResource(android.R.string.ok))
                }
            }
        )
    }
    if (showParticipantsSheet) {
        ModalBottomSheet(
            onDismissRequest = { showParticipantsSheet = false },
            sheetState = participantsSheetState
        ) {
            AddWorkoutParticipantsPickerContent(
                loading = ui.loadingFollowees,
                followees = ui.followees,
                searchQuery = participantsSearchQuery,
                onSearchQueryChange = { participantsSearchQuery = it },
                selectedIds = ui.selectedParticipantIds,
                onToggle = { userId -> vm.toggleParticipant(userId) },
                onDone = { showParticipantsSheet = false }
            )
        }
    }
    if (showWorkoutHelp) {
        ModalBottomSheet(
            onDismissRequest = { showWorkoutHelp = false },
            sheetState = workoutHelpSheetState
        ) {
            WorkoutHelpSheetContent(
                onClose = { showWorkoutHelp = false }
            )
        }
    }
    val strengthPick = strengthExercisePickTarget
    if (strengthPick != null) {
        ModalBottomSheet(
            onDismissRequest = { strengthExercisePickTarget = null; exerciseSearch = "" },
            sheetState = exerciseSheetState
        ) {
            Column(Modifier.padding(16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Box {
                        IconButton(
                            onClick = { languageMenuExpanded = true }
                        ) {
                            Text(
                                exerciseLang.uppercase(),
                                style = MaterialTheme.typography.labelLarge
                            )
                        }
                        DropdownMenu(
                            expanded = languageMenuExpanded,
                            onDismissRequest = { languageMenuExpanded = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.add_exercise_lang_es)) },
                                onClick = {
                                    exerciseLang = "es"
                                    languageMenuExpanded = false
                                    exerciseLangScope.launch(Dispatchers.IO) {
                                        ExerciseLanguagePreferences.set(app, "es")
                                    }
                                }
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.add_exercise_lang_en)) },
                                onClick = {
                                    exerciseLang = "en"
                                    languageMenuExpanded = false
                                    exerciseLangScope.launch(Dispatchers.IO) {
                                        ExerciseLanguagePreferences.set(app, "en")
                                    }
                                }
                            )
                        }
                    }
                    Box {
                        IconButton(onClick = { sortMenuExpanded = true }) {
                            Icon(
                                imageVector = Icons.Outlined.FilterList,
                                contentDescription = stringResource(R.string.add_exercise_sort_menu_content_description)
                            )
                        }
                        DropdownMenu(
                            expanded = sortMenuExpanded,
                            onDismissRequest = { sortMenuExpanded = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.add_exercise_sort_a_z)) },
                                onClick = {
                                    sortMenuExpanded = false
                                    vm.setExercisePickerSortMode(ExercisePickerSortMode.ALPHABETIC)
                                }
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.add_exercise_sort_most_used)) },
                                onClick = {
                                    sortMenuExpanded = false
                                    vm.setExercisePickerSortMode(ExercisePickerSortMode.MOST_USED)
                                }
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.add_exercise_sort_favorites)) },
                                onClick = {
                                    sortMenuExpanded = false
                                    vm.setExercisePickerSortMode(ExercisePickerSortMode.FAVORITES)
                                }
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.add_exercise_sort_recent)) },
                                onClick = {
                                    sortMenuExpanded = false
                                    vm.setExercisePickerSortMode(ExercisePickerSortMode.RECENT)
                                }
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = exerciseSearch,
                    onValueChange = { exerciseSearch = it },
                    label = { Text(stringResource(R.string.add_exercise_search_label)) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp)
                )
                if (ui.loadingExercises) {
                    Text(
                        stringResource(R.string.add_loading_exercises),
                        modifier = Modifier.padding(vertical = 8.dp)
                    )
                } else {
                    if (filteredExercises.isEmpty()) {
                        Text(
                            stringResource(R.string.add_exercise_search_empty),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 12.dp)
                        )
                    } else {
                        LazyColumn(Modifier.height(400.dp)) {
                            items(filteredExercises, key = { it.id }) { exRow ->
                                val title = exRow.localizedPickerName(exerciseLang)
                                val sub = exRow.pickerSubtitle()
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 8.dp, horizontal = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(
                                        Modifier
                                            .weight(1f)
                                            .clickable {
                                                when (strengthPick) {
                                                    is StrengthExercisePickTarget.WorkoutForm ->
                                                        vm.setExerciseOnDraft(strengthPick.draftId, exRow, exerciseLang)
                                                    is StrengthExercisePickTarget.RoutineTemplate ->
                                                        vm.templateEditSetExerciseOnDraft(
                                                            strengthPick.draftId,
                                                            exRow,
                                                            exerciseLang
                                                        )
                                                }
                                                strengthExercisePickTarget = null
                                                exerciseSearch = ""
                                            }
                                    ) {
                                        Text(
                                            title,
                                            style = MaterialTheme.typography.bodyLarge,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                        if (sub.isNotEmpty()) {
                                            Text(
                                                sub,
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                maxLines = 2,
                                                overflow = TextOverflow.Ellipsis
                                            )
                                        }
                                    }
                                    IconButton(
                                        onClick = { vm.toggleFavoriteExercise(exRow.id) }
                                    ) {
                                        Icon(
                                            imageVector = if (ui.favoriteExerciseIds.contains(exRow.id)) {
                                                Icons.Filled.Star
                                            } else {
                                                Icons.Outlined.StarOutline
                                            },
                                            contentDescription = stringResource(R.string.add_exercise_favorite_content_description)
                                        )
                                    }
                                }
                                HorizontalDivider()
                            }
                        }
                    }
                }
            }
        }
    }
    if (showRecommend) {
        AddWorkoutRecommendationDialog(
            kind = selectedKind,
            vm = vm,
            onDismiss = { showRecommend = false },
            onAppliedCardio = { r ->
                selectedKind = AddWorkoutKind.CARDIO
                applyCardioRecommendationToForm(
                    r = r,
                    setActivity = { cardioActivity = it },
                    setDurH = { cardioDurH = it },
                    setDurM = { cardioDurM = it },
                    setDurS = { cardioDurS = it },
                    setDurFallback = { cardioDurationSecFallback = it },
                    setDistance = { cardioDistanceKm = it },
                    setElev = { cardioElevationGainM = it },
                    setAvgHr = { cardioAvgHr = it },
                    setMaxHr = { cardioMaxHr = it },
                    setPace = { cardioAvgPaceSecPerKm = it },
                    setStat = { k, v -> if (v.isEmpty()) cardioStats.remove(k) else cardioStats[k] = v }
                )
            },
            onAppliedSport = { sr ->
                selectedKind = AddWorkoutKind.SPORT
                when (sr) {
                    is SportRecommendationResult.DurationOnly -> {
                        hyroxExercisesJson = ""
                        sportDurationMin = sr.durationMin.toString()
                        didEditSportDuration = true
                    }
                    is SportRecommendationResult.Hyrox -> {
                        sportType = AddSportType.HYROX
                        sportDurationMin = sr.durationMin.toString()
                        didEditSportDuration = true
                        hyroxExercisesJson = Json.encodeToString(
                            ListSerializer(HyroxExerciseRecommendationResult.serializer()),
                            sr.exercises
                        )
                    }
                }
            }
        )
    }
}

private fun ExerciseLite.localizedPickerName(lang: String): String = when (lang) {
    "en" -> nameEn ?: nameEs ?: name
    else -> nameEs ?: nameEn ?: name
}

private fun ExerciseLite.pickerSubtitle(): String =
    listOfNotNull(category, musclePrimary, equipment)
        .map { it.trim() }
        .filter { it.isNotEmpty() && !it.equals("strength", ignoreCase = true) }
        .joinToString(" · ")

private fun strengthExercisesFormValidForSave(exercises: List<StrengthExerciseDraft>): Boolean {
    if (exercises.isEmpty()) return false
    for (e in exercises) {
        if (e.exerciseId == null) return false
        val hasReps = e.sets.any { it.repsText.trim().toIntOrNull() != null }
        if (!hasReps) return false
    }
    return true
}

private fun hyroxExercisesJsonValid(hyroxExercisesJson: String): Boolean {
    val arr = runCatching { Json.parseToJsonElement(hyroxExercisesJson.trim()).jsonArray }
        .getOrNull()
    return arr != null && !arr.isEmpty()
}

private fun canSaveAddWorkout(
    kind: AddWorkoutKind,
    strengthExercises: List<StrengthExerciseDraft>,
    createRoutineEnabled: Boolean,
    newStrengthRoutineName: String,
    sportType: AddSportType,
    hyroxExercisesJson: String,
    createHyroxRoutineEnabled: Boolean = false,
    newHyroxRoutineName: String = ""
): Boolean = when (kind) {
    AddWorkoutKind.STRENGTH -> strengthExercisesFormValidForSave(strengthExercises) &&
        (!createRoutineEnabled || newStrengthRoutineName.trim().isNotEmpty())
    AddWorkoutKind.CARDIO -> true
    AddWorkoutKind.SPORT -> when (sportType) {
        AddSportType.HYROX ->
            hyroxExercisesJsonValid(hyroxExercisesJson) &&
                (!createHyroxRoutineEnabled || newHyroxRoutineName.trim().isNotEmpty())
        else -> true
    }
}

@Composable
private fun AddSectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun AddSuggestNextSessionRow(onClick: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = "QUICK ACTIONS",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            TextButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
                Text("✦ ${stringResource(R.string.add_recommend_button)}")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ParticipantsPillButton(
    text: String,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
            color = MaterialTheme.colorScheme.onPrimaryContainer
        )
    }
}

@Composable
private fun AddWorkoutParticipantsPickerContent(
    loading: Boolean,
    followees: List<ProfileLite>,
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    selectedIds: Set<String>,
    onToggle: (String) -> Unit,
    onDone: () -> Unit
) {
    val q = searchQuery.trim()
    val filtered = remember(followees, q) {
        if (q.isEmpty()) {
            followees
        } else {
            followees.filter { p ->
                (p.username ?: p.userId).lowercase().contains(q.lowercase())
            }
        }
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            ParticipantsPillButton(
                text = stringResource(R.string.add_participants_sheet_cancel),
                onClick = onDone
            )
            ParticipantsPillButton(
                text = stringResource(R.string.add_participants_sheet_confirm),
                onClick = onDone
            )
        }
        Text(
            text = stringResource(R.string.add_participants_picker_title),
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 14.dp, bottom = 8.dp)
        )
        OutlinedTextField(
            value = searchQuery,
            onValueChange = onSearchQueryChange,
            placeholder = { Text(stringResource(R.string.add_participants_search_placeholder)) },
            leadingIcon = {
                Icon(
                    imageVector = Icons.Filled.Search,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(22.dp)
        )
        when {
            loading -> {
                Text(
                    stringResource(R.string.add_participants_loading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 20.dp)
                )
            }
            followees.isEmpty() -> {
                Text(
                    stringResource(R.string.add_participants_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 20.dp)
                )
            }
            else -> {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp),
                    shape = RoundedCornerShape(16.dp),
                    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                ) {
                    if (filtered.isEmpty()) {
                        Text(
                            stringResource(R.string.add_participants_search_empty),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(20.dp)
                        )
                    } else {
                        LazyColumn(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(400.dp)
                        ) {
                            itemsIndexed(
                                items = filtered,
                                key = { _, p -> p.userId }
                            ) { index, p ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 12.dp, vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Row(
                                        modifier = Modifier
                                            .weight(1f)
                                            .padding(end = 4.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                                    ) {
                                        LiftrAvatar(
                                            imageUrl = p.avatarUrl,
                                            displayName = p.username,
                                            size = 44.dp
                                        )
                                        Text(
                                            text = p.username?.trim()
                                                .takeIf { it.orEmpty().isNotEmpty() } ?: p.userId,
                                            style = MaterialTheme.typography.bodyLarge,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                            modifier = Modifier.weight(1f, fill = true)
                                        )
                                    }
                                    Switch(
                                        checked = p.userId in selectedIds,
                                        onCheckedChange = { want ->
                                            val has = p.userId in selectedIds
                                            if (want != has) onToggle(p.userId)
                                        }
                                    )
                                }
                                if (index < filtered.lastIndex) {
                                    HorizontalDivider(
                                        modifier = Modifier.padding(start = 68.dp)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun applyCardioRecommendationToForm(
    r: CardioRecommendationResult,
    setActivity: (AddCardioActivity) -> Unit,
    setDurH: (String) -> Unit,
    setDurM: (String) -> Unit,
    setDurS: (String) -> Unit,
    setDurFallback: (String) -> Unit,
    setDistance: (String) -> Unit,
    setElev: (String) -> Unit,
    setAvgHr: (String) -> Unit,
    setMaxHr: (String) -> Unit,
    setPace: (String) -> Unit,
    setStat: (String, String) -> Unit
) {
    setActivity(
        AddCardioActivity.entries.firstOrNull { it.wire == r.activityWire }
            ?: AddCardioActivity.RUN
    )
    val t = r.durationSec.coerceAtLeast(0)
    setDurH(if (t >= 3600) (t / 3600).toString() else "")
    setDurM(((t % 3600) / 60).toString())
    setDurS((t % 60).toString())
    setDurFallback("")
    setDistance(
        r.distanceKm?.let { d ->
            if (d % 1.0 == 0.0) d.toInt().toString()
            else String.format(Locale.US, "%.2f", d)
        } ?: ""
    )
    setElev(r.elevationGainM?.toString() ?: "")
    setAvgHr(r.avgHr?.toString() ?: "")
    setMaxHr(r.maxHr?.toString() ?: "")
    setPace("")
    setStat("incline_pct", r.inclinePercent?.toString() ?: "")
    setStat("cadence_rpm", r.cadenceRpm?.toString() ?: "")
    setStat("watts_avg", r.wattsAvg?.toString() ?: "")
    setStat("split_sec_per_500m", r.splitSecPer500m?.toString() ?: "")
    setStat("swim_laps", r.swimLaps?.toString() ?: "")
    setStat("pool_length_m", r.poolLengthM?.toString() ?: "")
    setStat("swim_style", r.swimStyle ?: "")
}

/** Matches iOS `hmsToSeconds(h:m:s:)` in AddWorkoutSheet. */
private fun addHmsToTotalSecOrNull(h: String, m: String, s: String): Int? {
    val hour = h.trim().toIntOrNull() ?: 0
    val min = m.trim().toIntOrNull() ?: 0
    val sec = s.trim().toIntOrNull() ?: 0
    if (min !in 0..59 || sec !in 0..59 || hour < 0) return null
    val total = hour * 3600 + min * 60 + sec
    return total.takeIf { it > 0 }
}

/** iOS `autoPaceSec` — total seconds per km. */
private fun addCardioAutoPaceSecPerKm(distanceKmText: String, durationSec: Int?): Int? {
    val dist = distanceKmText.trim().replace(",", ".").toDoubleOrNull() ?: return null
    if (dist <= 0.0) return null
    val dur = durationSec ?: return null
    if (dur <= 0) return null
    return (dur.toDouble() / dist).roundToInt()
}

/** Swift `String(format: "%d:%02d /km", p/60, p%60)`. */
private fun addFormatPaceMinSecPerKm(paceSecPerKm: Int): String {
    val minutes = paceSecPerKm / 60
    val seconds = paceSecPerKm % 60
    return String.format("%d:%02d /km", minutes, seconds)
}
