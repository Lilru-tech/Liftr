package com.lilru.liftr.ui.health

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
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
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * Health Connect (Android) ↔ Apple Health / HealthKit (iOS): misma intención de producto; API distinta.
 * Tras confirmar, [importHealthConnectSessionToCardio] usa [BackendContracts.Rpc.CREATE_CARDIO_WORKOUT_V2] como el flujo Swift.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HealthConnectImportScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val client = remember {
        runCatching { HealthConnectClient.getOrCreate(context) }.getOrNull()
    }
    if (client == null) {
        HealthConnectNoClientScreen(onBack = onBack, modifier = modifier)
        return
    }
    val scope = rememberCoroutineScope()
    val c = client
    val perms = remember {
        setOf(HealthPermission.getReadPermission(ExerciseSessionRecord::class))
    }
    var lines by remember { mutableStateOf<List<String>>(emptyList()) }
    var records by remember { mutableStateOf<List<ExerciseSessionRecord>>(emptyList()) }
    var err by remember { mutableStateOf<String?>(null) }
    var importBusy by remember { mutableStateOf(false) }
    var importInfo by remember { mutableStateOf<String?>(null) }
    var chosen by remember { mutableStateOf<ExerciseSessionRecord?>(null) }
    var showHelpSheet by remember { mutableStateOf(false) }
    var permEpoch by remember { mutableStateOf(0) }
    val permLauncher = rememberLauncherForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { permEpoch++ }

    fun load() {
        scope.launch {
            err = null
            if (!c.permissionController.getGrantedPermissions().containsAll(perms)) {
                lines = emptyList()
                return@launch
            }
            val r = withContext(Dispatchers.IO) {
                runCatching {
                    val end = Instant.now()
                    val start = end.minus(7, ChronoUnit.DAYS)
                    c.readRecords(
                        ReadRecordsRequest(
                            recordType = ExerciseSessionRecord::class,
                            timeRangeFilter = TimeRangeFilter.between(start, end)
                        )
                    )
                }
            }
            r.onSuccess { res ->
                val fmt = DateTimeFormatter.ofPattern("d MMM HH:mm").withZone(ZoneId.systemDefault())
                val list = res.records.take(25)
                records = list
                lines = list.map { rec ->
                    val title = rec.title ?: rec.exerciseType.toString()
                    val t = rec.startTime
                    "$title — ${fmt.format(t)}"
                }
            }
            r.onFailure { e ->
                err = e.message?.take(200)
                lines = emptyList()
                records = emptyList()
            }
        }
    }

    LaunchedEffect(permEpoch) {
        load()
    }

    if (showHelpSheet) {
        ModalBottomSheet(onDismissRequest = { showHelpSheet = false }) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    stringResource(R.string.health_connect_help_sheet_title),
                    style = MaterialTheme.typography.titleLarge
                )
                Text(
                    stringResource(R.string.health_connect_help_sheet_body),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 12.dp, bottom = 8.dp)
                )
                TextButton(
                    onClick = { showHelpSheet = false },
                    modifier = Modifier.fillMaxWidth()
                ) { Text(stringResource(R.string.hc_import_ok)) }
            }
        }
    }

    importInfo?.let { msg ->
        AlertDialog(
            onDismissRequest = { importInfo = null },
            confirmButton = {
                TextButton(onClick = { importInfo = null }) {
                    Text(stringResource(R.string.hc_import_ok))
                }
            },
            text = { Text(msg) }
        )
    }
    chosen?.let { rec ->
        val fmt2 = DateTimeFormatter.ofPattern("d MMM uuuu HH:mm").withZone(ZoneId.systemDefault())
        val dSec = rec.endTime?.let { e ->
            java.time.Duration.between(rec.startTime, e).seconds
        } ?: 0L
        AlertDialog(
            onDismissRequest = { if (!importBusy) chosen = null },
            title = { Text(stringResource(R.string.hc_import_confirm_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        (rec.title ?: "—").ifBlank { "—" },
                        style = MaterialTheme.typography.titleSmall
                    )
                    Text(
                        stringResource(
                            R.string.hc_import_confirm_line,
                            fmt2.format(rec.startTime),
                            dSec.coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
                        ),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            },
            confirmButton = {
                if (importBusy) {
                    CircularProgressIndicator(Modifier.size(28.dp))
                } else {
                    TextButton(
                        onClick = {
                            scope.launch {
                                importBusy = true
                                val r = withContext(Dispatchers.IO) {
                                    importHealthConnectSessionToCardio(supabase, rec)
                                }
                                importBusy = false
                                chosen = null
                                importInfo = r.fold(
                                    onSuccess = { id -> context.getString(R.string.hc_import_success, id) },
                                    onFailure = { e -> e.message?.take(200) ?: "Error" }
                                )
                            }
                        }
                    ) { Text(stringResource(R.string.hc_import_confirm)) }
                }
            },
            dismissButton = {
                if (!importBusy) {
                    TextButton(onClick = { chosen = null }) {
                        Text(stringResource(R.string.hc_import_cancel))
                    }
                }
            }
        )
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Text(
            stringResource(R.string.health_connect_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            stringResource(R.string.health_connect_body),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            stringResource(R.string.health_connect_apple_note),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    stringResource(R.string.health_connect_help_title),
                    style = MaterialTheme.typography.titleSmall
                )
                Text(
                    stringResource(R.string.health_connect_help_body),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                TextButton(
                    onClick = { showHelpSheet = true },
                    modifier = Modifier.fillMaxWidth()
                ) { Text(stringResource(R.string.health_connect_help_open_details)) }
            }
        }
        OutlinedButton(
            onClick = { permLauncher.launch(perms) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.health_connect_request_permission))
        }
        err?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (lines.isNotEmpty()) {
            Text(
                stringResource(R.string.health_connect_sessions_header),
                style = MaterialTheme.typography.titleSmall
            )
            lines.forEachIndexed { i, line ->
                Text(
                    line,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier
                        .padding(top = 4.dp)
                        .clickable { chosen = records.getOrNull(i) }
                )
            }
        }
    }
}

@Composable
private fun HealthConnectNoClientScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Text(
            stringResource(R.string.health_connect_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            stringResource(R.string.health_connect_unavailable),
            color = MaterialTheme.colorScheme.error
        )
        if (Build.VERSION.SDK_INT >= 28) {
            OutlinedButton(
                onClick = {
                    val uri = Uri.parse(
                        "https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata"
                    )
                    context.startActivity(
                        Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.health_connect_install))
            }
        }
    }
}
