package com.lilru.liftr.ui.theme

import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.drawBehind

/**
 * Colores alineados con [Liftr/GradientBackground.swift] `gradientColors` (mismos id que iOS
 * [ProfileView] `backgroundTheme` / @AppStorage).
 */
fun liftrBackgroundGradientPair(themeId: String): Pair<Color, Color> {
    val o = { c: Color, a: Float -> c.copy(alpha = a) }
    return when (themeId) {
        "sunset" -> o(Color(0xFFFF9500), 0.6f) to o(Color(0xFFFF2D55), 0.55f) // orange, pink
        "forest" -> o(Color(0xFF34C759), 0.55f) to o(Color(0xFF5AC8FA), 0.55f) // green, teal
        "midnight" -> o(Color.Black, 0.9f) to o(Color(0xFF007AFF), 0.7f) // black, blue
        "lavender" -> o(Color(0xFFAF52DE), 0.45f) to o(Color(0xFF007AFF), 0.45f) // purple, blue
        "ocean" -> o(Color(0xFF5AC8FA), 0.55f) to o(Color(0xFF007AFF), 0.55f) // cyan, blue
        "rose" -> o(Color(0xFFFF2D55), 0.55f) to o(Color(0xFFAF52DE), 0.45f) // pink, purple
        "desert" -> o(Color(0xFFFFCC00), 0.45f) to o(Color(0xFFFF9500), 0.4f) // yellow, orange
        "berry" -> o(Color(0xFFFF3B30), 0.45f) to o(Color(0xFF5856D6), 0.55f) // red, indigo
        "mono" -> o(Color.Gray, 0.55f) to o(Color.Black, 0.55f)
        else -> o(Color(0xFF2ECC71), 0.6f) to o(Color(0xFF007AFF), 0.5f) // mint/blue “mintBlue” default
    }
}

/**
 * Gradiente diagonal (arriba-izquierda → abajo-derecha) como
 * [GradientBackground] `startPoint: .topLeading, endPoint: .bottomTrailing`.
 */
fun Modifier.liftrAppBackgroundGradient(themeId: String): Modifier = this.drawBehind {
    val (c0, c1) = liftrBackgroundGradientPair(themeId)
    drawRect(
        brush = Brush.linearGradient(
            colors = listOf(c0, c1),
            start = Offset(0f, 0f),
            end = Offset(size.width, size.height)
        )
    )
}
