package com.lilru.liftr.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.layout.SubcomposeLayout

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
    val variants = remember { mutableStateListOf<@Composable () -> Unit>() }
    variants.clear()
    HorizontalViewThatFitsScope(variants).content()

    if (variants.isEmpty()) return

    SubcomposeLayout(modifier = modifier) { constraints ->
        val maxWidth = constraints.maxWidth
        var selectedPlaceables: List<Placeable>? = null
        var selectedHeight = 0

        for (index in variants.indices) {
            val placeables = subcompose("variant_$index") {
                variants[index]()
            }.map { measurable ->
                measurable.measure(
                    constraints.copy(
                        minWidth = 0,
                        maxWidth = maxWidth
                    )
                )
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
            selectedPlaceables = subcompose("variant_fallback_$fallbackIndex") {
                variants[fallbackIndex]()
            }.map { measurable ->
                measurable.measure(
                    constraints.copy(
                        minWidth = 0,
                        maxWidth = maxWidth
                    )
                )
            }
            selectedHeight = selectedPlaceables.maxOfOrNull { it.height } ?: 0
        }

        val placeables = selectedPlaceables ?: emptyList()
        val contentWidth = placeables.sumOf { it.width }
        layout(contentWidth, selectedHeight) {
            placeables.forEach { placeable ->
                placeable.placeRelative(0, 0)
            }
        }
    }
}
