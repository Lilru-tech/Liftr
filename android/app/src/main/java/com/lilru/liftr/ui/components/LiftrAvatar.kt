package com.lilru.liftr.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage

/**
 * Foto de perfil circular; si no hay URL, muestra la inicial del nombre (comportamiento alineado a [AvatarView] en iOS).
 */
@Composable
fun LiftrAvatar(
    imageUrl: String?,
    displayName: String?,
    modifier: Modifier = Modifier,
    size: Dp = 48.dp
) {
    val label: String = displayName
        ?.firstOrNull { it.isLetterOrDigit() }
        ?.let { it.uppercase() }
        ?: "?"
    val surface = MaterialTheme.colorScheme.primaryContainer
    val onSurface = MaterialTheme.colorScheme.onPrimaryContainer
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(surface),
        contentAlignment = Alignment.Center
    ) {
        if (imageUrl.isNullOrBlank()) {
            Text(
                text = label,
                color = onSurface,
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.titleLarge.copy(
                    fontSize = (size.value * 0.4f).sp
                )
            )
        } else {
            AsyncImage(
                model = imageUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(size)
                    .clip(CircleShape)
            )
        }
    }
}
