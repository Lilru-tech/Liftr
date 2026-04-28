package com.lilru.liftr.data

import android.content.Context
import com.lilru.liftr.BuildConfig
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.storage.Storage
import io.github.jan.supabase.SupabaseClient

/**
 * Análogo al `SupabaseManager` de iOS: cliente único reutilizable.
 * La URL y la clave pública anónima se inyectan en `BuildConfig` leyendo `local.properties` en el módulo `android/`.
 */
object LiftrSupabase {
    @Volatile
    var client: SupabaseClient? = null
        private set

    /**
     * Debe llamarse al arranque (p. ej. desde [com.lilru.liftr.LiftrApplication]).
     * Si faltan URL o clave, [client] permanece nulo: la UI puede mostrar un aviso.
     */
    fun init(@Suppress("UNUSED_PARAMETER") context: Context) {
        if (client != null) return
        val url = BuildConfig.SUPABASE_URL
        val key = BuildConfig.SUPABASE_ANON_KEY
        if (url.isBlank() || key.isBlank()) {
            return
        }
        runCatching {
            createSupabaseClient(
                supabaseUrl = url,
                supabaseKey = key
            ) {
                install(Postgrest)
                install(Storage) { }
                install(Auth) { }
                install(Functions) { }
            }
        }.onSuccess { c ->
            client = c
        }
        // onFailure: client sigue null; la UI indica “configurar” (evitamos crashear en Application).
    }
}
