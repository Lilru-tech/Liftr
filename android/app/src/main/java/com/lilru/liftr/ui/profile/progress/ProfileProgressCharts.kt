package com.lilru.liftr.ui.profile.progress

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min

@Composable
fun ProfileActivityLineChart(
    points: List<ProgressPoint>,
    lineColor: Color,
    yAxisLabel: String,
    modifier: Modifier = Modifier
        .fillMaxWidth()
        .height(220.dp)
) {
    if (points.isEmpty()) return
    val maxY = max(1.0, points.maxOf { it.value } * 1.15)
    val minY = -maxY * 0.05
    val gridBg = Color.Gray.copy(alpha = 0.18f)
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
    ) {
        Text(
            yAxisLabel,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(8.dp)
        )
        Canvas(modifier = Modifier.fillMaxSize()) {
            val padL = 4.dp.toPx()
            val padR = 8.dp.toPx()
            val padT = 28.dp.toPx()
            val padB = 28.dp.toPx()
            val w = size.width - padL - padR
            val h = size.height - padT - padB
            drawRoundRect(
                color = gridBg,
                topLeft = Offset(padL, padT),
                size = Size(w, h)
            )
            if (points.size < 2) {
                val x = padL + w / 2f
                val nv = ((points[0].value - minY) / (maxY - minY)).toFloat().coerceIn(0f, 1f)
                val y = padT + h * (1f - nv)
                drawCircle(lineColor, 5.dp.toPx(), Offset(x, y))
                return@Canvas
            }
            val path = Path()
            var first = true
            points.forEachIndexed { i, p ->
                val t = i.toFloat() / (points.size - 1).coerceAtLeast(1)
                val x = padL + w * t
                val nv = ((p.value - minY) / (maxY - minY)).toFloat().coerceIn(0f, 1f)
                val y = padT + h * (1f - nv)
                if (first) {
                    path.moveTo(x, y)
                    first = false
                } else {
                    path.lineTo(x, y)
                }
            }
            drawPath(
                path = path,
                color = lineColor,
                style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round)
            )
            points.forEachIndexed { i, p ->
                val t = i.toFloat() / (points.size - 1).coerceAtLeast(1)
                val x = padL + w * t
                val nv = ((p.value - minY) / (maxY - minY)).toFloat().coerceIn(0f, 1f)
                val y = padT + h * (1f - nv)
                drawCircle(lineColor, 4.dp.toPx(), Offset(x, y))
            }
        }
    }
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        points.forEach { p ->
            Text(
                p.label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

data class DonutSegment(val label: String, val value: Double, val color: Color)

@Composable
fun KindDonutChart(
    segments: List<DonutSegment>,
    centerTitle: String,
    modifier: Modifier = Modifier
        .fillMaxWidth()
        .height(200.dp)
) {
    if (segments.isEmpty()) return
    val total = segments.sumOf { it.value }
    if (total <= 0) return
    Box(
        modifier = modifier,
        contentAlignment = Alignment.Center
    ) {
        val bg = Color.Gray.copy(alpha = 0.18f)
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 28.dp.toPx()
            val c = size.minDimension * 0.45f
            val left = (size.width - c) / 2f
            val top = (size.height - c) / 2f
            var start = -90f
            segments.forEach { s ->
                val sweep = (360.0 * (s.value / total)).toFloat()
                drawArc(
                    color = s.color,
                    startAngle = start,
                    sweepAngle = sweep,
                    useCenter = false,
                    topLeft = Offset(left, top),
                    size = Size(c, c),
                    style = Stroke(width = stroke)
                )
                start += sweep
            }
        }
        Text(
            centerTitle,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        segments.forEach { s ->
            val pct = ((s.value / total) * 100.0).toInt()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Canvas(Modifier.size(10.dp)) {
                    drawRect(s.color, size = size)
                }
                Text(
                    "${s.label} $pct%",
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(start = 4.dp)
                )
            }
        }
    }
}
