package com.lilru.liftr.bodyweight

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

enum class BodyWeightSource(val wire: String) {
    Manual("manual"),
    AppleHealth("apple_health"),
    HealthConnect("health_connect");

    companion object {
        fun fromWire(value: String): BodyWeightSource =
            entries.firstOrNull { it.wire == value } ?: Manual
    }
}

@Serializable
data class BodyWeightEntryWire(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("measured_at") val measuredAt: String,
    @SerialName("weight_kg") val weightKg: Double,
    val source: String,
    @SerialName("external_sample_id") val externalSampleId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
data class BodyWeightUpsertResultWire(
    @SerialName("entry_id") val entryId: String? = null,
    val inserted: Boolean? = null,
    val duplicate: Boolean? = null
)

data class BodyWeightChartPoint(
    val id: String,
    val label: String,
    val value: Double,
    val measuredAt: Instant
)

enum class BodyWeightRangePreset(val title: String, val days: Int) {
    Days30("30 days", 30),
    Days90("90 days", 90),
    Days365("365 days", 365)
}

object BodyWeightPresentation {
    fun formatKg(value: Double): String = String.format(Locale.US, "%.1f kg", value)

    fun deltaText(current: Double, previous: Double?): String? {
        if (previous == null) return null
        val delta = current - previous
        if (abs(delta) < 0.05) return "No change vs previous entry"
        val sign = if (delta > 0) "+" else ""
        return "$sign${String.format(Locale.US, "%.1f", delta)} kg vs previous entry"
    }

    fun periodDeltaText(entries: List<BodyWeightEntryWire>, days: Int, now: Instant = Instant.now()): String? {
        val sorted = entries.sortedBy { it.measuredAt }
        val latest = sorted.lastOrNull() ?: return null
        val cutoff = now.minusSeconds(days.toLong() * 86_400L)
        val baseline = sorted.lastOrNull { Instant.parse(it.measuredAt) <= cutoff } ?: sorted.firstOrNull()
        if (baseline == null) return null
        val delta = latest.weightKg - baseline.weightKg
        if (abs(delta) < 0.05) return "No net change in the last $days days"
        val sign = if (delta > 0) "+" else ""
        return "$sign${String.format(Locale.US, "%.1f", delta)} kg in the last $days days"
    }

    fun chartPoints(entries: List<BodyWeightEntryWire>, preset: BodyWeightRangePreset, now: Instant = Instant.now()): List<BodyWeightChartPoint> {
        val start = now.minusSeconds(preset.days.toLong() * 86_400L)
        val formatter = DateTimeFormatter.ofPattern("d MMM").withLocale(Locale.getDefault())
        return entries
            .mapNotNull { entry ->
                val instant = runCatching { Instant.parse(entry.measuredAt) }.getOrNull() ?: return@mapNotNull null
                if (instant.isBefore(start)) return@mapNotNull null
                BodyWeightChartPoint(
                    id = entry.id,
                    label = formatter.format(instant.atZone(ZoneOffset.systemDefault())),
                    value = entry.weightKg,
                    measuredAt = instant
                )
            }
            .sortedBy { it.measuredAt }
    }

    fun sourceLabel(source: BodyWeightSource): String = when (source) {
        BodyWeightSource.Manual -> "Manual"
        BodyWeightSource.AppleHealth -> "Apple Health"
        BodyWeightSource.HealthConnect -> "Health Connect"
    }
}

class BodyWeightClient(
    private val supabase: SupabaseClient
) {
    suspend fun listEntries(limit: Int = 500): List<BodyWeightEntryWire> {
        return supabase.from(BackendContracts.Tables.BODY_WEIGHT_ENTRIES).select {
            order(column = "measured_at", order = Order.DESCENDING)
            limit(count = limit.toLong())
        }.decodeList<BodyWeightEntryWire>()
    }

    suspend fun upsertEntry(
        measuredAt: Instant,
        weightKg: Double,
        source: BodyWeightSource,
        externalSampleId: String? = null
    ): BodyWeightUpsertResultWire {
        val params = buildJsonObject {
            put("p_measured_at", JsonPrimitive(measuredAt.toString()))
            put("p_weight_kg", JsonPrimitive(weightKg))
            put("p_source", JsonPrimitive(source.wire))
            externalSampleId?.let { put("p_external_sample_id", JsonPrimitive(it)) }
        }
        return supabase.postgrest.rpc(BackendContracts.Rpc.UPSERT_BODY_WEIGHT_ENTRY, params)
            .decodeAs<BodyWeightUpsertResultWire>()
    }

    suspend fun deleteEntry(id: String) {
        supabase.from(BackendContracts.Tables.BODY_WEIGHT_ENTRIES).delete {
            filter { eq("id", id) }
        }
    }
}
