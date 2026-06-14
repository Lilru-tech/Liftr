package com.lilru.liftr.ui.pets

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.hypot

data class ProfilePetFabBounds(
    val minX: Float,
    val maxX: Float,
    val minY: Float,
    val maxY: Float
) {
    val width: Float get() = maxX - minX
    val height: Float get() = maxY - minY
    val perimeter: Float get() = 2f * (width + height)
}

object ProfilePetFabPosition {
    private const val FAB_SIZE_DP = 90f
    private const val EDGE_PADDING_DP = 8f

    val fabSize: Dp = FAB_SIZE_DP.dp

    fun bounds(
        widthPx: Float,
        heightPx: Float,
        topInsetPx: Float,
        bottomInsetPx: Float,
        bottomInsetDp: Int,
        density: Density
    ): ProfilePetFabBounds {
        val fabRadiusPx = with(density) { FAB_SIZE_DP.dp.toPx() } / 2f
        val paddingPx = with(density) { EDGE_PADDING_DP.dp.toPx() }
        val tabBarPx = with(density) { 49.dp.toPx() }
        val bannerPx = with(density) { bottomInsetDp.dp.toPx() }

        return ProfilePetFabBounds(
            minX = fabRadiusPx + paddingPx,
            maxX = widthPx - fabRadiusPx - paddingPx,
            minY = topInsetPx + fabRadiusPx + paddingPx,
            maxY = heightPx - bottomInsetPx - tabBarPx - bannerPx - fabRadiusPx - paddingPx
        )
    }

    fun defaultPerimeterT(bounds: ProfilePetFabBounds): Float =
        perimeterParameterFor(Offset(bounds.maxX, bounds.maxY), bounds)

    fun pointOnPerimeter(t: Float, bounds: ProfilePetFabBounds): Offset {
        val perimeter = bounds.perimeter.coerceAtLeast(1f)
        var distance = t % 1f
        if (distance < 0f) distance += 1f
        distance *= perimeter

        val w = bounds.width
        val h = bounds.height

        return when {
            distance <= w -> Offset(bounds.minX + distance, bounds.minY)
            distance <= w + h -> Offset(bounds.maxX, bounds.minY + (distance - w))
            distance <= 2f * w + h -> Offset(bounds.maxX - (distance - w - h), bounds.maxY)
            else -> Offset(bounds.minX, bounds.maxY - (distance - 2f * w - h))
        }
    }

    fun perimeterParameterFor(point: Offset, bounds: ProfilePetFabBounds): Float {
        val snapped = nearestPointOnPerimeter(point, bounds)
        val w = bounds.width
        val h = bounds.height
        val perimeter = bounds.perimeter.coerceAtLeast(1f)

        return when {
            snapped.y == bounds.minY -> (snapped.x - bounds.minX) / perimeter
            snapped.x == bounds.maxX -> (w + (snapped.y - bounds.minY)) / perimeter
            snapped.y == bounds.maxY -> (w + h + (bounds.maxX - snapped.x)) / perimeter
            else -> (w + h + w + (bounds.maxY - snapped.y)) / perimeter
        }.coerceIn(0f, 1f)
    }

    fun nearestPointOnPerimeter(point: Offset, bounds: ProfilePetFabBounds): Offset {
        val candidates = listOf(
            Offset(point.x.coerceIn(bounds.minX, bounds.maxX), bounds.minY),
            Offset(bounds.maxX, point.y.coerceIn(bounds.minY, bounds.maxY)),
            Offset(point.x.coerceIn(bounds.minX, bounds.maxX), bounds.maxY),
            Offset(bounds.minX, point.y.coerceIn(bounds.minY, bounds.maxY))
        )
        return candidates.minByOrNull {
            hypot(it.x - point.x, it.y - point.y)
        } ?: candidates.first()
    }

    fun resolvedPerimeterT(
        saved: Float?,
        legacyX: Float?,
        legacyY: Float?,
        bounds: ProfilePetFabBounds
    ): Float {
        if (saved != null) return saved.coerceIn(0f, 1f)
        if (legacyX != null && legacyY != null) {
            val legacyPoint = Offset(
                x = bounds.minX + legacyX.coerceIn(0f, 1f) * bounds.width.coerceAtLeast(1f),
                y = bounds.minY + legacyY.coerceIn(0f, 1f) * bounds.height.coerceAtLeast(1f)
            )
            return perimeterParameterFor(legacyPoint, bounds)
        }
        return defaultPerimeterT(bounds)
    }
}
