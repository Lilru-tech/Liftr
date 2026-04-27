package com.lilru.liftr.ui.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import kotlin.math.max

@Composable
fun HomeMonthLineChart(
    points: List<HomeMonthPoint>,
    modifier: Modifier = Modifier
) {
    if (points.isEmpty()) return
    val primary = MaterialTheme.colorScheme.primary
    val outline = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)
    val maxV = max(points.maxOf { it.value }, 1.0)
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(140.dp)
    ) {
        val w = size.width
        val h = size.height
        val pad = 8.dp.toPx()
        val n = points.size
        if (n < 2) return@Canvas
        val path = Path()
        points.forEachIndexed { i, p ->
            val x = pad + (w - 2 * pad) * (i / (n - 1f).coerceAtLeast(1f))
            val y = h - pad - (h - 2 * pad) * (p.value / maxV).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        drawPath(
            path = path,
            color = primary,
            style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round)
        )
        drawLine(
            color = outline,
            start = Offset(pad, h - pad),
            end = Offset(w - pad, h - pad),
            strokeWidth = 1.dp.toPx()
        )
    }
}
