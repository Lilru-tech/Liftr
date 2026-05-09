package com.lilru.liftr.ui.segment

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.OutlinedButton
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.cardio.CardioRouteGeoJson
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.home.WorkoutDetailScreen
import com.lilru.liftr.ui.home.workoutDetailScreenGradientModifier
import com.lilru.liftr.ui.map.CardioRouteMapFromGeoJson
import com.lilru.liftr.ui.map.startGoogleMapsAtPoint
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import java.util.UUID

private data class SegmentDetailUi(
    val name: String,
    val geojson: String,
    val createdBy: String?,
    val foreignEffortsCount: Int,
    val bufferM: Double,
    val segmentLengthM: Double?,
    val centerLat: Double?,
    val centerLon: Double?,
    val leaderboardEffortCount: Long,
    val leaderboardAthleteCount: Long,
    val confidenceAvg: Double?,
    val confidenceMin: Double?,
    val confidenceMax: Double?,
    val viewerBestElapsedSec: Int?,
    val viewerBestWorkoutId: Long?
)

private data class SegmentLeaderUi(
    val rank: Int,
    /** UUID del atleta (mismo formato que `auth`); para filtrar “tu mejor” en cliente. */
    val userId: String,
    val username: String,
    val elapsedSec: Int,
    val workoutId: Int,
    val effortAtIso: String?,
    val confidence: Double?,
    /** Fracción 0–1 del eje del segmento cubierta por la ruta (RPC v2). */
    val routeCoverage: Double?,
    val isSourceWorkout: Boolean?
)

private fun formatSegmentElapsedSec(sec: Int): String {
    if (sec < 60) return "${sec}s"
    if (sec < 3600) {
        return String.format(Locale.US, "%d:%02d", sec / 60, sec % 60)
    }
    val h = sec / 3600
    val rem = sec % 3600
    return String.format(Locale.US, "%d:%02d:%02d", h, rem / 60, rem % 60)
}

