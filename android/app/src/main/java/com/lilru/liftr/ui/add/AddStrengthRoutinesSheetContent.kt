package com.lilru.liftr.ui.add

/**
 * Hoja de rutinas y carpetas de fuerza: CRUD y orden frente a tablas `strength_routine_*` (ver migraciones Supabase).
 * Paridad de producto con el picker de plantillas en [Liftr/AddWorkoutSheet.swift] — validar con pruebas manuales.
 */
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
private fun UnfiledHeader(
    collapsed: Boolean,
    onToggle: () -> Unit
) {
    val rot by animateFloatAsState(if (collapsed) 0f else 90f, label = "chev")
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(vertical = 4.dp, horizontal = 2.dp)
    ) {
        Icon(
            imageVector = Icons.Filled.ChevronRight,
            contentDescription = null,
            modifier = Modifier.rotate(rot),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            stringResource(R.string.add_routine_section_no_folder),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun FolderRowHeader(
    name: String,
    expanded: Boolean,
    onToggle: () -> Unit,
    onRename: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit,
    canMove: Boolean,
    canUp: Boolean,
    canDown: Boolean,
    topPadding: androidx.compose.ui.unit.Dp
) {
    val rot by animateFloatAsState(if (!expanded) 0f else 90f, label = "fc")
    var menu by remember { mutableStateOf(false) }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = topPadding, bottom = 4.dp, start = 2.dp, end = 2.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .weight(1f)
                .clickable(onClick = onToggle)
        ) {
            Icon(
                imageVector = Icons.Filled.ChevronRight,
                contentDescription = null,
                modifier = Modifier.rotate(rot),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                name,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Box {
            IconButton(onClick = { menu = true }) {
                Icon(
                    imageVector = Icons.Filled.MoreVert,
                    contentDescription = stringResource(R.string.add_routine_folder_options_content_description)
                )
            }
            DropdownMenu(
                expanded = menu,
                onDismissRequest = { menu = false }
            ) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.add_routine_folder_rename_label)) },
                    onClick = { menu = false; onRename() }
                )
                if (canMove) {
                    if (canUp) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.add_move_exercise_up)) },
                            onClick = { menu = false; onMoveUp() }
                        )
                    }
                    if (canDown) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.add_move_exercise_down)) },
                            onClick = { menu = false; onMoveDown() }
                        )
                    }
                }
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.add_routine_folder_delete_action)) },
                    onClick = { menu = false; onDelete() }
                )
            }
        }
    }
}

