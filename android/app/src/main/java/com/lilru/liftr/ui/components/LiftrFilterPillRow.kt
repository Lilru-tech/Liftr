package com.lilru.liftr.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lilru.liftr.ui.theme.LiftrRadii
import dev.chrisbanes.haze.HazeState

enum class LiftrPillSelectedStyle {
    HomeTint,
    IosWhite
}

@Composable
fun LiftrFilterPillRow(
    labels: List<String>,
    selectedIndex: Int,
    onSelected: (Int) -> Unit,
    hazeState: HazeState,
    modifier: Modifier = Modifier,
    selectedStyle: LiftrPillSelectedStyle = LiftrPillSelectedStyle.HomeTint,
    scrollable: Boolean = false,
    compact: Boolean = false,
    pillWeights: List<Float>? = null
) {
    val textStyle = if (compact) {
        MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, lineHeight = 13.sp)
    } else {
        MaterialTheme.typography.labelLarge
    }
    val verticalPadding = if (compact) 7.dp else 10.dp
    val horizontalPadding = when {
        scrollable -> 12.dp
        compact -> 6.dp
        else -> 4.dp
    }
    val containerShape = RoundedCornerShape(LiftrRadii.bottomBar)
    LiftrGlassSurface(
        hazeState = hazeState,
        shape = containerShape,
        modifier = modifier.fillMaxWidth(),
        elevation = 4.dp,
        strokeAlpha = 0.18f
    ) {
        val rowModifier = Modifier
            .fillMaxWidth()
            .padding(4.dp)
            .then(if (scrollable) Modifier.horizontalScroll(rememberScrollState()) else Modifier)
        Row(
            modifier = rowModifier,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            labels.forEachIndexed { index, label ->
                val selected = index == selectedIndex
                val selectedBg = when (selectedStyle) {
                    LiftrPillSelectedStyle.HomeTint -> MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)
                    LiftrPillSelectedStyle.IosWhite -> Color.White.copy(alpha = 0.92f)
                }
                val bg by animateColorAsState(
                    targetValue = if (selected) selectedBg else Color.Transparent,
                    animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
                    label = "filterPillBg"
                )
                val scale by animateFloatAsState(
                    targetValue = if (selected) 1.02f else 1f,
                    animationSpec = spring(
                        dampingRatio = Spring.DampingRatioMediumBouncy,
                        stiffness = Spring.StiffnessMedium
                    ),
                    label = "filterPillScale"
                )
                Box(
                    modifier = Modifier
                        .then(
                            when {
                                scrollable -> Modifier
                                pillWeights != null && index < pillWeights.size -> Modifier.weight(pillWeights[index])
                                !scrollable -> Modifier.weight(1f)
                                else -> Modifier
                            }
                        )
                        .scale(scale)
                        .clip(RoundedCornerShape(LiftrRadii.filterSegment))
                        .background(bg)
                        .clickable(role = Role.Tab) { onSelected(index) }
                        .padding(vertical = verticalPadding, horizontal = horizontalPadding),
                    contentAlignment = Alignment.Center
                ) {
                    LiftrLabel(
                        text = label,
                        style = textStyle,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                        color = if (selected) {
                            MaterialTheme.colorScheme.onSurface
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                        maxLines = 1
                    )
                }
            }
        }
    }
}
