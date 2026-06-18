package com.lilru.liftr.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

object LiftrRadii {
    val card = 26.dp
    val cardLarge = 28.dp
    val pill = 50.dp
    val dockButton = 16.dp
    val bottomBar = 32.dp
    val filterSegment = 22.dp
    val scrollFab = 22.dp
}

object LiftrLayout {
    val floatingNavClearance = 80.dp
}

val LiftrShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(LiftrRadii.card),
    large = RoundedCornerShape(LiftrRadii.cardLarge),
    extraLarge = RoundedCornerShape(LiftrRadii.bottomBar)
)
