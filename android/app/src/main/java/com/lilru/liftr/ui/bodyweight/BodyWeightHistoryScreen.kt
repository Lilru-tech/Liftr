package com.lilru.liftr.ui.bodyweight

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.bodyweight.BodyWeightClient
import com.lilru.liftr.bodyweight.BodyWeightEntryWire
import com.lilru.liftr.bodyweight.BodyWeightPresentation
import com.lilru.liftr.bodyweight.BodyWeightRangePreset
import com.lilru.liftr.bodyweight.BodyWeightSource
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.profile.progress.ProfileActivityLineChart
import com.lilru.liftr.ui.profile.progress.ProgressPoint
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BodyWeightHistoryScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val client = remember { BodyWeightClient(supabase) }
    var loading by remember { mutableStateOf(true) }
    var entries by remember { mutableStateOf<List<BodyWeightEntryWire>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var range by remember { mutableStateOf(BodyWeightRangePreset.Days90) }
    var showLogDialog by remember { mutableStateOf(false) }
    var logWeight by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            loading = true
            error = null
            runCatching { client.listEntries() }
                .onSuccess { entries = it }
                .onFailure { error = it.message }
            loading = false
        }
    }

    LaunchedEffect(Unit) { reload() }

    val sorted = entries.sortedByDescending { it.measuredAt }
    val latest = sorted.firstOrNull()
    val previous = sorted.getOrNull(1)
    val chartPoints = BodyWeightPresentation.chartPoints(entries, range).map {
        ProgressPoint(it.label, it.value)
    }

    Column(modifier = modifier.fillMaxSize()) {
        LiftrBackTopBar(
            title = stringResource(R.string.body_weight_history_title),
            onBack = onBack,
            actions = {
                TextButton(onClick = { showLogDialog = true }) {
                    Text(stringResource(R.string.body_weight_log))
                }
            }
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (loading) {
                CircularProgressIndicator()
            }
            error?.let {
                Text(it, color = MaterialTheme.colorScheme.error)
            }
            latest?.let { entry ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        BodyWeightPresentation.formatKg(entry.weightKg),
                        style = MaterialTheme.typography.headlineSmall
                    )
                    BodyWeightPresentation.deltaText(entry.weightKg, previous?.weightKg)?.let { delta ->
                        Text(delta, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    BodyWeightPresentation.periodDeltaText(entries, 30)?.let { delta ->
                        Text(delta, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                BodyWeightRangePreset.entries.forEachIndexed { index, preset ->
                    SegmentedButton(
                        selected = range == preset,
                        onClick = { range = preset },
                        shape = SegmentedButtonDefaults.itemShape(index, BodyWeightRangePreset.entries.size)
                    ) {
                        Text(preset.title)
                    }
                }
            }
            if (chartPoints.isNotEmpty()) {
                ProfileActivityLineChart(
                    points = chartPoints,
                    lineColor = MaterialTheme.colorScheme.primary,
                    yAxisLabel = "kg"
                )
            } else if (!loading) {
                Text(
                    stringResource(R.string.body_weight_no_entries_range),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            sorted.forEach { entry ->
                val measured = runCatching { Instant.parse(entry.measuredAt) }.getOrNull()
                val label = measured?.atZone(ZoneId.systemDefault())?.format(
                    DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm", Locale.getDefault())
                ) ?: entry.measuredAt
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text(BodyWeightPresentation.formatKg(entry.weightKg), style = MaterialTheme.typography.titleMedium)
                    Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        BodyWeightPresentation.sourceLabel(BodyWeightSource.fromWire(entry.source)),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }

    if (showLogDialog) {
        AlertDialog(
            onDismissRequest = { if (!saving) showLogDialog = false },
            title = { Text(stringResource(R.string.body_weight_log)) },
            text = {
                OutlinedTextField(
                    value = logWeight,
                    onValueChange = { logWeight = it },
                    label = { Text(stringResource(R.string.profile_weight_kg)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                Button(
                    enabled = !saving,
                    onClick = {
                        val weight = logWeight.replace(',', '.').trim().toDoubleOrNull()
                        if (weight == null || weight <= 0.0) {
                            Toast.makeText(context, R.string.body_weight_invalid, Toast.LENGTH_SHORT).show()
                            return@Button
                        }
                        saving = true
                        scope.launch {
                            runCatching {
                                client.upsertEntry(
                                    measuredAt = Instant.now(),
                                    weightKg = weight,
                                    source = BodyWeightSource.Manual
                                )
                            }.onSuccess {
                                showLogDialog = false
                                logWeight = ""
                                reload()
                            }.onFailure {
                                error = it.message
                            }
                            saving = false
                        }
                    }
                ) {
                    Text(if (saving) stringResource(R.string.profile_saving) else stringResource(R.string.edit_workout_meta_save))
                }
            },
            dismissButton = {
                TextButton(onClick = { if (!saving) showLogDialog = false }) {
                    Text(stringResource(R.string.hc_import_cancel))
                }
            }
        )
    }
}
