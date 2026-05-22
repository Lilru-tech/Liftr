package com.lilru.liftr.prefs

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.lilru.liftr.ui.common.FloatingDockEdge
import com.lilru.liftr.ui.common.migrateChatFabCorner
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.chatDataStore by preferencesDataStore("liftr_chat")

data class ChatFabDockState(
    val edge: FloatingDockEdge,
    val position: Float
)

object ChatPreferences {
    private val FAB_EDGE = stringPreferencesKey("chat_fab_edge")
    private val FAB_POSITION = floatPreferencesKey("chat_fab_position")
    private val FAB_CORNER = stringPreferencesKey("chat_fab_corner")
    private val FAB_DRAG_HINT_SEEN = booleanPreferencesKey("chat_fab_drag_hint_seen")

    @Deprecated("Legacy corner storage; migrated to edge + position.")
    enum class FabCorner { BottomLeading, BottomTrailing, TopLeading, TopTrailing }

    fun fabDockFlow(context: Context): Flow<ChatFabDockState> =
        context.chatDataStore.data.map { prefs ->
            val edgeRaw = prefs[FAB_EDGE]
            val position = prefs[FAB_POSITION]
            if (edgeRaw != null && position != null) {
                ChatFabDockState(
                    edge = FloatingDockEdge.fromRaw(edgeRaw),
                    position = position.coerceIn(0f, 1f)
                )
            } else {
                val (edge, position) = migrateChatFabCorner(prefs[FAB_CORNER])
                ChatFabDockState(edge = edge, position = position)
            }
        }

    suspend fun setFabDock(context: Context, edge: FloatingDockEdge, position: Float) {
        context.chatDataStore.edit {
            it[FAB_EDGE] = edge.name
            it[FAB_POSITION] = position.coerceIn(0f, 1f)
        }
    }

    fun fabDragHintSeenFlow(context: Context): Flow<Boolean> =
        context.chatDataStore.data.map { p -> p[FAB_DRAG_HINT_SEEN] == true }

    suspend fun setFabDragHintSeen(context: Context) {
        context.chatDataStore.edit { it[FAB_DRAG_HINT_SEEN] = true }
    }
}
