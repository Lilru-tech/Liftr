package com.lilru.liftr.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.lilru.liftr.ui.theme.LiftrRadii
import com.lilru.liftr.ui.theme.rememberLiftrHazeBlurEnabled
import dev.chrisbanes.haze.HazeState

@Composable
fun LiftrChatFab(
    modifier: Modifier = Modifier,
    contentDescription: String = "Open messages"
) {
    Box(
        modifier = modifier
            .size(56.dp)
            .shadow(
                elevation = 6.dp,
                shape = CircleShape,
                ambientColor = Color.Black.copy(alpha = 0.25f),
                spotColor = Color.Black.copy(alpha = 0.25f)
            )
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primary),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Filled.Send,
            contentDescription = contentDescription,
            tint = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier.size(22.dp)
        )
    }
}

@Composable
fun LiftrQuickActionFab(
    hazeState: HazeState,
    busy: Boolean,
    modifier: Modifier = Modifier,
    blurEnabled: Boolean = rememberLiftrHazeBlurEnabled()
) {
    val shape = RoundedCornerShape(LiftrRadii.dockButton)
    LiftrGlassSurface(
        hazeState = hazeState,
        shape = shape,
        modifier = modifier.size(width = 56.dp, height = 52.dp),
        elevation = 6.dp,
        strokeAlpha = 0.22f,
        blurEnabled = blurEnabled
    ) {
        Box(
            modifier = Modifier.size(width = 56.dp, height = 52.dp),
            contentAlignment = Alignment.Center
        ) {
            if (busy) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp
                )
            } else {
                Text("⚡", style = MaterialTheme.typography.titleLarge, color = Color(0xFFFFD600))
            }
        }
    }
}
