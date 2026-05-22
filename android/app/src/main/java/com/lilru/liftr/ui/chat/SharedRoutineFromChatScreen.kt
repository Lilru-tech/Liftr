package com.lilru.liftr.ui.chat

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.clickable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.hyrox.HyroxExerciseFormatting
import com.lilru.liftr.prefs.ExerciseLanguagePreferences
import com.lilru.liftr.ui.add.AddWorkoutViewModel
import com.lilru.liftr.ui.add.AddWorkoutViewModelFactory
import com.lilru.liftr.ui.components.LiftrAvatar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
private data class ShareExerciseNameWire(
    val id: Long,
    val name: String,
    @SerialName("name_es") val nameEs: String? = null,
    @SerialName("name_en") val nameEn: String? = null
)

private fun localizedExerciseName(row: ShareExerciseNameWire, lang: String): String {
    val l = lang.lowercase()
    return when {
        l.startsWith("es") -> row.nameEs?.trim().takeUnless { it.isNullOrEmpty() } ?: row.name
        l.startsWith("en") -> row.nameEn?.trim().takeUnless { it.isNullOrEmpty() } ?: row.name
        else -> row.name
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SharedRoutineFromChatScreen(
    supabase: SupabaseClient,
    snapshot: RoutineShareSnapshot,
    onBack: () -> Unit,
    topBarActions: @Composable RowScope.() -> Unit = {},
    modifier: Modifier = Modifier
) {
    val app = LocalContext.current.applicationContext as Application
    val ctx = LocalContext.current
    val vm: AddWorkoutViewModel = viewModel(factory = AddWorkoutViewModelFactory(supabase, app))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val copyFmt = stringResource(R.string.add_routine_copy_of_format, snapshot.name)
    var nameDraft by remember(snapshot.shareNonce) { mutableStateOf(copyFmt) }
    var targetFolder by remember(snapshot.shareNonce) { mutableStateOf<Long?>(null) }
    var showSaveDialog by remember { mutableStateOf(false) }

    val meId = remember { supabase.auth.currentUserOrNull()?.id }
    val viewerIsOwner = snapshot.ownerUserId != null && snapshot.ownerUserId == meId

    var exerciseNames by remember(snapshot.shareNonce) { mutableStateOf<Map<Long, String>>(emptyMap()) }
    var decodeError by remember(snapshot.shareNonce) { mutableStateOf<String?>(null) }
    var catalogLoading by remember(snapshot.shareNonce) { mutableStateOf(false) }

    LaunchedEffect(snapshot.shareNonce) {
        if (snapshot.routineKind == "hyrox") {
            vm.loadHyroxRoutines()
        } else {
            vm.loadStrengthRoutines()
        }
    }

    LaunchedEffect(snapshot.shareNonce, snapshot.detailJson, snapshot.routineKind) {
        decodeError = null
        exerciseNames = emptyMap()
        if (snapshot.routineKind == "strength") {
            val detail = decodeRoutineShareStrengthDetail(snapshot.detailJson)
            if (detail == null) {
                decodeError = ctx.getString(R.string.shared_routine_decode_error)
                return@LaunchedEffect
            }
            val ids = detail.strengthRoutineExercises.orEmpty().map { it.exerciseId }.distinct()
            if (ids.isEmpty()) {
                return@LaunchedEffect
            }
            catalogLoading = true
            runCatching {
                val lang = ExerciseLanguagePreferences.read(ctx)
                val rows = withContext(Dispatchers.IO) {
                    supabase.from(BackendContracts.Tables.EXERCISES)
                        .select(columns = Columns.raw("id,name,name_es,name_en")) {
                            filter { isIn("id", ids) }
                            limit(ids.size.coerceAtLeast(1).toLong())
                        }
                        .decodeList<ShareExerciseNameWire>()
                }
                exerciseNames = rows.associate { it.id to localizedExerciseName(it, lang) }
            }.onFailure {
                decodeError = ctx.getString(R.string.shared_routine_decode_error)
            }
            catalogLoading = false
        } else if (snapshot.routineKind == "hyrox") {
            if (decodeRoutineShareHyroxDetail(snapshot.detailJson) == null) {
                decodeError = ctx.getString(R.string.shared_routine_decode_error)
            }
        } else {
            decodeError = ctx.getString(R.string.shared_routine_decode_error)
        }
    }

    val sortedFolders = remember(ui.routineFolders, ui.hyroxRoutineFolders, snapshot.routineKind) {
        if (snapshot.routineKind == "hyrox") ui.hyroxRoutineFolders.sortedBy { it.sortOrder }
        else ui.routineFolders.sortedBy { it.sortOrder }
    }

    LaunchedEffect(ui.message) {
        val m = ui.message ?: return@LaunchedEffect
        if (m == "Routine saved.") {
            vm.clearStatus()
            onBack()
        }
    }

    if (showSaveDialog) {
        AlertDialog(
            onDismissRequest = { showSaveDialog = false },
            title = { Text(stringResource(R.string.add_routine_sheet_duplicate_title)) },
            text = {
                Column(
                    Modifier.verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = nameDraft,
                        onValueChange = { nameDraft = it },
                        label = { Text(stringResource(R.string.add_routine_name_label)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    if (sortedFolders.isNotEmpty()) {
                        Text(
                            stringResource(R.string.add_routine_folder_label),
                            style = MaterialTheme.typography.labelSmall
                        )
                        Column {
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable { targetFolder = null }
                                    .padding(vertical = 4.dp)
                            ) {
                                val mark = if (targetFolder == null) "✓ " else "  "
                                Text(mark + stringResource(R.string.add_routine_folder_none))
                            }
                            for (fo in sortedFolders) {
                                Row(
                                    Modifier
                                        .fillMaxWidth()
                                        .clickable { targetFolder = fo.id }
                                        .padding(vertical = 4.dp)
                                ) {
                                    val mark = if (targetFolder == fo.id) "✓ " else "  "
                                    Text(
                                        mark + fo.name,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showSaveDialog = false
                        if (snapshot.routineKind == "hyrox") {
                            vm.importHyroxRoutineFromShare(snapshot.detailJson, nameDraft, targetFolder)
                        } else {
                            vm.importStrengthRoutineFromShare(snapshot.detailJson, nameDraft, targetFolder)
                        }
                    },
                    enabled = !ui.managingRoutines && nameDraft.isNotBlank()
                ) { Text(stringResource(R.string.add_routine_save_action)) }
            },
            dismissButton = {
                TextButton(onClick = { showSaveDialog = false }) {
                    Text(stringResource(R.string.add_routine_dialog_cancel))
                }
            }
        )
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = Color.Transparent,
        topBar = {
            TopAppBar(
                title = { Text(snapshot.name) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = null)
                    }
                },
                actions = topBarActions,
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent)
            )
        }
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .fillMaxSize()
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                LiftrAvatar(
                    imageUrl = snapshot.ownerAvatarUrl,
                    displayName = snapshot.ownerUsername,
                    size = 44.dp
                )
                Column {
                    snapshot.ownerUsername?.takeIf { it.isNotBlank() }?.let { u ->
                        Text(
                            stringResource(R.string.shared_routine_from, "@$u"),
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                    val kindLabel = if (snapshot.routineKind == "hyrox") {
                        stringResource(R.string.chat_share_routine_card_hyrox)
                    } else {
                        stringResource(R.string.chat_share_routine_card_strength)
                    }
                    Text(
                        kindLabel,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            when {
                decodeError != null -> Text(decodeError!!, color = MaterialTheme.colorScheme.error)
                catalogLoading && snapshot.routineKind == "strength" -> {
                    CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 2.dp)
                }
                snapshot.routineKind == "strength" -> {
                    val detail = decodeRoutineShareStrengthDetail(snapshot.detailJson)
                    if (detail != null) {
                        val exs = detail.strengthRoutineExercises.orEmpty().sortedBy { it.orderIndex }
                        if (exs.isEmpty()) {
                            Text(
                                stringResource(R.string.shared_routine_no_exercises),
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        } else {
                            val emDash = stringResource(R.string.shared_routine_em_dash)
                            StrengthRoutineSharePreview(
                                exercises = exs,
                                exerciseNames = exerciseNames,
                                emDash = emDash
                            )
                        }
                    }
                }
                snapshot.routineKind == "hyrox" -> {
                    val detail = decodeRoutineShareHyroxDetail(snapshot.detailJson)
                    if (detail != null) {
                        val rows = detail.hyroxRoutineExercises.orEmpty().sortedBy { it.exerciseOrder }
                        if (rows.isEmpty()) {
                            Text(
                                stringResource(R.string.shared_routine_no_stations),
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        } else {
                            for (w in rows) {
                                HyroxStationDetailCard(w)
                                Spacer(Modifier.size(4.dp))
                            }
                        }
                    }
                }
            }

            ui.error?.let { err ->
                Text(err, color = MaterialTheme.colorScheme.error)
            }

            if (!viewerIsOwner) {
                Button(
                    onClick = { showSaveDialog = true },
                    enabled = !ui.managingRoutines && decodeError == null && (snapshot.routineKind != "strength" || !catalogLoading),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    if (ui.managingRoutines) {
                        CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                    } else {
                        Text(stringResource(R.string.shared_routine_save_as_yours))
                    }
                }
            }
        }
    }
}

@Composable
private fun HyroxStationDetailCard(w: RoutineShareHyroxEx) {
    val title = HyroxExerciseFormatting.label(w.exerciseCode, w.exerciseDisplayName, w.notes)
    val lines = buildList {
        w.distanceM?.takeIf { it > 0 }?.let { add(stringResource(R.string.shared_routine_distance_m, it)) }
        w.reps?.takeIf { it > 0 }?.let { add(stringResource(R.string.shared_routine_reps_n, it)) }
        w.weightKg?.takeIf { it > 0 }?.let { kg ->
            val s = if (kg == kotlin.math.floor(kg)) kg.toInt().toString() else String.format("%.1f", kg)
            add(stringResource(R.string.shared_routine_weight_kg, s))
        }
        w.durationSec?.takeIf { it > 0 }?.let { add(stringResource(R.string.shared_routine_duration_s, it)) }
        w.heightCm?.takeIf { it > 0 }?.let { add(stringResource(R.string.shared_routine_height_cm, it)) }
        w.implementCount?.takeIf { it > 0 }?.let { add(stringResource(R.string.shared_routine_implements_n, it)) }
        w.notes?.trim()?.takeIf { it.isNotEmpty() }?.let { add(stringResource(R.string.shared_routine_notes_line, it)) }
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f)
        )
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            if (lines.isEmpty()) {
                Text(stringResource(R.string.shared_routine_no_parameters), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                for (line in lines) {
                    Text(line, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
