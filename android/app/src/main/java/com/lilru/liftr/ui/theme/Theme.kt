package com.lilru.liftr.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import android.content.res.Configuration
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration

private val DarkColors = darkColorScheme(
    primary = Color(0xFF6EE7A8),
    background = Color(0xFF0F1419),
    surface = Color(0xFF1A1F26)
)

private val LightColors = lightColorScheme(
    primary = Color(0xFF0D7A4F),
    background = Color(0xFFF5F5F5),
    surface = Color(0xFFFFFFFF)
)

@Composable
fun LiftrTheme(content: @Composable () -> Unit) {
    val dark = (LocalConfiguration.current.uiMode
        and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val scheme = if (dark) DarkColors else LightColors
    MaterialTheme(
        colorScheme = scheme,
        typography = MaterialTheme.typography,
        content = content
    )
}
