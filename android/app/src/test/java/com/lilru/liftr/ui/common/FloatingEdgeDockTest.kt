package com.lilru.liftr.ui.common

import androidx.compose.ui.geometry.Offset
import org.junit.Assert.assertEquals
import org.junit.Test

class FloatingEdgeDockTest {

    @Test
    fun migrate_bottomTrailing_to_right_bottom() {
        val (edge, position) = migrateChatFabCorner("BottomTrailing")
        assertEquals(FloatingDockEdge.RIGHT, edge)
        assertEquals(1f, position)
    }

    @Test
    fun migrate_topLeading_to_left_top() {
        val (edge, position) = migrateChatFabCorner("TopLeading")
        assertEquals(FloatingDockEdge.LEFT, edge)
        assertEquals(0f, position)
    }

    @Test
    fun dock_snaps_to_right_edge_when_near_right() {
        val width = 400f
        val height = 800f
        val tab = 56f
        val (edge, _) = floatingEdgeDock(
            point = Offset(390f, 400f),
            widthPx = width,
            heightPx = height,
            tabSizePx = tab,
            bottomInsetPx = 72f
        )
        assertEquals(FloatingDockEdge.RIGHT, edge)
    }

    @Test
    fun should_merge_when_anchors_within_threshold() {
        val a = Offset(360f, 500f)
        val b = Offset(380f, 510f)
        assertEquals(true, floatingDockShouldMerge(a, b))
    }

    @Test
    fun should_not_merge_when_anchors_far_apart() {
        val a = Offset(360f, 500f)
        val b = Offset(360f, 200f)
        assertEquals(false, floatingDockShouldMerge(a, b))
    }

    @Test
    fun unmerge_offsets_chat_and_quick_along_same_edge() {
        val (chat, quick) = floatingDockUnmergePositions(FloatingDockEdge.RIGHT, 0.5f)
        assertEquals(FloatingDockEdge.RIGHT, chat.first)
        assertEquals(FloatingDockEdge.RIGHT, quick.first)
        assertEquals(0.42f, chat.second, 0.001f)
        assertEquals(0.58f, quick.second, 0.001f)
    }

    @Test
    fun anchor_right_bottom_matches_dock_position_one() {
        val width = 400f
        val height = 800f
        val tab = 56f
        val anchor = floatingEdgeAnchor(
            edge = FloatingDockEdge.RIGHT,
            position = 1f,
            widthPx = width,
            heightPx = height,
            tabSizePx = tab,
            bottomInsetPx = 72f
        )
        assertEquals(width - tab / 2f, anchor.x, 0.01f)
    }
}
