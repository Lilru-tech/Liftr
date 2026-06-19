package com.lilru.liftr.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.unit.Constraints
import kotlin.math.min

class HorizontalViewThatFitsScope internal constructor(
    internal val variants: MutableList<@Composable () -> Unit>
) {
    fun variant(content: @Composable () -> Unit) {
        variants.add(content)
    }
}

@Composable
fun HorizontalViewThatFits(
    modifier: Modifier = Modifier,
    content: @Composable HorizontalViewThatFitsScope.() -> Unit
) {
    val variantBuilders = remember { ArrayList<@Composable () -> Unit>(4) }
    variantBuilders.clear()
    HorizontalViewThatFitsScope(variantBuilders).content()

    if (variantBuilders.isEmpty()) return

    val variants = variantBuilders.toList()

    SubcomposeLayout(modifier = modifier) { constraints ->
        val maxWidth = constraints.maxWidth
        val intrinsicMeasure = constraints.copy(minWidth = 0, maxWidth = Constraints.Infinity)
        var selectedPlaceables: List<Placeable>? = null
        var selectedHeight = 0
        val slotPrefix = "v${variants.size}"

        for (index in variants.indices) {
            val placeables = subcompose("$slotPrefix-$index") {
                variants[index]()
            }.map { measurable ->
                measurable.measure(intrinsicMeasure)
            }

            val totalWidth = placeables.sumOf { it.width }
            if (totalWidth <= maxWidth) {
                selectedPlaceables = placeables
                selectedHeight = placeables.maxOfOrNull { it.height } ?: 0
                break
            }
        }

        if (selectedPlaceables == null) {
            val fallbackIndex = variants.lastIndex
            selectedPlaceables = subcompose("$slotPrefix-fallback-$fallbackIndex") {
                variants[fallbackIndex]()
            }.map { measurable ->
                measurable.measure(intrinsicMeasure)
            }
            selectedHeight = selectedPlaceables.maxOfOrNull { it.height } ?: 0
        }

        val placeables = selectedPlaceables ?: emptyList()
        val contentWidth = placeables.sumOf { it.width }
        val layoutWidth = min(contentWidth, maxWidth)
        layout(layoutWidth, selectedHeight) {
            var x = 0
            placeables.forEach { placeable ->
                placeable.placeRelative(x, 0)
                x += placeable.width
            }
        }
    }
}
