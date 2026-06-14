package com.lilru.liftr.ui.pets

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

private fun hpBarColor(ratio: Float): Color {
    val percent = ratio * 100f
    return when {
        percent >= 80f -> Color(0xFF22C55E)
        percent >= 60f -> Color(0xFFEAB308)
        percent >= 40f -> Color(0xFFF97316)
        percent >= 20f -> Color(0xFFEF4444)
        else -> Color(0xFF991B1B)
    }
}

@Composable
fun PetCombatHpBar(
    current: Int,
    max: Int,
    modifier: Modifier = Modifier
) {
    val safeMax = maxOf(max, 1)
    val ratio = (current.toFloat() / safeMax.toFloat()).coerceIn(0f, 1f)
    val animatedRatio by animateFloatAsState(
        targetValue = ratio,
        animationSpec = tween(durationMillis = 350),
        label = "hpRatio"
    )

    Column(modifier = modifier, horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(50))
                .background(Color.White.copy(alpha = 0.18f))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(animatedRatio)
                    .clip(RoundedCornerShape(50))
                    .background(hpBarColor(animatedRatio))
            )
        }
        Text(
            text = "$current/$safeMax HP",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth()
        )
    }
}
