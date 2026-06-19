package com.lilru.liftr.ui.components

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.lilru.liftr.ui.theme.rememberLiftrHazeBlurEnabled
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeChild

@Composable
fun liftrGlassStyle(): HazeStyle {
    val dark = (LocalConfiguration.current.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
        Configuration.UI_MODE_NIGHT_YES
    val background = if (dark) {
        Color(0xFF1C1C1E).copy(alpha = 0.72f)
    } else {
        Color.White.copy(alpha = 0.55f)
    }
    return HazeStyle(
        backgroundColor = background,
        blurRadius = 24.dp,
        tints = listOf(HazeTint(Color.White.copy(alpha = if (dark) 0.04f else 0.08f)))
    )
}

@Composable
fun liftrGlassFallbackColor(): Color {
    val dark = (LocalConfiguration.current.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
        Configuration.UI_MODE_NIGHT_YES
    return if (dark) {
        MaterialTheme.colorScheme.surface.copy(alpha = 0.82f)
    } else {
        Color.White.copy(alpha = 0.72f)
    }
}

@Composable
fun LiftrGlassSurface(
    hazeState: HazeState,
    shape: Shape,
    modifier: Modifier = Modifier,
    elevation: Dp = 8.dp,
    strokeAlpha: Float = 0.2f,
    blurEnabled: Boolean = rememberLiftrHazeBlurEnabled(),
    content: @Composable BoxScope.() -> Unit
) {
    val style = liftrGlassStyle()
    val glassModifier = modifier
        .shadow(
            elevation = elevation,
            shape = shape,
            ambientColor = Color.Black.copy(alpha = 0.12f),
            spotColor = Color.Black.copy(alpha = 0.18f)
        )
        .then(
            if (blurEnabled) {
                Modifier.hazeChild(state = hazeState, style = style)
            } else {
                Modifier
                    .clip(shape)
                    .background(liftrGlassFallbackColor())
            }
        )
        .border(0.8.dp, Color.White.copy(alpha = strokeAlpha), shape)

    Box(modifier = glassModifier, content = content)
}

@Composable
fun LiftrGlassCircle(
    hazeState: HazeState,
    modifier: Modifier = Modifier,
    blurEnabled: Boolean = rememberLiftrHazeBlurEnabled(),
    content: @Composable BoxScope.() -> Unit
) {
    LiftrGlassSurface(
        hazeState = hazeState,
        shape = androidx.compose.foundation.shape.CircleShape,
        modifier = modifier,
        elevation = 4.dp,
        strokeAlpha = 0.2f,
        blurEnabled = blurEnabled,
        content = content
    )
}
