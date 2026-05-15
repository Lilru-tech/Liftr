package com.lilru.liftr.bodyweight

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.lilru.liftr.prefs.LiftrPreferences
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.temporal.ChronoUnit

data class BodyWeightImportSummary(
    var imported: Int = 0,
    var skippedDuplicate: Int = 0,
    var failed: Int = 0,
    val errorMessages: MutableList<String> = mutableListOf()
)

class HealthConnectBodyWeightSync(
    private val context: Context,
    private val supabase: SupabaseClient
) {
    private val client = BodyWeightClient(supabase)

    fun isSyncEnabled(context: Context): Boolean =
        LiftrPreferences.bodyWeightHealthSyncEnabled(context)

    fun setSyncEnabled(context: Context, enabled: Boolean) {
        LiftrPreferences.setBodyWeightHealthSyncEnabled(context, enabled)
    }

    fun lastSyncAt(context: Context): Instant? =
        LiftrPreferences.bodyWeightHealthLastSyncAt(context)

    suspend fun syncRecentSamples(): BodyWeightImportSummary {
        val from = Instant.now().minus(30, ChronoUnit.DAYS)
        return syncSamples(from, Instant.now())
    }

    suspend fun syncSamples(from: Instant, to: Instant): BodyWeightImportSummary = withContext(Dispatchers.IO) {
        val summary = BodyWeightImportSummary()
        val healthClient = runCatching { HealthConnectClient.getOrCreate(context) }.getOrNull()
        if (healthClient == null) {
            summary.failed += 1
            summary.errorMessages += "Health Connect is not available on this device."
            return@withContext summary
        }
        val perms = setOf(HealthPermission.getReadPermission(WeightRecord::class))
        if (!healthClient.permissionController.getGrantedPermissions().containsAll(perms)) {
            summary.failed += 1
            summary.errorMessages += "Health Connect weight permission is not granted."
            return@withContext summary
        }
        val records = runCatching {
            healthClient.readRecords(
                ReadRecordsRequest(
                    recordType = WeightRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(from, to)
                )
            ).records
        }.getOrElse {
            summary.failed += 1
            summary.errorMessages += it.message.orEmpty().ifBlank { "Could not read weight records." }
            return@withContext summary
        }
        for (record in records) {
            val kg = record.weight.inKilograms
            if (kg <= 0.0) {
                summary.failed += 1
                continue
            }
            runCatching {
                val result = client.upsertEntry(
                    measuredAt = record.time,
                    weightKg = kg,
                    source = BodyWeightSource.HealthConnect,
                    externalSampleId = record.metadata.id
                )
                when {
                    result.duplicate == true -> summary.skippedDuplicate += 1
                    result.inserted == true -> summary.imported += 1
                    else -> summary.skippedDuplicate += 1
                }
            }.onFailure {
                summary.failed += 1
                summary.errorMessages += it.message.orEmpty().ifBlank { "Could not save weight sample." }
            }
        }
        LiftrPreferences.setBodyWeightHealthLastSyncAt(context, Instant.now())
        summary
    }
}
