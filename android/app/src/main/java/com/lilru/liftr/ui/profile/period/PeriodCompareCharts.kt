package com.lilru.liftr.ui.profile.period

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.util.Locale
import kotlin.math.max
import kotlin.math.round

data class PeriodCompareBreakdownMerge(
    val label: String,
    val workoutA: Int,
    val workoutB: Int
)

fun mergeBreakdownWorkouts(
    a: List<BreakdownRowUi>,
    b: List<BreakdownRowUi>
): List<PeriodCompareBreakdownMerge> {
    val labels = (a.map { it.label } + b.map { it.label }).distinct().sorted()
    return labels.map { key ->
        PeriodCompareBreakdownMerge(
            label = key.replaceFirstChar { ch ->
                if (ch.isLowerCase()) ch.titlecase(Locale.getDefault()) else ch.toString()
            },
            workoutA = a.find { it.label == key }?.workoutCount ?: 0,
            workoutB = b.find { it.label == key }?.workoutCount ?: 0
        )
    }.filter { it.workoutA > 0 || it.workoutB > 0 }
}

/**
 * Una sola métrica: dos barras (A y B) con escala común 0…max(A,B).
 */
@Composable
fun PeriodCompareSingleMetricBarChart(
    title: String,
    valueA: Double,
    valueB: Double,
    formatValue: (Double) -> String,
    colorA: Color,
    colorB: Color,
    modifier: Modifier = Modifier
        .fillMaxWidth()
        .height(200.dp)
) {
    val gridBg = Color.Gray.copy(alpha = 0.18f)
    val baseLine = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f)
    val maxV = max(1.0, max(valueA, valueB))
    Column(modifier = modifier) {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 6.dp)
        )
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(140.dp)
                .clip(RoundedCornerShape(12.dp))
        ) {
            val padL = 10.dp.toPx()
            val padR = 10.dp.toPx()
            val padT = 8.dp.toPx()
            val padB = 8.dp.toPx()
            val w = size.width - padL - padR
            val h = size.height - padT - padB
            drawRoundRect(
                color = gridBg,
                topLeft = Offset(padL, padT),
                size = Size(w, h),
                cornerRadius = CornerRadius(8.dp.toPx(), 8.dp.toPx())
            )
            val gapPx = 4.dp.toPx()
            val pairW = w * 0.5f
            val barW = (pairW - gapPx) / 2f
            val cx = padL + w / 2f
            val ha = (h * (valueA / maxV)).toFloat().coerceIn(0f, h)
            val hb = (h * (valueB / maxV)).toFloat().coerceIn(0f, h)
            val xA = cx - pairW / 2f
            val xB = xA + barW + gapPx
            val ya = padT + h - ha
            val yb = padT + h - hb
            drawRoundRect(
                color = colorA,
                topLeft = Offset(xA, ya),
                size = Size(barW, ha),
                cornerRadius = CornerRadius(3.dp.toPx(), 3.dp.toPx())
            )
            drawRoundRect(
                color = colorB,
                topLeft = Offset(xB, yb),
                size = Size(barW, hb),
                cornerRadius = CornerRadius(3.dp.toPx(), 3.dp.toPx())
            )
            drawLine(
                color = baseLine,
                start = Offset(padL + w * 0.1f, padT + h),
                end = Offset(padL + w * 0.9f, padT + h),
                strokeWidth = 1.dp.toPx()
            )
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(top = 8.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.weight(1f)) {
                Text(
                    formatValue(valueA),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = colorA,
                    textAlign = TextAlign.Center
                )
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.weight(1f)) {
                Text(
                    formatValue(valueB),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = colorB,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

/**
 * Por cada tipo: % de entrenos de ese periodo; A y B en la misma fila (dos columnas).
 */
@Composable
fun PeriodCompareBreakdownPctSideBySide(
    rows: List<PeriodCompareBreakdownMerge>,
    colorA: Color,
    colorB: Color,
    legendA: String,
    legendB: String,
    letterA: String,
    letterB: String,
    workoutsLabel: String,
    modifier: Modifier = Modifier.fillMaxWidth()
) {
    if (rows.isEmpty()) return
    val totalA = rows.sumOf { it.workoutA }.coerceAtLeast(1)
    val totalB = rows.sumOf { it.workoutB }.coerceAtLeast(1)
    val track = MaterialTheme.colorScheme.outline.copy(alpha = 0.15f)
    Column(
        modifier = modifier.padding(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        PeriodCompareChartLegend(
            colorA = colorA,
            colorB = colorB,
            labelA = legendA,
            labelB = legendB
        )
        rows.forEach { r ->
            val pctA = 100f * r.workoutA / totalA
            val pctB = 100f * r.workoutB / totalB
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    r.label,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    PctColumn(
                        modifier = Modifier.weight(1f),
                        shortLabel = letterA,
                        pct = pctA,
                        count = r.workoutA,
                        color = colorA,
                        track = track,
                        workoutsLabel = workoutsLabel
                    )
                    PctColumn(
                        modifier = Modifier.weight(1f),
                        shortLabel = letterB,
                        pct = pctB,
                        count = r.workoutB,
                        color = colorB,
                        track = track,
                        workoutsLabel = workoutsLabel
                    )
                }
            }
        }
    }
}

@Composable
private fun PctColumn(
    modifier: Modifier,
    shortLabel: String,
    pct: Float,
    count: Int,
    color: Color,
    track: Color,
    workoutsLabel: String
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(shortLabel, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                "${round(pct.toDouble()).toInt()}%",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = color
            )
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(5.dp))
                .background(track)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth((pct / 100f).coerceIn(0f, 1f))
                    .background(color)
            )
        }
        Text(
            "$count $workoutsLabel",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
fun PeriodCompareChartLegend(
    colorA: Color,
    colorB: Color,
    labelA: String,
    labelB: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        LegendDot(Modifier.weight(1f), colorA, labelA)
        LegendDot(Modifier.weight(1f), colorB, labelB)
    }
}

@Composable
private fun LegendDot(modifier: Modifier, color: Color, text: String) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Box(
            Modifier
                .width(10.dp)
                .height(10.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(color)
        )
        Text(
            text,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}
