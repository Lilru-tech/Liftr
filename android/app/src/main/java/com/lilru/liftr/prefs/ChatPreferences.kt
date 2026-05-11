package com.lilru.liftr.prefs

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.chatDataStore by preferencesDataStore("liftr_chat")

/** Persistent preferences for the chat feature, mirroring iOS' @AppStorage values. */
object ChatPreferences {
    private val FAB_CORNER = stringPreferencesKey("chat_fab_corner")
    private val FAB_DRAG_HINT_SEEN = booleanPreferencesKey("chat_fab_drag_hint_seen")

    enum class FabCorner { BottomLeading, BottomTrailing, TopLeading, TopTrailing }

    fun fabCornerFlow(context: Context): Flow<FabCorner> =
        context.chatDataStore.data.map { p ->
            when (p[FAB_CORNER]) {
                FabCorner.BottomTrailing.name -> FabCorner.BottomTrailing
                FabCorner.TopLeading.name -> FabCorner.TopLeading
                FabCorner.TopTrailing.name -> FabCorner.TopTrailing
                else -> FabCorner.BottomLeading
            }
        }

    suspend fun setFabCorner(context: Context, corner: FabCorner) {
        context.chatDataStore.edit { it[FAB_CORNER] = corner.name }
    }

    fun fabDragHintSeenFlow(context: Context): Flow<Boolean> =
        context.chatDataStore.data.map { p -> p[FAB_DRAG_HINT_SEEN] == true }

    suspend fun setFabDragHintSeen(context: Context) {
        context.chatDataStore.edit { it[FAB_DRAG_HINT_SEEN] = true }
    }
}
