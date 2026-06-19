package com.lilru.liftr.ui.theme

import android.content.res.Configuration
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.platform.LocalConfiguration

private fun Color.atAlpha(alpha: Float): Color = copy(alpha = alpha)

private data class GradientStops(val c0: Color, val c1: Color)

fun liftrBackgroundGradientPair(themeId: String): Pair<Color, Color> {
    val stops = liftrBackgroundGradientStops(themeId)
    return stops.c0 to stops.c1
}

private fun liftrBackgroundGradientStops(themeId: String): GradientStops = when (themeId) {
    "sunset" -> GradientStops(Color(0xFFFF9500), Color(0xFFFF2D55))
    "forest" -> GradientStops(Color(0xFF34C759), Color(0xFF5AC8FA))
    "midnight" -> GradientStops(Color.Black, Color(0xFF007AFF))
    "lavender" -> GradientStops(Color(0xFFAF52DE), Color(0xFF007AFF))
    "ocean" -> GradientStops(Color(0xFF5AC8FA), Color(0xFF007AFF))
    "rose" -> GradientStops(Color(0xFFFF2D55), Color(0xFFAF52DE))
    "desert" -> GradientStops(Color(0xFFFFCC00), Color(0xFFFF9500))
    "berry" -> GradientStops(Color(0xFFFF3B30), Color(0xFF5856D6))
    "mono" -> GradientStops(Color.Gray, Color.Black)
    else -> GradientStops(Color(0xFF2ECC71), Color(0xFF007AFF))
}

private fun liftrBackgroundAlphaStops(themeId: String): List<Pair<Float, Color>> {
    val (c0, c1) = liftrBackgroundGradientStops(themeId)
    return when (themeId) {
        "sunset" -> listOf(
            0f to c0.atAlpha(0.6f),
            0.35f to c0.atAlpha(0.45f),
            0.65f to c1.atAlpha(0.48f),
            1f to c1.atAlpha(0.55f)
        )
        "forest" -> listOf(
            0f to c0.atAlpha(0.55f),
            0.35f to c0.atAlpha(0.42f),
            0.65f to c1.atAlpha(0.45f),
            1f to c1.atAlpha(0.55f)
        )
        "midnight" -> listOf(
            0f to c0.atAlpha(0.9f),
            0.35f to c0.atAlpha(0.75f),
            0.65f to c1.atAlpha(0.62f),
            1f to c1.atAlpha(0.7f)
        )
        "lavender" -> listOf(
            0f to c0.atAlpha(0.45f),
            0.35f to c0.atAlpha(0.36f),
            0.65f to c1.atAlpha(0.38f),
            1f to c1.atAlpha(0.45f)
        )
        "ocean" -> listOf(
            0f to c0.atAlpha(0.55f),
            0.35f to c0.atAlpha(0.44f),
            0.65f to c1.atAlpha(0.48f),
            1f to c1.atAlpha(0.55f)
        )
        "rose" -> listOf(
            0f to c0.atAlpha(0.55f),
            0.35f to c0.atAlpha(0.4f),
            0.65f to c1.atAlpha(0.38f),
            1f to c1.atAlpha(0.45f)
        )
        "desert" -> listOf(
            0f to c0.atAlpha(0.45f),
            0.35f to c0.atAlpha(0.36f),
            0.65f to c1.atAlpha(0.34f),
            1f to c1.atAlpha(0.4f)
        )
        "berry" -> listOf(
            0f to c0.atAlpha(0.45f),
            0.35f to c0.atAlpha(0.38f),
            0.65f to c1.atAlpha(0.48f),
            1f to c1.atAlpha(0.55f)
        )
        "mono" -> listOf(
            0f to c0.atAlpha(0.55f),
            0.35f to c0.atAlpha(0.45f),
            0.65f to c1.atAlpha(0.48f),
            1f to c1.atAlpha(0.55f)
        )
        else -> listOf(
            0f to c0.atAlpha(0.6f),
            0.35f to c0.atAlpha(0.48f),
            0.65f to c1.atAlpha(0.44f),
            1f to c1.atAlpha(0.5f)
        )
    }
}

private fun liftrGradientBaseWash(dark: Boolean): Color =
    if (dark) Color(0xFF0F1419) else Color(0xFFF2F2F7)

private fun liftrBloomAccent(themeId: String): Color? = when (themeId) {
    "lavender" -> Color(0xFFAF52DE)
    "rose" -> Color(0xFFFF2D55)
    else -> null
}

@Composable
fun Modifier.liftrAppBackgroundGradient(themeId: String): Modifier {
    val dark = (LocalConfiguration.current.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
        Configuration.UI_MODE_NIGHT_YES
    return drawLiftrGradient(themeId, dark = dark, opaque = false)
}

@Composable
fun Modifier.liftrAppBackgroundGradientOpaque(themeId: String): Modifier {
    val dark = (LocalConfiguration.current.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
        Configuration.UI_MODE_NIGHT_YES
    return drawLiftrGradient(themeId, dark = dark, opaque = true)
}

private fun Modifier.drawLiftrGradient(themeId: String, dark: Boolean, opaque: Boolean): Modifier =
    this.drawBehind {
        drawRect(liftrGradientBaseWash(dark))
        val stops = liftrBackgroundAlphaStops(themeId).map { (stop, color) ->
            stop to if (opaque) color.copy(alpha = 1f) else color
        }
        drawRect(
            brush = Brush.linearGradient(
                colorStops = stops.toTypedArray(),
                start = Offset(0f, 0f),
                end = Offset(size.width, size.height)
            )
        )
        liftrBloomAccent(themeId)?.let { bloom ->
            drawRect(
                brush = Brush.radialGradient(
                    colors = listOf(
                        bloom.copy(alpha = if (opaque) 0.12f else 0.08f),
                        Color.Transparent
                    ),
                    center = Offset(size.width * 0.15f, size.height * 0.1f),
                    radius = size.width.coerceAtLeast(size.height) * 0.75f
                )
            )
        }
    }
