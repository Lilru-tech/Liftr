package com.lilru.liftr.ui.bodyweight

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.WeightRecord
import com.lilru.liftr.R
import com.lilru.liftr.bodyweight.BodyWeightImportSummary
import com.lilru.liftr.bodyweight.BodyWeightSyncWorker
import com.lilru.liftr.bodyweight.HealthConnectBodyWeightSync
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

@Composable
fun HealthConnectBodyWeightImportScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sync = remember { HealthConnectBodyWeightSync(context, supabase) }
    val client = remember {
        runCatching { HealthConnectClient.getOrCreate(context) }.getOrNull()
    }
    var syncEnabled by remember { mutableStateOf(LiftrPreferences.bodyWeightHealthSyncEnabled(context)) }
    var importing by remember { mutableStateOf(false) }
    var summary by remember { mutableStateOf<BodyWeightImportSummary?>(null) }
    var info by remember { mutableStateOf<String?>(null) }
    val perms = remember { setOf(HealthPermission.getReadPermission(WeightRecord::class)) }
    val permLauncher = rememberLauncherForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) {
        scope.launch {
            if (syncEnabled) {
                summary = sync.syncRecentSamples()
            }
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        LiftrBackTopBar(
            title = stringResource(R.string.body_weight_health_connect_title),
            onBack = onBack
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                stringResource(R.string.body_weight_health_connect_body),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            RowSwitch(
                label = stringResource(R.string.body_weight_background_sync),
                checked = syncEnabled,
                onCheckedChange = { enabled ->
                    syncEnabled = enabled
                    LiftrPreferences.setBodyWeightHealthSyncEnabled(context, enabled)
                    if (enabled) {
                        if (client != null) {
                            permLauncher.launch(perms)
                        }
                        BodyWeightSyncWorker.schedule(context)
                    } else {
                        BodyWeightSyncWorker.cancel(context)
                    }
                }
            )
            LiftrPreferences.bodyWeightHealthLastSyncAt(context)?.let { last ->
                val label = DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm", Locale.getDefault())
                    .format(last.atZone(ZoneId.systemDefault()))
                Text(
                    stringResource(R.string.body_weight_last_sync, label),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Button(
                onClick = {
                    if (client == null) {
                        info = context.getString(R.string.health_connect_unavailable)
                        return@Button
                    }
                    importing = true
                    scope.launch {
                        runCatching {
                            if (!client.permissionController.getGrantedPermissions().containsAll(perms)) {
                                permLauncher.launch(perms)
                            }
                            val from = Instant.now().minus(90, ChronoUnit.DAYS)
                            sync.syncSamples(from, Instant.now())
                        }.onSuccess {
                            summary = it
                            info = context.getString(R.string.body_weight_import_done)
                        }.onFailure {
                            info = it.message
                        }
                        importing = false
                    }
                },
                enabled = !importing,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (importing) {
                    CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                }
                Text(stringResource(R.string.body_weight_import_samples))
            }
            info?.let {
                Text(it, style = MaterialTheme.typography.bodySmall)
            }
            summary?.let { result ->
                Text(stringResource(R.string.body_weight_imported, result.imported))
                Text(stringResource(R.string.body_weight_skipped, result.skippedDuplicate))
                Text(stringResource(R.string.body_weight_failed, result.failed))
            }
        }
    }
}

@Composable
private fun RowSwitch(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, modifier = Modifier.weight(1f).padding(end = 8.dp))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
