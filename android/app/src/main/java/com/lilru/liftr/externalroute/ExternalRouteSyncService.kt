package com.lilru.liftr.externalroute

import android.content.Context
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.lilru.liftr.ui.health.healthConnectWorkoutExternalId
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

data class ExternalRouteSyncSummary(
    var applied: Int = 0,
    var skipped: Int = 0,
    var failed: Int = 0,
    var errorMessages: List<String> = emptyList()
)

@Serializable
private data class ExternalRoutePointWire(
    val lat: Double,
    val lon: Double,
    val alt: Double? = null,
    val ts: String? = null
)

@Serializable
private data class ExternalRouteJobWire(
    val id: String,
    val provider: String,
    @SerialName("provider_activity_id") val providerActivityId: String,
    @SerialName("started_at") val startedAt: String,
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("activity_code") val activityCode: String? = null,
    @SerialName("route_points") val routePoints: List<ExternalRoutePointWire> = emptyList()
)

class ExternalRouteSyncService(
    private val context: Context,
    private val supabase: SupabaseClient
) {
    private val prefs = context.applicationContext.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    var isSyncEnabled: Boolean
        get() = prefs.getBoolean(KEY_SYNC_ENABLED, false)
        set(value) {
            prefs.edit().putBoolean(KEY_SYNC_ENABLED, value).apply()
        }

    var lastSyncAt: Instant?
        get() = prefs.getString(KEY_LAST_SYNC_AT, null)?.let { runCatching { Instant.parse(it) }.getOrNull() }
        private set(value) {
            prefs.edit().putString(KEY_LAST_SYNC_AT, value?.toString()).apply()
        }

    var routesAppliedCount: Int
        get() = prefs.getInt(KEY_ROUTES_APPLIED, 0)
        private set(value) {
            prefs.edit().putInt(KEY_ROUTES_APPLIED, value).apply()
        }

    suspend fun processPendingJobs(userId: String): ExternalRouteSyncSummary {
        if (!isSyncEnabled) return ExternalRouteSyncSummary()
        val client = runCatching { HealthConnectClient.getOrCreate(context) }.getOrNull()
            ?: return ExternalRouteSyncSummary(
                failed = 1,
                errorMessages = listOf("Health Connect is not available on this device.")
            )

        val readPerm = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
        val granted = client.permissionController.getGrantedPermissions()
        if (!granted.contains(readPerm)) {
            return ExternalRouteSyncSummary(
                failed = 1,
                errorMessages = listOf("Grant Health Connect read permission to sync GPS routes.")
            )
        }

        val summary = ExternalRouteSyncSummary()
        val jobs = runCatching { fetchPendingJobs() }.getOrElse { e ->
            return ExternalRouteSyncSummary(failed = 1, errorMessages = listOf(e.message ?: "Failed to load jobs."))
        }

        val errors = mutableListOf<String>()
        for (job in jobs) {
            val partial = processJob(job, client)
            summary.applied += partial.applied
            summary.skipped += partial.skipped
            summary.failed += partial.failed
            errors.addAll(partial.errorMessages)
        }
        summary.errorMessages = errors

        if (summary.applied > 0) {
            routesAppliedCount = routesAppliedCount + summary.applied
        }
        lastSyncAt = Instant.now()
        return summary
    }

    suspend fun handleWearableCallbackUri(uri: Uri) {
        if (!WearableRedirect.isWearableCallback(uri)) return
        if (WearableRedirect.status(uri) != "connected") return
        val userId = supabase.auth.currentUserOrNull()?.id ?: return
        isSyncEnabled = true
        processPendingJobs(userId)
    }

    private suspend fun processJob(
        job: ExternalRouteJobWire,
        client: HealthConnectClient
    ): ExternalRouteSyncSummary {
        val summary = ExternalRouteSyncSummary()
        val activityCode = job.activityCode
        val exerciseType = activityCode?.let { ExternalRouteActivityMapping.healthConnectExerciseType(it) }
        if (exerciseType == null) {
            updateJobStatus(job.id, "failed", "unsupported_activity", null)
            summary.failed += 1
            return summary
        }

        val startedAt = parseInstant(job.startedAt) ?: run {
            updateJobStatus(job.id, "failed", "invalid_started_at", null)
            summary.failed += 1
            return summary
        }
        val endedAt = job.endedAt?.let { parseInstant(it) }
        val durationSec = job.durationSec ?: run {
            val end = endedAt ?: startedAt
            maxOf(1, ChronoUnit.SECONDS.between(startedAt, end).toInt())
        }

        val windowStart = startedAt.minus(HealthConnectWorkoutMatcher.START_TOLERANCE_SEC, ChronoUnit.SECONDS)
        val windowEnd = (endedAt ?: startedAt).plus(HealthConnectWorkoutMatcher.START_TOLERANCE_SEC, ChronoUnit.SECONDS)

        val sessions = runCatching {
            client.readRecords(
                ReadRecordsRequest(
                    recordType = ExerciseSessionRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(windowStart, windowEnd)
                )
            ).records
        }.getOrElse { e ->
            updateJobStatus(job.id, "failed", "health_connect_query_failed", null)
            summary.failed += 1
            summary.errorMessages = listOf(e.message ?: "Health Connect query failed.")
            return summary
        }

        val criteria = HealthConnectWorkoutMatchCriteria(
            startedAt = startedAt,
            endedAt = endedAt,
            durationSec = durationSec,
            exerciseType = exerciseType,
            preferredSourceBundleIds = ExternalRouteSourceBundles.preferredBundles(job.provider)
        )

        val routeCounts = sessions.associate { it.metadata.id to 0 }
        val session = HealthConnectWorkoutMatcher.findBestMatch(sessions, criteria, routeCounts)
        if (session == null) {
            updateJobStatus(job.id, "failed", "no_matching_health_session", null)
            summary.failed += 1
            return summary
        }

        val coords = decimateRoutePoints(job.routePoints)
        if (coords.size < 2) {
            updateJobStatus(job.id, "failed", "insufficient_route_points", null)
            summary.failed += 1
            return summary
        }

        val geojson = RouteLineStringDecimation.encodeGeoJsonLineString(coords)
        if (geojson == null) {
            updateJobStatus(job.id, "failed", "invalid_geojson", null)
            summary.failed += 1
            return summary
        }

        val externalUuid = healthConnectWorkoutExternalId(session.metadata.id)
        if (externalUuid == null) {
            updateJobStatus(job.id, "failed", "missing_session_id", null)
            summary.failed += 1
            return summary
        }

        val iso = DateTimeFormatter.ISO_INSTANT
        runCatching {
            supabase.postgrest.rpc(
                "apply_external_route_to_cardio_workout",
                buildJsonObject {
                    put("p_healthkit_uuid", externalUuid)
                    put("p_route_geojson", geojson)
                    put("p_provider", job.provider)
                    put("p_provider_activity_id", job.providerActivityId)
                    put("p_started_at", iso.format(startedAt))
                    endedAt?.let { put("p_ended_at", iso.format(it)) }
                    put("p_duration_sec", durationSec)
                    activityCode?.let { put("p_activity_code", it) }
                }
            ) { }
        }.onFailure { e ->
            updateJobStatus(job.id, "failed", "liftr_apply_failed", null)
            summary.failed += 1
            summary.errorMessages = listOf(e.message ?: "Failed to apply route.")
            return summary
        }

        updateJobStatus(job.id, "applied_liftr", null, externalUuid)
        summary.applied += 1
        return summary
    }

    private fun decimateRoutePoints(points: List<ExternalRoutePointWire>): List<LatLng> {
        val coords = points.mapNotNull { p ->
            if (!p.lat.isFinite() || !p.lon.isFinite()) null
            else LatLng(latitude = p.lat, longitude = p.lon)
        }
        return RouteLineStringDecimation.decimate(coords)
    }

    private suspend fun fetchPendingJobs(): List<ExternalRouteJobWire> =
        supabase.postgrest.from("external_workout_route_jobs").select {
            filter { eq("status", "pending") }
            order("started_at", Order.DESCENDING)
            limit(50)
        }.decodeList()

    private suspend fun updateJobStatus(
        jobId: String,
        status: String,
        reason: String?,
        healthUuid: String?
    ) {
        runCatching {
            supabase.postgrest.rpc(
                "update_external_route_job_status",
                buildJsonObject {
                    put("p_job_id", jobId)
                    put("p_status", status)
                    reason?.let { put("p_skip_reason", it) }
                    healthUuid?.let { put("p_healthkit_workout_uuid", it) }
                }
            ) { }
        }
    }

    private fun parseInstant(raw: String): Instant? =
        runCatching { Instant.parse(raw) }.getOrNull()

    companion object {
        private const val PREF = "liftr_external_route_sync"
        private const val KEY_SYNC_ENABLED = "externalRouteSyncEnabled"
        private const val KEY_LAST_SYNC_AT = "externalRouteLastSyncAt"
        private const val KEY_ROUTES_APPLIED = "externalRouteAppliedCount"
    }
}
