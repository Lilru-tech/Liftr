package com.lilru.liftr.ui.common

import androidx.compose.ui.geometry.Offset
import kotlin.math.abs

enum class FloatingDockEdge {
    LEFT,
    RIGHT,
    TOP,
    BOTTOM;

    companion object {
        fun fromRaw(raw: String?): FloatingDockEdge =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: RIGHT
    }
}

fun floatingEdgeAnchor(
    edge: FloatingDockEdge,
    position: Float,
    widthPx: Float,
    heightPx: Float,
    tabSizePx: Float,
    bottomInsetPx: Float = 0f
): Offset {
    val minX = tabSizePx / 2f
    val maxX = (widthPx - tabSizePx / 2f).coerceAtLeast(minX)
    val minY = tabSizePx / 2f + 10f
    val maxY = (heightPx - tabSizePx / 2f - bottomInsetPx).coerceAtLeast(minY)
    val p = position.coerceIn(0f, 1f)

    return when (edge) {
        FloatingDockEdge.LEFT -> Offset(minX, minY + (maxY - minY) * p)
        FloatingDockEdge.RIGHT -> Offset(maxX, minY + (maxY - minY) * p)
        FloatingDockEdge.TOP -> Offset(minX + (maxX - minX) * p, minY)
        FloatingDockEdge.BOTTOM -> Offset(minX + (maxX - minX) * p, maxY)
    }
}

fun floatingEdgeDock(
    point: Offset,
    widthPx: Float,
    heightPx: Float,
    tabSizePx: Float,
    bottomInsetPx: Float = 0f
): Pair<FloatingDockEdge, Float> {
    val minX = tabSizePx / 2f
    val maxX = (widthPx - tabSizePx / 2f).coerceAtLeast(minX)
    val minY = tabSizePx / 2f + 10f
    val maxY = (heightPx - tabSizePx / 2f - bottomInsetPx).coerceAtLeast(minY)
    val edge = listOf(
        FloatingDockEdge.LEFT to abs(point.x - minX),
        FloatingDockEdge.RIGHT to abs(point.x - maxX),
        FloatingDockEdge.TOP to abs(point.y - minY),
        FloatingDockEdge.BOTTOM to abs(point.y - maxY)
    ).minBy { it.second }.first

    val pos = when (edge) {
        FloatingDockEdge.LEFT, FloatingDockEdge.RIGHT ->
            ((point.y - minY) / (maxY - minY).coerceAtLeast(1f)).coerceIn(0f, 1f)
        FloatingDockEdge.TOP, FloatingDockEdge.BOTTOM ->
            ((point.x - minX) / (maxX - minX).coerceAtLeast(1f)).coerceIn(0f, 1f)
    }

    return edge to pos
}

const val FLOATING_DOCK_MERGE_THRESHOLD_PX = 56f
const val FLOATING_DOCK_UNMERGE_OFFSET = 0.08f

fun floatingDockDistance(a: Offset, b: Offset): Float {
    val dx = a.x - b.x
    val dy = a.y - b.y
    return kotlin.math.sqrt(dx * dx + dy * dy)
}

fun floatingDockShouldMerge(
    a: Offset,
    b: Offset,
    thresholdPx: Float = FLOATING_DOCK_MERGE_THRESHOLD_PX
): Boolean = floatingDockDistance(a, b) < thresholdPx

fun floatingDockUnmergePositions(
    edge: FloatingDockEdge,
    mergedPosition: Float,
    offset: Float = FLOATING_DOCK_UNMERGE_OFFSET
): Pair<Pair<FloatingDockEdge, Float>, Pair<FloatingDockEdge, Float>> {
    val merged = mergedPosition.coerceIn(0f, 1f)
    val chatPos = when (edge) {
        FloatingDockEdge.LEFT, FloatingDockEdge.RIGHT ->
            (merged - offset).coerceIn(0f, 1f)
        FloatingDockEdge.TOP, FloatingDockEdge.BOTTOM ->
            (merged - offset).coerceIn(0f, 1f)
    }
    val quickPos = when (edge) {
        FloatingDockEdge.LEFT, FloatingDockEdge.RIGHT ->
            (merged + offset).coerceIn(0f, 1f)
        FloatingDockEdge.TOP, FloatingDockEdge.BOTTOM ->
            (merged + offset).coerceIn(0f, 1f)
    }
    return (edge to chatPos) to (edge to quickPos)
}

fun migrateChatFabCorner(cornerRaw: String?): Pair<FloatingDockEdge, Float> = when (cornerRaw) {
    "BottomTrailing", "bottomTrailing" -> FloatingDockEdge.RIGHT to 1f
    "TopLeading", "topLeading" -> FloatingDockEdge.LEFT to 0f
    "TopTrailing", "topTrailing" -> FloatingDockEdge.RIGHT to 0f
    else -> FloatingDockEdge.LEFT to 1f
}