private fun formatEffortDateMedium(iso: String?): String? {
    if (iso.isNullOrBlank()) return null
    return try {
        val z = java.time.ZonedDateTime.parse(iso)
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(z.toLocalDate())
    } catch (_: Exception) {
        null
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SegmentDetailScreen(
    supabase: SupabaseClient,
    segmentId: UUID,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var overlayWorkoutId by rememberSaveable(segmentId) { mutableStateOf<Int?>(null) }
    if (overlayWorkoutId != null) {
        WorkoutDetailScreen(
            supabase = supabase,
            workoutId = overlayWorkoutId!!,
            onBack = { overlayWorkoutId = null },
            modifier = modifier
        )
        return
    }

    var loading by remember(segmentId) { mutableStateOf(true) }
    var error by remember(segmentId) { mutableStateOf<String?>(null) }
    var detail by remember(segmentId) { mutableStateOf<SegmentDetailUi?>(null) }
    var leaders by remember(segmentId) { mutableStateOf<List<SegmentLeaderUi>>(emptyList()) }
    var menuExpanded by remember { mutableStateOf(false) }
    var showRename by remember { mutableStateOf(false) }
    var renameDraft by remember { mutableStateOf("") }
    var ownerBusy by remember { mutableStateOf(false) }
    var ownerError by remember { mutableStateOf<String?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var reloadTick by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val meId = supabase.auth.currentUserOrNull()?.id

    LaunchedEffect(segmentId, reloadTick) {
        loading = true
        error = null
        ownerError = null
        runCatching {
            val dParams = buildJsonObject {
                put("p_segment_id", segmentId.toString())
            }
            val dRes = supabase.postgrest.rpc(BackendContracts.Rpc.GET_SEGMENT_DETAIL_V1, dParams) { }
            val dArr = JSONArray(dRes.data.trim())
            if (dArr.length() == 0) {
                detail = null
            } else {
                val o = dArr.getJSONObject(0)
                val cb = o.optString("created_by", "").trim().takeIf { it.isNotEmpty() }
                detail = SegmentDetailUi(
                    name = o.optString("name", "Segment"),
                    geojson = o.optString("geojson", ""),
                    createdBy = cb,
                    foreignEffortsCount = o.optInt("foreign_efforts_count", 0),
                    bufferM = o.optDouble("buffer_m", 25.0),
                    segmentLengthM = o.optNullableDouble("segment_length_m"),
                    centerLat = o.optNullableDouble("center_lat"),
                    centerLon = o.optNullableDouble("center_lon"),
                    leaderboardEffortCount = if (o.has("leaderboard_effort_count") && !o.isNull("leaderboard_effort_count")) {
                        o.optLong("leaderboard_effort_count", 0L)
                    } else {
                        0L
                    },
                    leaderboardAthleteCount = if (o.has("leaderboard_athlete_count") && !o.isNull("leaderboard_athlete_count")) {
                        o.optLong("leaderboard_athlete_count", 0L)
                    } else {
                        0L
                    },
                    confidenceAvg = o.optNullableDouble("confidence_avg"),
                    confidenceMin = o.optNullableDouble("confidence_min"),
                    confidenceMax = o.optNullableDouble("confidence_max"),
                    viewerBestElapsedSec = if (o.has("viewer_best_elapsed_sec") && !o.isNull("viewer_best_elapsed_sec")) {
                        o.optInt("viewer_best_elapsed_sec", 0).takeIf { it > 0 }
                    } else {
                        null
                    },
                    viewerBestWorkoutId = if (o.has("viewer_best_workout_id") && !o.isNull("viewer_best_workout_id")) {
                        o.optLong("viewer_best_workout_id", 0L).takeIf { it > 0L }
                    } else {
                        null
                    }
                )
            }
            val lParams = buildJsonObject {
                put("p_segment_id", segmentId.toString())
                put("p_limit", 50)
            }
            val lRes = supabase.postgrest.rpc(BackendContracts.Rpc.GET_SEGMENT_LEADERBOARD_V1, lParams) { }
            val lArr = JSONArray(lRes.data.trim())
            val rows = buildList {
                for (i in 0 until lArr.length()) {
                    val r = lArr.optJSONObject(i) ?: continue
                    add(
                        SegmentLeaderUi(
                            rank = r.optInt("rank", i + 1),
                            userId = r.optString("user_id", "").trim(),
                            username = r.optNullableString("username")
                                ?: r.optString("user_id").take(8) + "…",
                            elapsedSec = r.optInt("elapsed_sec", 0),
                            workoutId = r.optInt("workout_id", 0),
                            effortAtIso = r.optNullableString("effort_at"),
                            confidence = r.optNullableDouble("confidence"),
                            routeCoverage = r.optNullableDouble("route_coverage"),
                            isSourceWorkout = if (r.has("is_source_workout") && !r.isNull("is_source_workout")) {
                                r.optBoolean("is_source_workout", false)
                            } else {
                                null
                            }
                        )
                    )
                }
            }
            leaders = rows
                .sortedBy { it.elapsedSec }
                .mapIndexed { idx, r -> r.copy(rank = idx + 1) }
        }.onFailure { e ->
            error = e.message ?: "Error"
            detail = null
            leaders = emptyList()
        }
        loading = false
    }

    Box(modifier = modifier) {
    Scaffold(
        modifier = Modifier
            .fillMaxSize()
            .then(workoutDetailScreenGradientModifier()),
        topBar = {
            TopAppBar(
                title = { Text(detail?.name ?: stringResource(R.string.segment_detail_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.segment_back))
                    }
                },
                actions = {
                    val d = detail
                    if (d != null && meId != null && d.createdBy == meId) {
                        Box {
                            IconButton(
                                onClick = { menuExpanded = true },
                                enabled = !ownerBusy
                            ) {
                                Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.segment_menu_a11y))
                            }
                            DropdownMenu(
                                expanded = menuExpanded,
                                onDismissRequest = { menuExpanded = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.segment_rename)) },
                                    onClick = {
                                        menuExpanded = false
                                        renameDraft = d.name
                                        showRename = true
                                    }
                                )
                                if (d.foreignEffortsCount == 0) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.segment_delete)) },
                                        onClick = {
                                            menuExpanded = false
                                            showDeleteConfirm = true
                                        }
                                    )
                                }
                            }
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f)
                )
            )
        }
    ) { inner ->
        when {
            loading -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(inner),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    CircularProgressIndicator()
                }
            }
            error != null -> {
                Text(
                    text = error ?: "",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(inner)
                        .padding(16.dp)
                )
            }
            detail == null -> {
                Text(
                    text = stringResource(R.string.segment_not_found),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(inner)
                        .padding(16.dp)
                )
            }
            else -> {
                val d = detail!!
                val ctx = LocalContext.current
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(inner)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    ownerError?.let { err ->
                        Text(
                            text = err,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    if (d.geojson.isNotBlank()) {
                        CardioRouteMapFromGeoJson(
                            routeGeojson = d.geojson,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    val lenKmStr = d.segmentLengthM?.takeIf { it > 0 }?.let { m ->
                        String.format(Locale.US, "%.2f km", m / 1000.0)
                    } ?: "—"
                    val bufferInt = d.bufferM.toInt().coerceAtLeast(1)
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
                        shape = RoundedCornerShape(10.dp)
                    ) {
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                stringResource(R.string.segment_about_title),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                stringResource(R.string.segment_stats_length_buffer, lenKmStr, bufferInt),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                stringResource(
                                    R.string.segment_stats_athletes_efforts,
                                    d.leaderboardAthleteCount.toInt(),
                                    d.leaderboardEffortCount.toInt()
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            val avg = d.confidenceAvg
                            if (avg != null && avg > 0 && avg <= 1.0) {
                                val pct = kotlin.math.round(avg * 100).toInt()
                                val lo = d.confidenceMin
                                val hi = d.confidenceMax
                                val rangeText = if (lo != null && hi != null && lo > 0 && hi > 0 && lo <= 1 && hi <= 1 && hi > lo) {
                                    stringResource(
                                        R.string.segment_stats_confidence_range,
                                        pct,
                                        kotlin.math.round(lo * 100).toInt(),
                                        kotlin.math.round(hi * 100).toInt()
                                    )
                                } else {
                                    stringResource(R.string.segment_stats_confidence_avg, pct)
                                }
                                Text(
                                    text = rangeText,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                    val routeMid = CardioRouteGeoJson.parseLineStringLatLng(d.geojson)
                        .takeIf { it.size >= 2 }
                        ?.let { it[it.size / 2] }
                    val mapLat = d.centerLat ?: routeMid?.first
                    val mapLon = d.centerLon ?: routeMid?.second
                    val canOpenMaps = mapLat != null && mapLon != null &&
                        mapLat.isFinite() && mapLon.isFinite() &&
                        mapLat in -90.0..90.0 && mapLon in -180.0..180.0
                    OutlinedButton(
                        onClick = {
                            if (canOpenMaps) {
                                startGoogleMapsAtPoint(ctx, mapLat!!, mapLon!!, d.name)
                            }
                        },
                        enabled = canOpenMaps,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Map, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.segment_open_maps))
                        }
                    }
                    val viewerPb = remember(leaders, meId) {
                        if (meId == null) {
                            null
                        } else {
                            leaders.filter { it.userId.equals(meId, ignoreCase = true) }
                                .minByOrNull { it.elapsedSec }
                        }
                    }
                    if (viewerPb != null && viewerPb.elapsedSec > 0) {
                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Column(Modifier.padding(12.dp)) {
                                Text(
                                    stringResource(R.string.segment_your_best_title),
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    formatSegmentElapsedSec(viewerPb.elapsedSec),
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                        }
                    }
                    Text(
                        stringResource(R.string.segment_time_disclaimer),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.9f)
                    )
                    Text(
                        stringResource(R.string.segment_leaderboard_title),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    if (leaders.isEmpty()) {
                        Text(
                            stringResource(R.string.segment_leaderboard_empty),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        leaders.forEach { row ->
                            val dateLabel = formatEffortDateMedium(row.effortAtIso)
                            val isViewerBest = viewerPb?.workoutId == row.workoutId
                            val rowModifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .then(
                                    if (isViewerBest) {
                                        Modifier.border(
                                            2.dp,
                                            MaterialTheme.colorScheme.primary,
                                            RoundedCornerShape(10.dp)
                                        )
                                    } else {
                                        Modifier
                                    }
                                )
                                .clickable(
                                    enabled = row.workoutId > 0,
                                    onClick = { overlayWorkoutId = row.workoutId }
                                )
                            Surface(
                                modifier = rowModifier,
                                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
                                shape = RoundedCornerShape(10.dp)
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(Modifier.weight(1f)) {
                                        Text(
                                            "#${row.rank}  ${row.username}",
                                            style = MaterialTheme.typography.bodyMedium
                                        )
                                        Text(
                                            formatSegmentElapsedSec(row.elapsedSec),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                        if (dateLabel != null) {
                                            Text(
                                                dateLabel,
                                                style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.85f)
                                            )
                                        }
                                        val overlapFrac = row.routeCoverage ?: row.confidence
                                        if (overlapFrac != null && overlapFrac > 0 && overlapFrac <= 1.0) {
                                            Text(
                                                stringResource(
                                                    R.string.segment_overlap_row,
                                                    kotlin.math.round(overlapFrac * 100).toInt()
                                                ),
                                                style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.85f)
                                            )
                                        }
                                        if (row.isSourceWorkout == true) {
                                            Text(
                                                stringResource(R.string.segment_defined_from_workout_row),
                                                style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                    }
                                    Icon(
                                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                        contentDescription = stringResource(R.string.segment_open_workout_a11y),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showRename) {
        AlertDialog(
            onDismissRequest = { if (!ownerBusy) showRename = false },
            title = { Text(stringResource(R.string.segment_rename_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = renameDraft,
                        onValueChange = { renameDraft = it },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    ownerError?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val t = renameDraft.trim()
                        if (t.isEmpty()) return@Button
                        scope.launch {
                            ownerBusy = true
                            ownerError = null
                            runCatching {
                                supabase.postgrest.rpc(
                                    BackendContracts.Rpc.UPDATE_MY_SEGMENT_NAME_V1,
                                    buildJsonObject {
                                        put("p_segment_id", segmentId.toString())
                                        put("p_name", t)
                                    }
                                ) { }
                            }.onSuccess {
                                showRename = false
                                reloadTick += 1
                            }.onFailure { ownerError = it.message?.take(200) ?: it::class.java.simpleName }
                            ownerBusy = false
                        }
                    },
                    enabled = !ownerBusy
                ) { Text(stringResource(R.string.segment_save)) }
            },
            dismissButton = {
                TextButton(onClick = { showRename = false }, enabled = !ownerBusy) {
                    Text(stringResource(R.string.segment_create_cancel))
                }
            }
        )
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { if (!ownerBusy) showDeleteConfirm = false },
            title = { Text(stringResource(R.string.segment_delete_confirm_title)) },
            text = { Text(stringResource(R.string.segment_delete_confirm_body)) },
            confirmButton = {
                Button(
                    onClick = {
                        scope.launch {
                            ownerBusy = true
                            val result = runCatching {
                                supabase.postgrest.rpc(
                                    BackendContracts.Rpc.DELETE_MY_SEGMENT_V1,
                                    buildJsonObject { put("p_segment_id", segmentId.toString()) }
                                ) { }
                            }
                            withContext(Dispatchers.Main.immediate) {
                                ownerBusy = false
                                result.onSuccess {
                                    showDeleteConfirm = false
                                    onBack()
                                }.onFailure {
                                    ownerError = it.message?.take(200)
                                    showDeleteConfirm = false
                                }
                            }
                        }
                    },
                    enabled = !ownerBusy
                ) { Text(stringResource(R.string.segment_delete)) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }, enabled = !ownerBusy) {
                    Text(stringResource(R.string.segment_create_cancel))
                }
            }
        )
    }
    }
}

private fun JSONObject.optNullableString(key: String): String? {
    if (!has(key) || isNull(key)) return null
    val s = optString(key, "").trim()
    return s.takeIf { it.isNotEmpty() }
}

private fun JSONObject.optNullableDouble(key: String): Double? {
    if (!has(key) || isNull(key)) return null
    val v = optDouble(key, Double.NaN)
    return v.takeUnless { it.isNaN() }
}

/** Invocar desde corrutina (PostgREST RPC es suspend). */
private val duplicateUuidRegex =
    Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

private fun extractDuplicateSegmentUuidFromError(e: Throwable): UUID? {
    val text = buildString {
        append(e.message ?: "")
        append(' ')
        append(e.cause?.message ?: "")
    }
    if (!text.contains("duplicate_segment", ignoreCase = true)) return null
    return duplicateUuidRegex.find(text)?.value?.let { runCatching { UUID.fromString(it) }.getOrNull() }
}

suspend fun createSegmentFromWorkoutRpc(
    supabase: SupabaseClient,
    workoutId: Int,
    name: String,
    startFraction: Double,
    endFraction: Double,
    bufferM: Double = 25.0
): UUID {
    return try {
        val params = buildJsonObject {
            put("p_workout_id", workoutId)
            put("p_name", name)
            put("p_start_fraction", startFraction)
            put("p_end_fraction", endFraction)
            put("p_buffer_m", bufferM)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.CREATE_SEGMENT_FROM_WORKOUT_V1, params) { }
        parseUuidFromRpc(res.data) ?: error("Invalid segment id from server")
    } catch (e: Exception) {
        val dup = extractDuplicateSegmentUuidFromError(e)
        if (dup != null) throw SegmentDuplicateException(dup)
        throw e
    }
}

private fun parseUuidFromRpc(raw: String): UUID? {
    val t = raw.trim()
    runCatching { return UUID.fromString(t.removeSurrounding("\"")) }.getOrNull()
    runCatching {
        val arr = JSONArray(t)
        if (arr.length() > 0) {
            val s = arr.optString(0)
            if (s.isNotBlank()) return UUID.fromString(s)
        }
    }.getOrNull()
    runCatching {
        val o = JSONObject(t)
        val s = o.optString("create_segment_from_workout_v1", "")
        if (s.isNotBlank()) return UUID.fromString(s)
    }.getOrNull()
    return null
}
