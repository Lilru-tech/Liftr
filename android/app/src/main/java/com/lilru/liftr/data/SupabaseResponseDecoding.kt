package com.lilru.liftr.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

/**
 * PostgREST en supabase-kt a veces devuelve el cuerpo como `[{...}]` y otras como
 * `{"data":[{...}]}`. Sin desempaquetar `data`, [kotlinx.serialization] no decodifica filas
 * y la UI queda sin username/avatar, workouts, etc.
 */
object SupabaseResponseDecoding {
    val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    inline fun <reified T> decodeListOrObject(raw: String): List<T> {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return emptyList()
        return runCatching {
            val root = json.parseToJsonElement(trimmed)
            when (root) {
                is JsonArray -> root.map { el -> json.decodeFromString<T>(el.toString()) }
                is JsonObject -> {
                    when (val data = root["data"]) {
                        is JsonArray -> data.map { el -> json.decodeFromString<T>(el.toString()) }
                        is JsonObject -> listOf(json.decodeFromString<T>(data.toString()))
                        else -> listOf(json.decodeFromString<T>(root.toString()))
                    }
                }
                else -> emptyList()
            }
        }.getOrDefault(emptyList())
    }
}
