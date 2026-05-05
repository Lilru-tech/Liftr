package com.lilru.liftr.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.cardio.CardioRouteGeoJson
import com.lilru.liftr.ui.map.CardioRouteMapFromGeoJson
import com.lilru.liftr.ui.map.CardioRouteSegmentTapMap
import com.lilru.liftr.ui.segment.SegmentDuplicateException
import com.lilru.liftr.ui.segment.createSegmentFromWorkoutRpc
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import java.util.Locale
import java.util.UUID

@Composable
fun CardioDetailSection(
    detail: CardioSessionDetail,
    workoutId: Int? = null,
    workoutState: String? = null,
    isOwner: Boolean = false,
    supabase: SupabaseClient? = null,
    onSegmentCreated: ((UUID) -> Unit)? = null,
    /** Si el servidor detecta un segmento ya muy similar, abrir ese detalle (p. ej. overlay en el detalle del workout). */
    onDuplicateSegment: ((UUID) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val act = remember(detail) { effectiveCardioActivityCode(detail) }
    val ex = detail.extras
    val scope = rememberCoroutineScope()
    var showSegmentDialog by remember { mutableStateOf(false) }
    var segmentName by remember { mutableStateOf("Segment") }
    var startFrac by remember { mutableFloatStateOf(0f) }
    var endFrac by remember { mutableFloatStateOf(1f) }
    var segmentBusy by remember { mutableStateOf(false) }
    var segmentErr by remember { mutableStateOf<String?>(null) }
    var nextMapTapSetsStart by remember { mutableStateOf(true) }
    val routePts = remember(detail.routeGeojson) {
        CardioRouteGeoJson.parseLineStringLatLng(detail.routeGeojson)
    }
    val canOfferSegment =
        isOwner &&
            workoutState?.equals("published", ignoreCase = true) == true &&
            workoutId != null &&
            supabase != null &&
            onSegmentCreated != null &&
            !detail.routeGeojson.isNullOrBlank()

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(
                color = workoutDetailFieldPanelColor(),
                shape = RoundedCornerShape(14.dp)
            )
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            stringResource(
                R.string.home_detail_cardio_block_title,
                formatActivityCodeForDisplay(
                    (detail.activityCode?.takeIf { it.isNotBlank() } ?: detail.modality)
                        ?.ifBlank { "cardio" } ?: "cardio"
                )
            ),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        if (detail.distanceKm != null) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_distance),
                String.format(Locale.US, "%.2f km", detail.distanceKm)
            )
        }
        if (detail.durationSec != null && detail.durationSec > 0) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_duration),
                formatDurationFromSec(detail.durationSec)
            )
        }
        if (detail.avgPaceSecPerKm != null && detail.avgPaceSecPerKm > 0) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_avg_pace),
                formatPaceMinSecPerKm(detail.avgPaceSecPerKm)
            )
        }
        val splits = ex?.kmSplitPaceSec
        if (!splits.isNullOrEmpty()) {
            KmPaceSplitsSection(splits = splits)
        }
        if (detail.avgHr != null) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_avg_hr),
                stringResource(R.string.home_detail_cardio_bpm, detail.avgHr)
            )
        }
        if (detail.maxHr != null) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_max_hr),
                stringResource(R.string.home_detail_cardio_bpm, detail.maxHr)
            )
        }
        if (detail.elevationGainM != null) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_elevation),
                stringResource(R.string.home_detail_cardio_m, detail.elevationGainM)
            )
        }
        if (!detail.routeGeojson.isNullOrBlank()) {
            Text(
                stringResource(R.string.home_detail_cardio_route),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 4.dp)
            )
            CardioRouteMapFromGeoJson(
                routeGeojson = detail.routeGeojson,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp)
            )
            if (canOfferSegment) {
                Button(
                    onClick = {
                        segmentErr = null
                        showSegmentDialog = true
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp)
                ) {
                    Text(stringResource(R.string.segment_create_button))
                }
            }
        }
        if (!detail.notes.isNullOrBlank()) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_session_notes),
                detail.notes
            )
        }
        if (showsCardioCadenceForActivity(act) && ex?.cadenceRpm != null) {
            val unit = if (act == "rowerg") "spm" else "rpm"
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_cadence),
                "${ex.cadenceRpm} $unit"
            )
        }
        if (showsCardioWattsForActivity(act) && ex?.wattsAvg != null) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_watts),
                stringResource(R.string.home_detail_cardio_w, ex.wattsAvg)
            )
        }
        if (showsCardioInclineForActivity(act) && ex?.inclinePct != null) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_incline),
                String.format(Locale.US, "%.1f %%", ex.inclinePct)
            )
        }
        if (showsCardioSplit500mForActivity(act) && ex?.splitSecPer500m != null) {
            CardioInfoRow(
                stringResource(R.string.home_detail_cardio_label_split_500),
                "${formatMmSs(ex.splitSecPer500m)} /500m"
            )
        }
        if (showSegmentDialog && canOfferSegment && workoutId != null && supabase != null && onSegmentCreated != null) {
            AlertDialog(
                onDismissRequest = { if (!segmentBusy) showSegmentDialog = false },
                title = { Text(stringResource(R.string.segment_create_dialog_title)) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedTextField(
                            value = segmentName,
                            onValueChange = { segmentName = it },
                            label = { Text(stringResource(R.string.segment_name_hint)) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                        if (routePts.size >= 2) {
                            Text(
                                stringResource(R.string.segment_map_hint),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                FilterChip(
                                    selected = nextMapTapSetsStart,
                                    onClick = { nextMapTapSetsStart = true },
                                    label = { Text(stringResource(R.string.segment_map_pick_start)) }
                                )
                                FilterChip(
                                    selected = !nextMapTapSetsStart,
                                    onClick = { nextMapTapSetsStart = false },
                                    label = { Text(stringResource(R.string.segment_map_pick_end)) }
                                )
                            }
                            CardioRouteSegmentTapMap(
                                routePoints = routePts,
                                onPickFraction = { f ->
                                    if (nextMapTapSetsStart) {
                                        startFrac = min(f, 0.99).toFloat()
                                        if (endFrac <= startFrac) {
                                            endFrac = min(1f, startFrac + 0.02f)
                                        }
                                    } else {
                                        endFrac = max(f, 0.01).toFloat()
                                        if (endFrac <= startFrac) {
                                            startFrac = max(0f, endFrac - 0.02f)
                                        }
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                                mapHeightDp = 200
                            )
                            Spacer(Modifier.height(4.dp))
                        }
                        Text(
                            stringResource(R.string.segment_start_pct, (startFrac * 100).toInt()),
                            style = MaterialTheme.typography.labelMedium
                        )
                        Slider(
                            value = startFrac,
                            onValueChange = { startFrac = it.coerceIn(0f, 0.95f) },
                            valueRange = 0f..0.95f
                        )
                        Text(
                            stringResource(R.string.segment_end_pct, (endFrac * 100).toInt()),
                            style = MaterialTheme.typography.labelMedium
                        )
                        Slider(
                            value = endFrac,
                            onValueChange = { endFrac = it.coerceIn(0.05f, 1f) },
                            valueRange = 0.05f..1f
                        )
                        if (segmentErr != null) {
                            Text(
                                segmentErr!!,
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                        Text(
                            stringResource(R.string.segment_create_auto_match_footer),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                confirmButton = {
                    Button(
                        onClick = {
                            if (startFrac >= endFrac) {
                                segmentErr = "Invalid range"
                                return@Button
                            }
                            val nameTrim = segmentName.trim().ifEmpty { "Segment" }
                            segmentBusy = true
                            segmentErr = null
                            scope.launch {
                                runCatching {
                                    createSegmentFromWorkoutRpc(
                                        supabase = supabase,
                                        workoutId = workoutId,
                                        name = nameTrim,
                                        startFraction = startFrac.toDouble(),
                                        endFraction = endFrac.toDouble()
                                    )
                                }.onSuccess { id ->
                                    segmentBusy = false
                                    showSegmentDialog = false
                                    onSegmentCreated(id)
                                }.onFailure { e ->
                                    segmentBusy = false
                                    val dup = (e as? SegmentDuplicateException)?.existingSegmentId
                                        ?: (e.cause as? SegmentDuplicateException)?.existingSegmentId
                                    if (dup != null && onDuplicateSegment != null) {
                                        showSegmentDialog = false
                                        onDuplicateSegment.invoke(dup)
                                        segmentErr = null
                                    } else {
                                        segmentErr = e.message ?: "Error"
                                    }
                                }
                            }
                        },
                        enabled = !segmentBusy
                    ) {
                        Text(stringResource(R.string.segment_create_confirm))
                    }
                },
                dismissButton = {
                    TextButton(
                        onClick = { showSegmentDialog = false },
                        enabled = !segmentBusy
                    ) {
                        Text(stringResource(R.string.segment_create_cancel))
                    }
                }
            )
        }
        if (showsCardioSwimFieldsForActivity(act)) {
            if (ex?.swimLaps != null) {
                CardioInfoRow(
                    stringResource(R.string.home_detail_cardio_label_laps),
                    "${ex.swimLaps}"
                )
            }
            if (ex?.poolLengthM != null) {
                CardioInfoRow(
                    stringResource(R.string.home_detail_cardio_label_pool_length),
                    stringResource(R.string.home_detail_cardio_m, ex.poolLengthM)
                )
            }
            val st = ex?.swimStyle?.trim().orEmpty()
            if (st.isNotEmpty()) {
                CardioInfoRow(
                    stringResource(R.string.home_detail_cardio_label_swim_style),
                    st.replaceFirstChar { c ->
                        if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
                    }
                )
            }
        }
    }
}

@Composable
private fun KmPaceSplitsSection(splits: List<Int>) {
    if (splits.isEmpty()) return
    if (splits.size == 1) {
        CardioInfoRow(
            stringResource(R.string.home_detail_cardio_label_per_km_pace),
            stringResource(
                R.string.home_detail_cardio_km1_pace,
                formatPaceMinSecPerKm(splits[0])
            )
        )
    } else {
        var expanded by remember { mutableStateOf(false) }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    color = workoutDetailInsetFieldColor(),
                    shape = RoundedCornerShape(10.dp)
                )
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded }
                    .padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    stringResource(R.string.home_detail_cardio_label_per_km_pace),
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold
                )
                if (expanded) {
                    Text(
                        stringResource(R.string.home_detail_cardio_n_km, splits.size),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            stringResource(
                                R.string.home_detail_cardio_km1_pace,
                                formatPaceMinSecPerKm(splits[0])
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace
                        )
                        Text(
                            stringResource(R.string.home_detail_cardio_n_more, splits.size - 1),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            if (expanded) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    splits.forEachIndexed { idx, sec ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                "Km ${idx + 1}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                formatPaceMinSecPerKm(sec),
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CardioInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                color = workoutDetailInsetFieldColor(),
                shape = RoundedCornerShape(10.dp)
            )
            .padding(10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            value,
            style = MaterialTheme.typography.bodySmall
        )
    }
}
