package com.lilru.liftr.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.map.CardioRouteMapFromGeoJson
import java.util.Locale

@Composable
fun CardioDetailSection(
    detail: CardioSessionDetail,
    modifier: Modifier = Modifier
) {
    val act = remember(detail) { effectiveCardioActivityCode(detail) }
    val ex = detail.extras
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
