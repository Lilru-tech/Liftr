package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.data.PetLogFilterCategory
import com.lilru.liftr.data.PetLogWire
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PetLogsSection(
    logs: List<PetLogWire>,
    hasMore: Boolean,
    onLoadMore: () -> Unit,
    onDeleteAll: () -> Unit,
    disabledCategories: Set<String>,
    onDisabledCategoriesChange: (Set<String>) -> Unit,
    modifier: Modifier = Modifier
) {
    var showFilterSheet by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val filteredLogs = remember(logs, disabledCategories) {
        PetLogFilterCategory.filter(logs, disabledCategories)
    }

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Logs", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            IconButton(onClick = { showFilterSheet = true }) {
                Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.pet_log_filters_title))
            }
        }

        when {
            logs.isEmpty() -> {
                Text(
                    stringResource(R.string.pet_logs_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 8.dp)
                )
            }
            filteredLogs.isEmpty() -> {
                Text(
                    stringResource(R.string.log_filters_no_matches),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 8.dp)
                )
            }
            else -> {
                filteredLogs.forEach { log ->
                    PetLogCard(log)
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    if (hasMore) {
                        TextButton(onClick = onLoadMore) { Text(stringResource(R.string.pet_logs_load_more)) }
                    } else {
                        Row {}
                    }
                    TextButton(onClick = onDeleteAll) {
                        Text(stringResource(R.string.pet_logs_delete), color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }

    if (showFilterSheet) {
        LogFilterBottomSheet(
            title = stringResource(R.string.pet_log_filters_title),
            categories = PetLogFilterCategory.all.map { it.key to it.label },
            disabledCategories = disabledCategories,
            onDisabledCategoriesChange = onDisabledCategoriesChange,
            footer = stringResource(R.string.log_filters_footer),
            onDismiss = { showFilterSheet = false },
            sheetState = sheetState
        )
    }
}

@Composable
private fun PetLogCard(log: PetLogWire) {
    androidx.compose.material3.Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(log.title(), fontWeight = FontWeight.SemiBold)
                Text(
                    formatLogDate(log.createdAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            val subtitle = log.subtitle()
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else if (log.expGained > 0) {
                Text("Exp gained: ${log.expGained}", style = MaterialTheme.typography.bodySmall)
            }
            log.newLevel?.let {
                Text("New level: $it", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogFilterBottomSheet(
    title: String,
    categories: List<Pair<String, String>>,
    disabledCategories: Set<String>,
    onDisabledCategoriesChange: (Set<String>) -> Unit,
    footer: String,
    onDismiss: () -> Unit,
    sheetState: androidx.compose.material3.SheetState
) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            categories.forEach { (key, label) ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(label, modifier = Modifier.weight(1f).padding(end = 8.dp))
                    Switch(
                        checked = key !in disabledCategories,
                        onCheckedChange = { enabled ->
                            val next = disabledCategories.toMutableSet()
                            if (enabled) next.remove(key) else next.add(key)
                            onDisabledCategoriesChange(next)
                        }
                    )
                }
            }
            Text(footer, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = { onDisabledCategoriesChange(emptySet()) }) {
                    Text(stringResource(R.string.log_filters_show_all))
                }
                TextButton(onClick = { onDisabledCategoriesChange(categories.map { it.first }.toSet()) }) {
                    Text(stringResource(R.string.log_filters_hide_all))
                }
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.log_filters_done))
                }
            }
        }
    }
}

private fun formatLogDate(raw: String): String = runCatching {
    val dt = Instant.parse(raw).atZone(ZoneId.systemDefault())
    DateTimeFormatter.ofPattern("d/M/yyyy, HH:mm", Locale.getDefault()).format(dt)
}.getOrDefault(raw)
