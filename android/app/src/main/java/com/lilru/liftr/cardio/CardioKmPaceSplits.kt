package com.lilru.liftr.cardio

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Paridad con [Liftr/CardioKmPaceSplits.swift] (merge de [stats] con clave [km_split_pace_sec]).
 */
object CardioKmPaceSplits {
    const val JSON_KEY = "km_split_pace_sec"

    fun formatFieldText(splits: List<Int>): String =
        splits.joinToString(", ") { sec ->
            val m = sec / 60
            val s = sec % 60
            String.format("%d:%02d", m, s)
        }

    /**
     * Paridad con [CardioKmPaceSplits.parseFieldText] en Swift: separadores `,` `;` o saltos, tokens `m:ss` o segundos.
     */
    fun parseFieldText(text: String): List<Int> {
        val raw = text.replace("·", ",").replace(";", ",")
        val parts = raw.split(',', '\n').map { it.trim() }.filter { it.isNotEmpty() }
        val out = ArrayList<Int>(parts.size)
        for (p in parts) {
            val token = p.lowercase().replace("/km", "").trim()
            val sec = parseSingleToken(token) ?: continue
            if (sec > 0) out.add(sec)
        }
        return out
    }

    private fun parseSingleToken(token: String): Int? {
        if (token.all { it.isDigit() }) return token.toIntOrNull()
        val bits = token.split(':').map { it.trim() }
        if (bits.size !in 2..3) return null
        val nums = bits.mapNotNull { it.toIntOrNull() }
        if (nums.size != bits.size) return null
        return when (nums.size) {
            2 -> nums[0] * 60 + nums[1]
            3 -> nums[0] * 3600 + nums[1] * 60 + nums[2]
            else -> null
        }
    }

    /**
     * [statsObject] = objeto JSON `stats` existente, o vacío. Inserta/actualiza [km_split_pace_sec] como [JsonArray] de enteros, o quita la clave si la lista es vacía.
     */
    fun mergeStatsObject(statsObject: JsonObject, kmSplitsPaceSec: List<Int>): JsonObject = buildJsonObject {
        statsObject.forEach { (k, v) ->
            if (k == JSON_KEY) return@forEach
            put(k, v)
        }
        if (kmSplitsPaceSec.isNotEmpty()) {
            put(
                JSON_KEY,
                JsonArray(kmSplitsPaceSec.map { JsonPrimitive(it) })
            )
        }
    }
}