@Composable
private fun RoutineListRow(
    row: StrengthRoutineUi,
    busy: Boolean,
    updatedLabel: String?,
    onApply: () -> Unit,
    neighbors: Pair<List<StrengthRoutineUi>, Int>?,
    onEditRoutine: () -> Unit,
    onRenameRoutine: () -> Unit,
    onDuplicate: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onMoveTo: () -> Unit,
    onDeleteRoutine: () -> Unit
) {
    var menu by remember { mutableStateOf(false) }
    val neigh = neighbors
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    row.name,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (updatedLabel != null) {
                    Text(
                        updatedLabel,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Box {
                IconButton(
                    onClick = { menu = true },
                    enabled = !busy
                ) {
                    Icon(
                        imageVector = Icons.Filled.MoreVert,
                        contentDescription = stringResource(R.string.add_routine_routine_options_content_description)
                    )
                }
                DropdownMenu(
                    expanded = menu,
                    onDismissRequest = { menu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.add_routine_sheet_menu_edit)) },
                        onClick = { menu = false; onEditRoutine() }
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.add_routine_sheet_menu_rename)) },
                        onClick = { menu = false; onRenameRoutine() }
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.add_routine_sheet_menu_duplicate)) },
                        onClick = { menu = false; onDuplicate() }
                    )
                    if (neigh != null) {
                        val (list, idx) = neigh
                        if (idx > 0) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.add_routine_sheet_menu_move_up)) },
                                onClick = { menu = false; onMoveUp() }
                            )
                        }
                        if (idx < list.lastIndex) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.add_routine_sheet_menu_move_down)) },
                                onClick = { menu = false; onMoveDown() }
                            )
                        }
                    }
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.add_routine_sheet_menu_move_to)) },
                        onClick = { menu = false; onMoveTo() }
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.add_routine_delete_action), color = MaterialTheme.colorScheme.error) },
                        onClick = { menu = false; onDeleteRoutine() }
                    )
                }
            }
            TextButton(
                onClick = onApply,
                enabled = !busy
            ) {
                if (busy) {
                    Text(stringResource(R.string.add_routine_applying))
                } else {
                    Text(stringResource(R.string.add_routine_apply_button))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddStrengthRoutinesSheetContent(
    ui: AddWorkoutUiState,
    onClose: () -> Unit,
    onReload: () -> Unit,
    onCreateFolder: (String) -> Unit,
    onRenameFolder: (Long, String) -> Unit,
    onMoveFolder: (Long, Int) -> Unit,
    onDeleteFolder: (Long) -> Unit,
    onRenameRoutine: (Long, String) -> Unit,
    onDuplicateRoutine: (Long, String, Long?) -> Unit,
    onMoveRoutine: (Long, Int) -> Unit,
    onMoveRoutineToFolder: (Long, Long?) -> Unit,
    onDeleteRoutine: (Long) -> Unit,
    onApplyRoutine: (Long) -> Unit,
    onEditRoutine: (Long, String) -> Unit
) {
    val ctx = LocalContext.current.applicationContext
    val persistScope = rememberCoroutineScope()
    var search by remember { mutableStateOf("") }
    var collapsedFolderIds by remember { mutableStateOf<Set<Long>>(emptySet()) }
    var unfiledCollapsed by remember { mutableStateOf(false) }
    fun persistRoutinesSheetState() {
        persistScope.launch(Dispatchers.IO) {
            StrengthRoutinesSheetPreferences.save(
                ctx,
                folderIds = collapsedFolderIds,
                unfiledCollapsed = unfiledCollapsed
            )
        }
    }
    LaunchedEffect(Unit) {
        val s = withContext(Dispatchers.IO) { StrengthRoutinesSheetPreferences.read(ctx) }
        collapsedFolderIds = s.collapsedFolderIds
        unfiledCollapsed = s.unfiledCollapsed
    }

    var newFolderName by remember { mutableStateOf("") }
    var showNewFolderDialog by remember { mutableStateOf(false) }

    var folderRename by remember { mutableStateOf<RoutineFolderUi?>(null) }
    var folderRenameText by remember { mutableStateOf("") }

    var routineToRename by remember { mutableStateOf<StrengthRoutineUi?>(null) }
    var routineRenameDraft by remember { mutableStateOf("") }

    var duplicateOf by remember { mutableStateOf<StrengthRoutineUi?>(null) }
    var duplicateNameDraft by remember { mutableStateOf("") }
    var duplicateTargetFolder by remember { mutableStateOf<Long?>(null) }

    var moveRoutineId by remember { mutableStateOf<Long?>(null) }
    var routineToDelete by remember { mutableStateOf<Long?>(null) }
    var folderToDelete by remember { mutableStateOf<Long?>(null) }

    var expandMenuOpen by remember { mutableStateOf(false) }

    val sortedFolderRows = remember(ui.routineFolders) {
        ui.routineFolders.sortedBy { it.sortOrder }
    }

    val q = search.trim()
    val displayRoutines = remember(ui.routines, q) {
        if (q.isEmpty()) ui.routines
        else ui.routines.filter { it.name.contains(q, ignoreCase = true) }
    }
    val sortedFolders = remember(ui.routineFolders) {
        ui.routineFolders.sortedWith(compareBy { it.sortOrder })
    }
    val displayFolders = remember(sortedFolders, q, ui.routines) {
        if (q.isEmpty()) sortedFolders
        else sortedFolders.filter { f ->
            f.name.contains(q, ignoreCase = true) ||
                ui.routines.any { it.folderId == f.id && it.name.contains(q, ignoreCase = true) }
        }
    }
    val routinesUnfiled = remember(displayRoutines) {
        displayRoutines
            .filter { it.folderId == null }
            .sortedWith(
                compareBy<StrengthRoutineUi> { it.sortOrder }
                    .thenByDescending { it.updatedAtIso ?: "" }
            )
    }
    fun inFolder(id: Long) = displayRoutines
        .filter { it.folderId == id }
        .sortedWith(compareBy<StrengthRoutineUi> { it.sortOrder }.thenByDescending { it.updatedAtIso ?: "" })

    fun groupNeighbors(row: StrengthRoutineUi): Pair<List<StrengthRoutineUi>, Int>? {
        if (q.isNotEmpty()) return null
        val list = displayRoutines
            .filter { it.folderId == row.folderId }
            .sortedWith(compareBy<StrengthRoutineUi> { it.sortOrder }.thenBy { it.id })
        val i = list.indexOfFirst { it.id == row.id }
        if (i < 0) return null
        return list to i
    }

    if (showNewFolderDialog) {
        AlertDialog(
            onDismissRequest = { showNewFolderDialog = false; newFolderName = "" },
            title = { Text(stringResource(R.string.add_routine_sheet_new_folder_title)) },
            text = {
                OutlinedTextField(
                    value = newFolderName,
                    onValueChange = { newFolderName = it },
                    label = { Text(stringResource(R.string.add_routine_new_folder_label)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onCreateFolder(newFolderName)
                        newFolderName = ""
                        showNewFolderDialog = false
                    }
                ) { Text(stringResource(R.string.add_routine_create_folder)) }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showNewFolderDialog = false
                        newFolderName = ""
                    }
                ) { Text(stringResource(R.string.add_routine_dialog_cancel)) }
            }
        )
    }
    if (folderRename != null) {
        val f = folderRename
        if (f != null) {
            AlertDialog(
                onDismissRequest = { folderRename = null },
                title = { Text(stringResource(R.string.add_routine_folder_rename_label)) },
                text = {
                    OutlinedTextField(
                        value = folderRenameText,
                        onValueChange = { folderRenameText = it },
                        label = { Text(stringResource(R.string.add_routine_name_label)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            onRenameFolder(f.id, folderRenameText)
                            folderRename = null
                        }
                    ) { Text(stringResource(R.string.add_routine_save_action)) }
                },
                dismissButton = { TextButton(onClick = { folderRename = null }) { Text(stringResource(R.string.add_routine_dialog_cancel)) } }
            )
        }
    }
    if (routineToRename != null) {
        val r = routineToRename
        if (r != null) {
            AlertDialog(
                onDismissRequest = { routineToRename = null },
                title = { Text(stringResource(R.string.add_routine_sheet_rename_routine_title)) },
                text = {
                    OutlinedTextField(
                        value = routineRenameDraft,
                        onValueChange = { routineRenameDraft = it },
                        label = { Text(stringResource(R.string.add_routine_name_label)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            onRenameRoutine(r.id, routineRenameDraft)
                            routineToRename = null
                        }
                    ) { Text(stringResource(R.string.add_routine_save_action)) }
                },
                dismissButton = { TextButton(onClick = { routineToRename = null }) { Text(stringResource(R.string.add_routine_dialog_cancel)) } }
            )
        }
    }
    if (duplicateOf != null) {
        val s = duplicateOf
        if (s != null) {
            AlertDialog(
                onDismissRequest = { duplicateOf = null; duplicateNameDraft = "" },
                title = { Text(stringResource(R.string.add_routine_sheet_duplicate_title)) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = duplicateNameDraft,
                            onValueChange = { duplicateNameDraft = it },
                            label = { Text(stringResource(R.string.add_routine_name_label)) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                        if (sortedFolderRows.isNotEmpty()) {
                            Text(
                                stringResource(R.string.add_routine_folder_label),
                                style = MaterialTheme.typography.labelSmall
                            )
                            Column {
                                Row(
                                    Modifier
                                        .fillMaxWidth()
                                        .clickable {
                                            duplicateTargetFolder = null
                                        }
                                        .padding(vertical = 4.dp)
                                ) {
                                    val mark = if (duplicateTargetFolder == null) "✓ " else "  "
                                    Text("$mark${stringResource(R.string.add_routine_folder_none)}")
                                }
                                for (fo in sortedFolderRows) {
                                    Row(
                                        Modifier
                                            .fillMaxWidth()
                                            .clickable {
                                                duplicateTargetFolder = fo.id
                                            }
                                            .padding(vertical = 4.dp)
                                    ) {
                                        val mark = if (duplicateTargetFolder == fo.id) "✓ " else "  "
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
                            onDuplicateRoutine(s.id, duplicateNameDraft, duplicateTargetFolder)
                            duplicateOf = null
                            duplicateNameDraft = ""
                        }
                    ) { Text(stringResource(R.string.add_routine_save_action)) }
                },
                dismissButton = {
                    TextButton(
                        onClick = {
                            duplicateOf = null
                            duplicateNameDraft = ""
                        }
                    ) { Text(stringResource(R.string.add_routine_dialog_cancel)) }
                }
            )
        }
    }
    if (moveRoutineId != null) {
        val rid = moveRoutineId
        if (rid != null) {
            AlertDialog(
                onDismissRequest = { moveRoutineId = null },
                title = { Text(stringResource(R.string.add_routine_sheet_move_to_title)) },
                text = {
                    Column {
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable { onMoveRoutineToFolder(rid, null); moveRoutineId = null }
                                .padding(vertical = 4.dp)
                        ) { Text(stringResource(R.string.add_routine_folder_none)) }
                        for (fo in sortedFolderRows) {
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable { onMoveRoutineToFolder(rid, fo.id); moveRoutineId = null }
                                    .padding(vertical = 4.dp)
                            ) { Text(fo.name) }
                        }
                    }
                },
                confirmButton = { TextButton(onClick = { moveRoutineId = null }) { Text(stringResource(R.string.add_routine_dialog_close)) } }
            )
        }
    }
    if (routineToDelete != null) {
        val id = routineToDelete
        if (id != null) {
            AlertDialog(
                onDismissRequest = { routineToDelete = null },
                title = { Text(stringResource(R.string.add_routine_delete_confirm_title)) },
                text = { Text(stringResource(R.string.add_routine_delete_confirm_body)) },
                confirmButton = {
                    TextButton(
                        onClick = {
                            onDeleteRoutine(id)
                            routineToDelete = null
                        }
                    ) { Text(stringResource(R.string.add_routine_delete_action), color = MaterialTheme.colorScheme.error) }
                },
                dismissButton = { TextButton(onClick = { routineToDelete = null }) { Text(stringResource(R.string.add_routine_dialog_cancel)) } }
            )
        }
    }
    if (folderToDelete != null) {
        val id = folderToDelete
        if (id != null) {
            AlertDialog(
                onDismissRequest = { folderToDelete = null },
                title = { Text(stringResource(R.string.add_routine_folder_delete_confirm_title)) },
                text = { Text(stringResource(R.string.add_routine_folder_delete_confirm_body)) },
                confirmButton = {
                    TextButton(
                        onClick = {
                            onDeleteFolder(id)
                            folderToDelete = null
                        }
                    ) { Text(stringResource(R.string.add_routine_folder_delete_action), color = MaterialTheme.colorScheme.error) }
                },
                dismissButton = { TextButton(onClick = { folderToDelete = null }) { Text(stringResource(R.string.add_routine_dialog_cancel)) } }
            )
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 560.dp)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        ui.error?.let { err ->
            Text(
                err,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(bottom = 8.dp)
            )
        }
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            TextButton(onClick = onClose) { Text(stringResource(R.string.add_routine_sheet_close)) }
            Row {
                Box {
                    IconButton(
                        onClick = { expandMenuOpen = true },
                        enabled = !ui.loadingRoutines
                    ) {
                        Icon(
                            Icons.Filled.UnfoldMore,
                            stringResource(R.string.add_routine_sheet_expand_collapse)
                        )
                    }
                    DropdownMenu(
                        expanded = expandMenuOpen,
                        onDismissRequest = { expandMenuOpen = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.add_routine_expand_all)) },
                            onClick = {
                                expandMenuOpen = false
                                collapsedFolderIds = emptySet()
                                unfiledCollapsed = false
                                persistRoutinesSheetState()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.add_routine_collapse_all)) },
                            onClick = {
                                expandMenuOpen = false
                                collapsedFolderIds = sortedFolders.map { it.id }.toSet()
                                unfiledCollapsed = displayRoutines.any { it.folderId == null }
                                persistRoutinesSheetState()
                            }
                        )
                    }
                }
                IconButton(
                    onClick = { showNewFolderDialog = true; newFolderName = "" }
                ) {
                    Icon(
                        imageVector = Icons.Filled.CreateNewFolder,
                        contentDescription = stringResource(R.string.add_routine_create_folder)
                    )
                }
                IconButton(
                    onClick = onReload,
                    enabled = !ui.loadingRoutines
                ) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = stringResource(R.string.add_routines_reload)
                    )
                }
            }
        }
        Text(
            stringResource(R.string.add_routine_sheet_routines_title),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(bottom = 4.dp, top = 4.dp)
        )
        OutlinedTextField(
            value = search,
            onValueChange = { search = it },
            label = { Text(stringResource(R.string.add_routine_sheet_search_hint)) },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp)
        )
        if (ui.loadingRoutines && ui.routines.isEmpty() && ui.routineFolders.isEmpty()) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                CircularProgressIndicator(Modifier.padding(12.dp))
            }
        } else if (q.isNotEmpty() && displayRoutines.isEmpty()) {
            Text(
                stringResource(R.string.add_routine_sheet_no_match),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(8.dp)
            )
        } else if (ui.routineFolders.isEmpty() && ui.routines.isEmpty()) {
            Text(
                stringResource(R.string.add_routines_empty_hint),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall
            )
        } else {
            if (routinesUnfiled.isNotEmpty()) {
                UnfiledHeader(unfiledCollapsed) {
                    unfiledCollapsed = !unfiledCollapsed
                    persistRoutinesSheetState()
                }
                if (!unfiledCollapsed) {
                    for (row in routinesUnfiled) {
                        val copyOf = stringResource(R.string.add_routine_copy_of_format, row.name)
                        RoutineListRow(
                            row = row,
                            busy = ui.managingRoutines || ui.applyingRoutine ||
                                ui.strengthRoutineTemplateEdit?.saving == true,
                            updatedLabel = formatRoutineUpdatedAt(row.updatedAtIso),
                            onApply = { onApplyRoutine(row.id) },
                            neighbors = groupNeighbors(row),
                            onEditRoutine = { onEditRoutine(row.id, row.name) },
                            onRenameRoutine = {
                                routineToRename = row
                                routineRenameDraft = row.name
                            },
                            onDuplicate = {
                                duplicateOf = row
                                duplicateNameDraft = copyOf
                                duplicateTargetFolder = row.folderId
                            },
                            onMoveUp = { onMoveRoutine(row.id, -1) },
                            onMoveDown = { onMoveRoutine(row.id, 1) },
                            onMoveTo = { moveRoutineId = row.id },
                            onDeleteRoutine = { routineToDelete = row.id }
                        )
                    }
                }
            }
            for (folder in displayFolders) {
                val inF = inFolder(folder.id)
                val collapsed = collapsedFolderIds.contains(folder.id)
                val fIdx = sortedFolders.indexOfFirst { it.id == folder.id }
                val canUp = fIdx > 0
                val canDown = fIdx >= 0 && fIdx < sortedFolders.size - 1
                val firstFolderId = displayFolders.firstOrNull()?.id
                val topPad = if (routinesUnfiled.isNotEmpty() || folder.id != firstFolderId) 12.dp else 0.dp
                FolderRowHeader(
                    name = folder.name,
                    expanded = !collapsed,
                    onToggle = {
                        collapsedFolderIds = if (collapsed) {
                            collapsedFolderIds - folder.id
                        } else {
                            collapsedFolderIds + folder.id
                        }
                        persistRoutinesSheetState()
                    },
                    onRename = { folderRename = folder; folderRenameText = folder.name },
                    onMoveUp = { onMoveFolder(folder.id, -1) },
                    onMoveDown = { onMoveFolder(folder.id, 1) },
                    onDelete = { folderToDelete = folder.id },
                    canMove = q.isEmpty(),
                    canUp = canUp,
                    canDown = canDown,
                    topPadding = topPad
                )
                if (!collapsed) {
                    if (inF.isEmpty()) {
                        Text(
                            stringResource(R.string.add_routine_folder_empty),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(8.dp)
                        )
                    } else {
                        for (row in inF) {
                            val copyOf = stringResource(R.string.add_routine_copy_of_format, row.name)
                            RoutineListRow(
                                row = row,
                                busy = ui.managingRoutines || ui.applyingRoutine ||
                                    ui.strengthRoutineTemplateEdit?.saving == true,
                                updatedLabel = formatRoutineUpdatedAt(row.updatedAtIso),
                                onApply = { onApplyRoutine(row.id) },
                                neighbors = groupNeighbors(row),
                                onEditRoutine = { onEditRoutine(row.id, row.name) },
                                onRenameRoutine = {
                                    routineToRename = row
                                    routineRenameDraft = row.name
                                },
                                onDuplicate = {
                                    duplicateOf = row
                                    duplicateNameDraft = copyOf
                                    duplicateTargetFolder = row.folderId
                                },
                                onMoveUp = { onMoveRoutine(row.id, -1) },
                                onMoveDown = { onMoveRoutine(row.id, 1) },
                                onMoveTo = { moveRoutineId = row.id },
                                onDeleteRoutine = { routineToDelete = row.id }
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun formatRoutineUpdatedAt(iso: String?): String? {
    if (iso == null) return null
    return runCatching {
        val i = Instant.parse(iso)
        val z = ZoneId.systemDefault()
        val dtf = DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm", Locale.getDefault())
        dtf.format(i.atZone(z).toLocalDateTime())
    }.getOrNull()
}