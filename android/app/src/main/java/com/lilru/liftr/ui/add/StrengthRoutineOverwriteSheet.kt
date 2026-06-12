package com.lilru.liftr.ui.add

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Notes
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private data class ExerciseDiffGroup(
    val exerciseOrderIndex: Int,
    val exerciseTitle: String,
    val setGroups: List<SetDiffGroup>
)

private data class SetDiffGroup(
    val setNumber: Int,
    val lines: List<StrengthRoutineOverwriteDiffLine>
)

private fun buildOverwriteDiffGroups(lines: List<StrengthRoutineOverwriteDiffLine>): List<ExerciseDiffGroup> {
    val fieldRank = mapOf(
        "Reps" to 0,
        "Weight" to 1,
        "RPE" to 2,
        "Rest" to 3,
        "Drop steps" to 4,
        "Sets" to 5,
        "Added set" to 6,
        "Removed set" to 7,
        "Set notes" to 8,
        "Prescription" to 9
    )
    return lines.groupBy { it.exerciseOrderIndex }
        .toSortedMap()
        .mapNotNull { (_, exLines) ->
            if (exLines.isEmpty()) return@mapNotNull null
            val title = exLines.first().exerciseTitle
            val order = exLines.first().exerciseOrderIndex
            val setGroups = exLines.groupBy { it.setNumber }
                .toSortedMap()
                .map { (setNum, sl) ->
                    SetDiffGroup(
                        setNumber = setNum,
                        lines = sl.sortedBy { fieldRank[it.fieldTitle] ?: 99 }
                    )
                }
            ExerciseDiffGroup(order, title, setGroups)
        }
}

private fun iconForOverwriteField(title: String): ImageVector = when (title) {
    "Reps" -> Icons.Filled.Repeat
    "Weight" -> Icons.Filled.FitnessCenter
    "RPE" -> Icons.Filled.Speed
    "Rest" -> Icons.Filled.Timer
    "Set notes" -> Icons.Filled.Notes
    else -> Icons.Filled.Tune
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StrengthRoutineOverwriteBottomSheet(
    prompt: StrengthRoutineOverwritePrompt,
    onDismissRequest: () -> Unit,
    onOverwriteTemplate: (Set<String>) -> Unit,
    onNotNow: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = sheetState
    ) {
        StrengthRoutineOverwriteSheetContent(
            prompt = prompt,
            onOverwriteTemplate = onOverwriteTemplate,
            onNotNow = onNotNow,
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
        )
    }
}

@Composable
private fun StrengthRoutineOverwriteSheetContent(
    prompt: StrengthRoutineOverwritePrompt,
    onOverwriteTemplate: (Set<String>) -> Unit,
    onNotNow: () -> Unit,
    modifier: Modifier = Modifier
) {
    val actionableIds = remember(prompt) { actionableOverwriteDiffLineIds(prompt.diffLines) }
    var selectedIds by remember(prompt) { mutableStateOf(actionableIds) }
    val selectedCount = selectedIds.count { actionableIds.contains(it) }
    val groups = buildOverwriteDiffGroups(prompt.diffLines)
    val exCount = prompt.diffLines.map { it.exerciseOrderIndex }.toSet().size
    val summary = when {
        selectedCount == actionableIds.size && exCount == 1 ->
            "$selectedCount change · 1 exercise"
        selectedCount == actionableIds.size ->
            "$selectedCount changes · $exCount exercises"
        exCount == 1 ->
            "$selectedCount of ${actionableIds.size} changes · 1 exercise"
        else ->
            "$selectedCount of ${actionableIds.size} changes · $exCount exercises"
    }

    LazyColumn(
        modifier = modifier.padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "Review changes",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    prompt.routineName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Surface(
                    shape = MaterialTheme.shapes.large,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    tonalElevation = 1.dp
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Layers,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            summary,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
                Text(
                    buildAnnotatedString {
                        append("This updates your ")
                        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) {
                            append("saved routine template")
                        }
                        append(". Your completed workout is still saved as usual.")
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        item {
            Text(
                "CHANGES",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                letterSpacing = 0.6.sp
            )
        }

        items(groups, key = { it.exerciseOrderIndex }) { exGroup ->
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerHigh
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Column(
                    Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Text(
                        exGroup.exerciseTitle,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    exGroup.setGroups.forEachIndexed { idx, setGroup ->
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(
                                "Set ${setGroup.setNumber}",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            setGroup.lines.forEach { line ->
                                OverwriteDiffRow(
                                    line = line,
                                    isSelectable = line.fieldTitle != "Sets",
                                    checked = selectedIds.contains(line.id),
                                    onCheckedChange = { enabled ->
                                        if (line.fieldTitle == "Sets") return@OverwriteDiffRow
                                        selectedIds = if (enabled) {
                                            selectedIds + line.id
                                        } else {
                                            selectedIds - line.id
                                        }
                                    }
                                )
                            }
                        }
                        if (idx < exGroup.setGroups.lastIndex) {
                            HorizontalDivider(Modifier.padding(vertical = 4.dp))
                        }
                    }
                }
            }
        }

        item {
            Spacer(Modifier.height(4.dp))
            HorizontalDivider()
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = { onOverwriteTemplate(selectedIds.intersect(actionableIds)) },
                modifier = Modifier.fillMaxWidth(),
                enabled = selectedCount > 0
            ) {
                Text(
                    if (selectedCount == 1) "Apply 1 change" else "Apply $selectedCount changes"
                )
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = onNotNow,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Not now")
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun OverwriteDiffRow(
    line: StrengthRoutineOverwriteDiffLine,
    isSelectable: Boolean,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription =
                    "${line.fieldTitle}, was ${line.oldValue}, now ${line.newValue}, ${line.exerciseContext}"
            },
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top
    ) {
        if (isSelectable) {
            Checkbox(
                checked = checked,
                onCheckedChange = onCheckedChange
            )
        } else {
            Spacer(Modifier.size(48.dp))
        }
        Icon(
            imageVector = iconForOverwriteField(line.fieldTitle),
            contentDescription = null,
            modifier = Modifier.size(22.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                line.fieldTitle.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    line.oldValue,
                    style = MaterialTheme.typography.bodyMedium,
                    textDecoration = TextDecoration.LineThrough,
                    color = MaterialTheme.colorScheme.outline
                )
                Text("→", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                Text(
                    line.newValue,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}
