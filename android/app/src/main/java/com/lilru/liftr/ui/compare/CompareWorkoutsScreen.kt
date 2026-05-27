package com.lilru.liftr.ui.compare

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import io.github.jan.supabase.SupabaseClient
import kotlin.math.abs

private val LeftBar = Color(0xFF057D52)
private val RightBar = Color(0xFFD12E36)

@Composable
fun CompareWorkoutsScreen(
    supabase: SupabaseClient,
    currentWorkoutId: Int,
    other: CompareOtherTarget,
    averageRightLabel: String? = null,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vmKey = when (other) {
        is CompareOtherTarget.Workout -> "compare-$currentWorkoutId-w-${other.id}"
        is CompareOtherTarget.Average ->
            "compare-$currentWorkoutId-a-${other.scope}-${other.sampleCount}"
    }
    val vm: CompareWorkoutsViewModel = viewModel(
        key = vmKey,
        factory = CompareWorkoutsViewModelFactory(
            supabase = supabase,
            currentWorkoutId = currentWorkoutId,
            other = other,
            averageRightLabel = averageRightLabel
        )
    )
    val state by vm.uiState.collectAsStateWithLifecycle()
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            TextButton(onClick = onClose) {
                Text(stringResource(R.string.compare_workouts_close))
            }
        }
        Text(
            stringResource(R.string.compare_workouts_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center
        )
        val labels = state.labels
        if (labels != null) {
            val k = labels.kind
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    labels.leftLabel,
                    color = LeftBar,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    stringResource(R.string.compare_workouts_vs),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    labels.rightLabel,
                    color = RightBar,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                val cap = k.replaceFirstChar { c ->
                    if (c.isLowerCase()) c.titlecase() else c.toString()
                }
                Text(
                    "— $cap",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        when {
            state.loading -> {
                CircularProgressIndicator(
                    modifier = Modifier
                        .padding(top = 16.dp)
                        .align(Alignment.CenterHorizontally)
                )
            }
            state.error != null -> {
                Text(
                    state.error!!,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 12.dp)
                )
            }
            state.metrics.isEmpty() -> {
                Text(
                    stringResource(R.string.compare_workouts_empty),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 12.dp)
                )
            }
            else -> {
                val display = state.metrics.filter { CompareWorkoutFormat.hasNonZero(it) }
                if (display.isEmpty()) {
                    Text(
                        stringResource(R.string.compare_workouts_all_zero),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .padding(top = 12.dp)
                            .fillMaxWidth()
                    )
                } else {
                    val signed = CompareWorkoutFormat.overallSignedPcts(display)
                    val overall = CompareWorkoutFormat.overallPct(signed)
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                    ) {
                        if (overall != null) {
                            OverallSummaryRow(
                                valuePct = overall,
                                count = signed.size,
                                totalRows = display.size
                            )
                        }
                        LazyColumn(
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth()
                        ) {
                            items(
                                count = display.size,
                                key = { ix -> display[ix].key + "_" + ix }
                            ) { ix ->
                                CompareMetricRowCard(row = display[ix])
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun OverallSummaryRow(
    valuePct: Double,
    count: Int,
    totalRows: Int
) {
    val sub = if (count == totalRows) {
        stringResource(R.string.compare_workouts_overall_sub_all, count)
    } else {
        stringResource(R.string.compare_workouts_overall_sub_partial, count, totalRows)
    }
    val color = when {
        abs(valuePct) < 0.05 -> MaterialTheme.colorScheme.onSurfaceVariant
        valuePct > 0 -> LeftBar
        else -> RightBar
    }
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 6.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.compare_workouts_overall),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    sub,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                CompareWorkoutFormat.overallPctFormat(valuePct),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = color,
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(color.copy(alpha = 0.22f))
                    .padding(horizontal = 10.dp, vertical = 6.dp)
            )
        }
    }
}

/** Carril completo + barra proporcional al valor (primera fila verde, segunda roja; paridad iOS). */
@Composable
private fun CompareWorkoutBarTrack(
    fraction: Float,
    fillBrush: Brush,
    trackColor: Color,
    trackShape: Shape,
    trackHeight: Dp
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(trackHeight)
    ) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .clip(trackShape)
                .background(trackColor)
        )
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction)
                .fillMaxHeight()
                .align(Alignment.CenterStart)
                .clip(trackShape)
                .background(fillBrush)
        )
    }
}

@Composable
private fun CompareMetricRowCard(row: CompareMetricRow) {
    val raw = CompareWorkoutFormat.rawDiffPct(row.left, row.right)
    val signed = raw?.let { it * CompareWorkoutFormat.metricDirection(row.key) }
    val badgeColor = when {
        signed == null || abs(signed) < 0.05 -> MaterialTheme.colorScheme.onSurfaceVariant
        signed > 0 -> LeftBar
        else -> RightBar
    }
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    CompareWorkoutFormat.prettyMetric(row.key),
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f)
                )
                if (signed != null) {
                    Text(
                        CompareWorkoutFormat.pctRowFormat(signed),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = badgeColor,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(badgeColor.copy(alpha = 0.22f))
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    CompareWorkoutFormat.formatValue(row.left, row.unit),
                    style = MaterialTheme.typography.labelSmall,
                    color = LeftBar
                )
                Text(
                    stringResource(R.string.compare_workouts_vs),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                )
                Text(
                    CompareWorkoutFormat.formatValue(row.right, row.unit),
                    style = MaterialTheme.typography.labelSmall,
                    color = RightBar
                )
            }
            val (lfRaw, rfRaw) = CompareWorkoutFormat.barPairFractions(row.left, row.right, row.key)
            val lf = lfRaw.coerceIn(0f, 1f)
            val rf = rfRaw.coerceIn(0f, 1f)
            val trackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.11f)
            val trackShape = RoundedCornerShape(50)
            val trackH = 12.dp
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                CompareWorkoutBarTrack(
                    fraction = lf,
                    fillBrush = Brush.horizontalGradient(
                        listOf(LeftBar, LeftBar.copy(alpha = 0.72f))
                    ),
                    trackColor = trackColor,
                    trackShape = trackShape,
                    trackHeight = trackH
                )
                CompareWorkoutBarTrack(
                    fraction = rf,
                    fillBrush = Brush.horizontalGradient(
                        listOf(RightBar, RightBar.copy(alpha = 0.72f))
                    ),
                    trackColor = trackColor,
                    trackShape = trackShape,
                    trackHeight = trackH
                )
            }
        }
    }
}
