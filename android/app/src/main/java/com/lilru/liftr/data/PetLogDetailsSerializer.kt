package com.lilru.liftr.data

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

@OptIn(ExperimentalSerializationApi::class)
object PetLogDetailsSerializer : KSerializer<Map<String, String>?> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("PetLogDetails")

    override fun deserialize(decoder: Decoder): Map<String, String>? {
        val input = decoder as? JsonDecoder ?: return null
        return when (val element = input.decodeJsonElement()) {
            is JsonNull -> null
            is JsonObject -> element.mapValues { (_, value) ->
                when (value) {
                    is JsonPrimitive -> value.contentOrNull ?: value.toString()
                    else -> value.toString()
                }
            }
            else -> null
        }
    }

    override fun serialize(encoder: Encoder, value: Map<String, String>?) {
        val output = encoder as JsonEncoder
        if (value == null) {
            output.encodeNull()
            return
        }
        output.encodeJsonElement(
            buildJsonObject {
                value.forEach { (key, entry) -> put(key, entry) }
            }
        )
    }
}
