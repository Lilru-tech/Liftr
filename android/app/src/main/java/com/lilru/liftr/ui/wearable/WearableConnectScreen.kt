package com.lilru.liftr.ui.wearable

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.externalroute.ExternalRouteSyncService
import com.lilru.liftr.externalroute.ExternalRouteSyncSummary
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.from
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Serializable
private data class WearableConnectionRow(
    val provider: String,
    val status: String,
    @SerialName("connected_at") val connectedAt: String? = null,
    @SerialName("last_sync_at") val lastSyncAt: String? = null
)

@Serializable
private data class WearableOAuthStartResponse(
    val provider: String? = null,
    @SerialName("authorization_url") val authorizationUrl: String? = null,
    val error: String? = null,
    val message: String? = null
)

@Composable
fun WearableConnectScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val syncService = remember(context, supabase) { ExternalRouteSyncService(context, supabase) }
    var syncEnabled by remember { mutableStateOf(syncService.isSyncEnabled) }
    var connecting by remember { mutableStateOf(false) }
    var syncing by remember { mutableStateOf(false) }
    var connection by remember { mutableStateOf<WearableConnectionRow?>(null) }
    var banner by remember { mutableStateOf<String?>(null) }
    var lastSummary by remember { mutableStateOf<ExternalRouteSyncSummary?>(null) }

    suspend fun refreshConnection() {
        runCatching {
            connection = supabase.from("wearable_connections").select {
                filter { eq("provider", "garmin") }
                limit(1)
            }.decodeList<WearableConnectionRow>().firstOrNull()
        }.onFailure {
            connection = null
        }
    }

    LaunchedEffect(Unit) {
        refreshConnection()
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
    ) {
        LiftrBackTopBar(
            onBack = onBack,
            title = stringResource(R.string.wearable_routes_title)
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        stringResource(R.string.wearable_routes_gps_title),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        stringResource(R.string.wearable_routes_gps_body),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(stringResource(R.string.wearable_routes_toggle))
                        Switch(
                            checked = syncEnabled,
                            onCheckedChange = { enabled ->
                                syncEnabled = enabled
                                syncService.isSyncEnabled = enabled
                                banner = null
                                if (!enabled) return@Switch
                                val userId = supabase.auth.currentUserOrNull()?.id
                                if (userId == null) {
                                    syncEnabled = false
                                    syncService.isSyncEnabled = false
                                    banner = context.getString(R.string.wearable_routes_sign_in_required)
                                    return@Switch
                                }
                                scope.launch {
                                    syncing = true
                                    val summary = syncService.processPendingJobs(userId)
                                    syncing = false
                                    lastSummary = summary
                                    if (summary.failed > 0 && summary.applied == 0) {
                                        banner = summary.errorMessages.firstOrNull()
                                        syncEnabled = false
                                        syncService.isSyncEnabled = false
                                    }
                                    refreshConnection()
                                }
                            }
                        )
                    }
                    syncService.lastSyncAt?.let { instant ->
                        Text(
                            stringResource(
                                R.string.wearable_routes_last_sync,
                                DateTimeFormatter.ofPattern("MMM d, HH:mm")
                                    .withZone(ZoneId.systemDefault())
                                    .format(instant)
                            ),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (syncService.routesAppliedCount > 0) {
                        Text(
                            stringResource(R.string.wearable_routes_applied_count, syncService.routesAppliedCount),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        stringResource(R.string.wearable_routes_garmin_section),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            when (connection?.status) {
                                "active" -> stringResource(R.string.wearable_routes_garmin_connected)
                                null -> stringResource(R.string.wearable_routes_not_connected)
                                else -> stringResource(R.string.wearable_routes_garmin_status, connection?.status ?: "")
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        if (connecting || syncing) {
                            CircularProgressIndicator(modifier = Modifier.padding(4.dp))
                        }
                    }
                    Button(
                        onClick = {
                            val userId = supabase.auth.currentUserOrNull()?.id
                            if (userId == null) {
                                banner = context.getString(R.string.wearable_routes_sign_in_required)
                                return@Button
                            }
                            connecting = true
                            banner = null
                            scope.launch {
                                runCatching {
                                    val raw = supabase.functions.invoke(
                                        BackendContracts.EdgeFunctions.WEARABLE_OAUTH_START,
                                        body = buildJsonObject { put("provider", "garmin") }
                                    ).bodyAsText()
                                    val response = Json.decodeFromString<WearableOAuthStartResponse>(raw)
                                    val url = response.authorizationUrl
                                    if (url.isNullOrBlank()) {
                                        banner = response.error ?: response.message
                                            ?: context.getString(R.string.wearable_routes_garmin_not_ready)
                                    } else {
                                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                    }
                                }.onFailure { e ->
                                    banner = userFacingGarminConnectError(context, e)
                                }
                                connecting = false
                            }
                        },
                        enabled = !connecting && supabase.auth.currentUserOrNull() != null,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            if (connection?.status == "active") {
                                stringResource(R.string.wearable_routes_reconnect_garmin)
                            } else {
                                stringResource(R.string.wearable_routes_connect_garmin)
                            }
                        )
                    }
                    OutlinedButton(
                        onClick = {
                            val userId = supabase.auth.currentUserOrNull()?.id ?: return@OutlinedButton
                            scope.launch {
                                syncing = true
                                lastSummary = syncService.processPendingJobs(userId)
                                syncing = false
                                refreshConnection()
                            }
                        },
                        enabled = !syncing && supabase.auth.currentUserOrNull() != null,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.wearable_routes_sync_now))
                    }
                }
            }

            banner?.let { message ->
                Text(
                    message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
            }

            lastSummary?.let { summary ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            stringResource(R.string.wearable_routes_result_title),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(stringResource(R.string.wearable_routes_result_applied, summary.applied))
                        HorizontalDivider()
                        Text(stringResource(R.string.wearable_routes_result_skipped, summary.skipped))
                        if (summary.failed > 0) {
                            HorizontalDivider()
                            Text(stringResource(R.string.wearable_routes_result_failed, summary.failed))
                        }
                    }
                }
            }
        }
    }
}

private fun userFacingGarminConnectError(context: android.content.Context, error: Throwable): String {
    val text = "${error.message} $error".lowercase()
    return when {
        "404" in text || "not found" in text ->
            context.getString(R.string.wearable_routes_garmin_not_ready)
        "503" in text || "garmin_not_configured" in text ->
            context.getString(R.string.wearable_routes_garmin_keys_missing)
        else -> error.message ?: context.getString(R.string.wearable_routes_garmin_not_ready)
    }
}
