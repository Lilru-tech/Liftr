package com.lilru.liftr.ui.add

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.strengthRoutinesSheetDataStore by preferencesDataStore("liftr_strength_routines_sheet")

/**
 * Paridad con [Liftr.AddWorkoutSheet] `strengthRoutinesSheet.collapsedFolderIdsCSV` y `unfiledSectionCollapsed`.
 */
object StrengthRoutinesSheetPreferences {
    private val keyCsv = stringPreferencesKey("strength_routines_collapsed_folder_ids_csv")
    private val keyUnfiled = booleanPreferencesKey("strength_routines_unfiled_collapsed")

    data class State(
        val collapsedFolderIds: Set<Long> = emptySet(),
        val unfiledCollapsed: Boolean = false
    )

    suspend fun read(context: Context): State {
        val p = context.strengthRoutinesSheetDataStore.data.map { prefs ->
            val csv = prefs[keyCsv].orEmpty()
            val ids = if (csv.isBlank()) {
                emptySet()
            } else {
                csv.split(',')
                    .mapNotNull { it.trim().toLongOrNull() }
                    .toSet()
            }
            State(
                collapsedFolderIds = ids,
                unfiledCollapsed = prefs[keyUnfiled] ?: false
            )
        }
        return p.first()
    }

    suspend fun save(context: Context, folderIds: Set<Long>, unfiledCollapsed: Boolean) {
        val csv = folderIds.sorted().joinToString(",")
        context.strengthRoutinesSheetDataStore.edit { prefs ->
            prefs[keyCsv] = csv
            prefs[keyUnfiled] = unfiledCollapsed
        }
    }
}
