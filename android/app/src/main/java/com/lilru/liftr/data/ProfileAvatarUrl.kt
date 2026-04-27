package com.lilru.liftr.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray

/**
 * Lee [profiles.avatar_url] con un parser JSON mínimo (misma lógica que el icono de perfil en
 * [com.lilru.liftr.ui.main.MainShellScreen]).
 * Sirve de respaldo cuando [SupabaseResponseDecoding] devuelve lista vacía (p. ej. fallo
 * al deserializar otra columna de la fila) y [ProfileViewModel] se quedaba sin avatar mientras
 * el bottom bar seguía mostrándolo.
 */
suspend fun loadProfileAvatarUrl(
    supabase: SupabaseClient,
    userId: String
): String? = withContext(Dispatchers.IO) {
    runCatching {
        val raw =
            supabase
                .from(BackendContracts.Tables.PROFILES)
                .select(columns = Columns.raw("avatar_url")) {
                    filter { eq("user_id", userId) }
                    limit(1)
                }
                .data
        val t = raw.trim()
        if (t.isEmpty()) return@runCatching null
        val arr = JSONArray(if (t.startsWith("[")) t else "[$t]")
        if (arr.length() == 0) return@runCatching null
        arr.getJSONObject(0).optString("avatar_url", "").trim().takeIf { it.isNotEmpty() }
    }.getOrNull()
}
