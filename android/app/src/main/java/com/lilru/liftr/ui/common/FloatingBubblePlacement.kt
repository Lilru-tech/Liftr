package com.lilru.liftr.ui.common

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

fun floatingBubbleOrigin(
    anchor: Offset,
    edge: FloatingDockEdge,
    bubbleWidthPx: Float,
    bubbleHeightPx: Float,
    tabWidthPx: Float,
    tabHeightPx: Float,
    screenWidthPx: Float,
    screenHeightPx: Float,
    spacingPx: Float,
    marginPx: Float = 12f
): Offset {
    val tabHalfW = tabWidthPx / 2f
    val tabHalfH = tabHeightPx / 2f
    val raw = when (edge) {
        FloatingDockEdge.LEFT -> Offset(
            x = anchor.x + tabHalfW + spacingPx,
            y = anchor.y - bubbleHeightPx / 2f
        )
        FloatingDockEdge.RIGHT -> Offset(
            x = anchor.x - tabHalfW - spacingPx - bubbleWidthPx,
            y = anchor.y - bubbleHeightPx / 2f
        )
        FloatingDockEdge.TOP -> Offset(
            x = anchor.x - bubbleWidthPx / 2f,
            y = anchor.y + tabHalfH + spacingPx
        )
        FloatingDockEdge.BOTTOM -> Offset(
            x = anchor.x - bubbleWidthPx / 2f,
            y = anchor.y - tabHalfH - spacingPx - bubbleHeightPx
        )
    }

    val maxX = (screenWidthPx - bubbleWidthPx - marginPx).coerceAtLeast(marginPx)
    val maxY = (screenHeightPx - bubbleHeightPx - marginPx).coerceAtLeast(marginPx)

    return Offset(
        x = raw.x.coerceIn(marginPx, maxX),
        y = raw.y.coerceIn(marginPx, maxY)
    )
}

fun petGreetingBubbleOrigin(
    anchor: Offset,
    bubbleWidthPx: Float,
    bubbleHeightPx: Float,
    fabRadiusPx: Float,
    screenWidthPx: Float,
    screenHeightPx: Float,
    verticalGapPx: Float,
    marginPx: Float = 12f
): Offset {
    val idealX = anchor.x - bubbleWidthPx / 2f
    val maxX = (screenWidthPx - bubbleWidthPx - marginPx).coerceAtLeast(marginPx)
    val y = anchor.y - fabRadiusPx - verticalGapPx - bubbleHeightPx
    val maxY = (screenHeightPx - bubbleHeightPx - marginPx).coerceAtLeast(marginPx)

    return Offset(
        x = idealX.coerceIn(marginPx, maxX),
        y = y.coerceIn(marginPx, maxY)
    )
}

fun floatingBubbleOffset(
    anchor: Offset,
    edge: FloatingDockEdge,
    bubbleWidthPx: Float,
    bubbleHeightPx: Float,
    tabWidthPx: Float,
    tabHeightPx: Float,
    screenWidthPx: Float,
    screenHeightPx: Float,
    spacingPx: Float,
    marginPx: Float = 12f
): IntOffset {
    val origin = floatingBubbleOrigin(
        anchor = anchor,
        edge = edge,
        bubbleWidthPx = bubbleWidthPx,
        bubbleHeightPx = bubbleHeightPx,
        tabWidthPx = tabWidthPx,
        tabHeightPx = tabHeightPx,
        screenWidthPx = screenWidthPx,
        screenHeightPx = screenHeightPx,
        spacingPx = spacingPx,
        marginPx = marginPx
    )
    return IntOffset(origin.x.roundToInt(), origin.y.roundToInt())
}

fun Density.marginPx(): Float = 12.dp.toPx()
