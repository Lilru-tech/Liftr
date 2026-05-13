package com.lilru.liftr.territory

import android.content.Context
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.AppSnackbar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class TerritoryBBoxWire(
    @SerialName("min_lat") val minLat: Double? = null,
    @SerialName("min_lon") val minLon: Double? = null,
    @SerialName("max_lat") val maxLat: Double? = null,
    @SerialName("max_lon") val maxLon: Double? = null
)

@Serializable
data class TerritoryCaptureSummaryWire(
    val ok: Boolean = false,
    @SerialName("route_kind") val routeKind: String? = null,
    @SerialName("cells_gained") val cellsGained: Int? = null,
    @SerialName("cells_taken") val cellsTaken: Int? = null,
    val bbox: TerritoryBBoxWire? = null,
    @SerialName("already_applied") val alreadyApplied: Boolean? = null,
    val reason: String? = null
)

@Serializable
data class TerritoryGeoJsonPolygonWire(
    val type: String? = null,
    val coordinates: List<List<List<Double>>> = emptyList()
) {
    fun ringLatLng(): List<Pair<Double, Double>> {
        val ring = coordinates.firstOrNull().orEmpty()
        return ring.mapNotNull { pair ->
            if (pair.size < 2) return@mapNotNull null
            val lon = pair[0]
            val lat = pair[1]
            if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return@mapNotNull null
            lat to lon
        }
    }
}

@Serializable
data class TerritoryPreviewCellWire(
    @SerialName("cell_id") val cellId: String,
    @SerialName("cell_geojson") val cellGeojson: TerritoryGeoJsonPolygonWire? = null
)

@Serializable
data class TerritoryPreviewResponseWire(
    val ok: Boolean = false,
    @SerialName("route_kind") val routeKind: String? = null,
    @SerialName("cells_count") val cellsCount: Int? = null,
    val cells: List<TerritoryPreviewCellWire> = emptyList(),
    val bbox: TerritoryBBoxWire? = null,
    val reason: String? = null
)

@Serializable
data class TerritoryMapCellWire(
    @SerialName("cell_id") val cellId: String,
    @SerialName("cell_geojson") val cellGeojson: TerritoryGeoJsonPolygonWire? = null,
    @SerialName("owner_user_id") val ownerUserId: String? = null,
    @SerialName("owner_username") val ownerUsername: String? = null,
    @SerialName("owner_avatar_url") val ownerAvatarUrl: String? = null,
    @SerialName("captured_at") val capturedAt: String? = null,
    @SerialName("is_mine") val isMine: Boolean? = null
)

@Serializable
data class TerritorySummaryWire(
    @SerialName("total_cells") val totalCells: Int? = null,
    @SerialName("cells_last_7d") val cellsLast7d: Int? = null,
    @SerialName("approx_area_m2") val approxAreaM2: Double? = null
)

@Serializable
data class TerritoryShareLeaderRowWire(
    val rank: Int = 0,
    @SerialName("user_id") val userId: String,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("owned_cells") val ownedCells: Int? = null,
    @SerialName("territory_share_pct") val territorySharePct: Double? = null
)

@Serializable
data class TerritoryCityRegionRowWire(
    @SerialName("city_key") val cityKey: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("center_lat") val centerLat: Double? = null,
    @SerialName("center_lon") val centerLon: Double? = null,
    @SerialName("captured_cells") val capturedCells: Int? = null,
    @SerialName("total_capture_cells") val totalCaptureCells: Int? = null,
    @SerialName("my_owned_cells") val myOwnedCells: Int? = null,
    @SerialName("owned_cells") val ownedCells: Int? = null
)

@Serializable
data class TerritoryBackfillResponseWire(
    val ok: Boolean = false,
    val processed: Int? = null,
    @SerialName("cells_gained") val cellsGained: Int? = null,
    @SerialName("cells_taken") val cellsTaken: Int? = null,
    @SerialName("has_more") val hasMore: Boolean? = null
)

@Serializable
data class TerritoryRecentTakeoverRowWire(
    @SerialName("workout_id") val workoutId: Long? = null,
    @SerialName("other_user_id") val otherUserId: String? = null,
    @SerialName("other_username") val otherUsername: String? = null,
    @SerialName("cells_taken") val cellsTaken: Int? = null,
    @SerialName("share_taken_pct") val shareTakenPct: Double? = null,
    @SerialName("created_at") val createdAt: String? = null
)

object TerritoryCaptureClient {
    private val json = Json { ignoreUnknownKeys = true }
    private val backgroundScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    suspend fun applyCapture(supabase: SupabaseClient, workoutId: Int): TerritoryCaptureSummaryWire? {
        return runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.APPLY_TERRITORY_CAPTURE_V1,
                buildJsonObject { put("p_workout_id", workoutId) }
            )
            json.decodeFromString<TerritoryCaptureSummaryWire>(res.data)
        }.onFailure { error ->
            AppSnackbar.showError(captureFailureMessage(error))
        }.getOrNull()
    }

    suspend fun previewCapture(supabase: SupabaseClient, routeGeoJson: String): TerritoryPreviewResponseWire? {
        return runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.PREVIEW_TERRITORY_CAPTURE_V1,
                buildJsonObject { put("p_route_geojson", routeGeoJson) }
            )
            val decoded = json.decodeFromString<TerritoryPreviewResponseWire>(res.data)
            if (!decoded.ok) {
                AppSnackbar.showError(captureFailureMessage(decoded.reason))
            }
            decoded
        }.onFailure { error ->
            AppSnackbar.showError(captureFailureMessage(error))
        }.getOrNull()
    }

    suspend fun fetchRecentTakeovers(
        supabase: SupabaseClient,
        userId: String? = null,
        limit: Int = 3
    ): List<TerritoryRecentTakeoverRowWire> {
        return runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.LIST_TERRITORY_RECENT_TAKEOVERS_V1,
                buildJsonObject {
                    userId?.let { put("p_user_id", it) }
                    put("p_limit", limit)
                }
            )
            json.decodeFromString<List<TerritoryRecentTakeoverRowWire>>(res.data)
        }.getOrDefault(emptyList())
    }

    suspend fun fetchTerritorySummary(
        supabase: SupabaseClient,
        userId: String? = null
    ): TerritorySummaryWire? {
        return runCatching {
            val res = if (userId == null) {
                supabase.postgrest.rpc(BackendContracts.Rpc.GET_MY_TERRITORY_SUMMARY_V1)
            } else {
                supabase.postgrest.rpc(
                    BackendContracts.Rpc.GET_TERRITORY_SUMMARY_V1,
                    buildJsonObject { put("p_user_id", userId) }
                )
            }
            json.decodeFromString<TerritorySummaryWire>(res.data)
        }.onFailure { error ->
            if (userId == null) {
                AppSnackbar.showError(captureFailureMessage(error))
            }
        }.getOrNull()
    }

    suspend fun fetchUserTerritoryTopCities(
        supabase: SupabaseClient,
        userId: String,
        limit: Int = 3
    ): List<TerritoryCityRegionRowWire> {
        return runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.LIST_USER_TERRITORY_TOP_CITIES_V1,
                buildJsonObject {
                    put("p_user_id", userId)
                    put("p_limit", limit)
                }
            )
            json.decodeFromString<List<TerritoryCityRegionRowWire>>(res.data).map { row ->
                row.copy(myOwnedCells = row.myOwnedCells ?: row.ownedCells)
            }
        }.getOrDefault(emptyList())
    }

    suspend fun fetchMySummary(supabase: SupabaseClient): TerritorySummaryWire? {
        return fetchTerritorySummary(supabase, userId = null)
    }

    fun storeCaptureReferenceCoordinate(context: Context, summary: TerritoryCaptureSummaryWire) {
        if (!summary.ok) return
        val bbox = summary.bbox ?: return
        val minLat = bbox.minLat ?: return
        val minLon = bbox.minLon ?: return
        val maxLat = bbox.maxLat ?: return
        val maxLon = bbox.maxLon ?: return
        LiftrPreferences.setTerritoryReferenceCoordinate(
            context = context,
            latitude = (minLat + maxLat) / 2.0,
            longitude = (minLon + maxLon) / 2.0
        )
    }

    suspend fun fetchMapCells(
        supabase: SupabaseClient,
        minLat: Double,
        minLon: Double,
        maxLat: Double,
        maxLon: Double,
        limit: Int = 500
    ): List<TerritoryMapCellWire> {
        return runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.GET_TERRITORY_MAP_V1,
                buildJsonObject {
                    put("p_min_lat", minLat)
                    put("p_min_lon", minLon)
                    put("p_max_lat", maxLat)
                    put("p_max_lon", maxLon)
                    put("p_limit", limit)
                }
            )
            json.decodeFromString<List<TerritoryMapCellWire>>(res.data)
        }.onFailure { error ->
            AppSnackbar.showError(captureFailureMessage(error))
        }.getOrDefault(emptyList())
    }

    suspend fun fetchTerritoryCityRegions(supabase: SupabaseClient): List<TerritoryCityRegionRowWire> {
        return runCatching {
            val res = supabase.postgrest.rpc(BackendContracts.Rpc.LIST_TERRITORY_CITY_REGIONS_V1)
            json.decodeFromString<List<TerritoryCityRegionRowWire>>(res.data)
        }.getOrDefault(emptyList())
    }

    suspend fun fetchTerritoryCityShareLeaderboard(
        supabase: SupabaseClient,
        cityKey: String,
        scope: String = "global",
        limit: Int = 100
    ): List<TerritoryShareLeaderRowWire> {
        return runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.GET_TERRITORY_CITY_SHARE_LEADERBOARD_V1,
                buildJsonObject {
                    put("p_city_key", cityKey)
                    put("p_scope", scope)
                    put("p_limit", limit)
                }
            )
            json.decodeFromString<List<TerritoryShareLeaderRowWire>>(res.data)
        }.getOrDefault(emptyList())
    }

    fun nearestCityKey(
        latitude: Double?,
        longitude: Double?,
        cities: List<TerritoryCityRegionRowWire>
    ): String? {
        if (cities.isEmpty()) return null
        if (latitude == null || longitude == null) return cities.firstOrNull()?.cityKey
        return cities.minByOrNull { city ->
            val lat = city.centerLat ?: 0.0
            val lon = city.centerLon ?: 0.0
            val dLat = lat - latitude
            val dLon = lon - longitude
            dLat * dLat + dLon * dLon
        }?.cityKey
    }

    fun preferredCityKey(
        latitude: Double?,
        longitude: Double?,
        cities: List<TerritoryCityRegionRowWire>
    ): String? {
        val owned = cities.filter { (it.myOwnedCells ?: 0) > 0 }
        val pool = if (owned.isEmpty()) cities else owned
        if (pool.isEmpty()) return null
        return nearestCityKey(latitude, longitude, pool)
    }

    suspend fun fetchTerritoryShareLeaderboard(
        supabase: SupabaseClient,
        scope: String = "global",
        limit: Int = 100
    ): List<TerritoryShareLeaderRowWire> {
        val cities = fetchTerritoryCityRegions(supabase)
        val cityKey = cities.firstOrNull()?.cityKey ?: return emptyList()
        return fetchTerritoryCityShareLeaderboard(supabase, cityKey, scope, limit)
    }

    suspend fun backfillHistoricalCaptures(
        supabase: SupabaseClient,
        context: Context,
        batchSize: Int = 5,
        maxBatches: Int = 8
    ) {
        if (LiftrPreferences.territoryHistoricalBackfillDone(context)) {
            refreshTerritoryMunicipalitiesInBackground(supabase)
            return
        }
        var processedAny = false
        repeat(maxBatches) {
            val batch = runCatching {
                val res = supabase.postgrest.rpc(
                    BackendContracts.Rpc.BACKFILL_MY_TERRITORY_CAPTURES_V1,
                    buildJsonObject { put("p_limit", batchSize) }
                )
                json.decodeFromString<TerritoryBackfillResponseWire>(res.data)
            }.getOrNull() ?: return
            if (!batch.ok) return
            if ((batch.processed ?: 0) == 0) return
            processedAny = processedAny || (batch.processed ?: 0) > 0
            if (batch.hasMore != true) return
        }
        if (processedAny) {
            LiftrPreferences.setTerritoryHistoricalBackfillDone(context, true)
        }
        refreshTerritoryMunicipalitiesInBackground(supabase)
    }

    fun refreshTerritoryMunicipalitiesInBackground(supabase: SupabaseClient, limit: Int = 1) {
        backgroundScope.launch {
            withTimeoutOrNull(8_000) {
                invokeTerritoryMunicipalityResolve(supabase, limit)
            }
        }
    }

    private suspend fun invokeTerritoryMunicipalityResolve(supabase: SupabaseClient, limit: Int) {
        runCatching {
            supabase.functions.invoke(
                BackendContracts.EdgeFunctions.RESOLVE_TERRITORY_MUNICIPALITY,
                body = buildJsonObject {
                    put("limit", limit)
                    put("max_items", limit)
                    put("process_queue", true)
                    put("run_assignment_backfill", false)
                }
            )
        }
    }

    fun citySummaryLabel(city: TerritoryCityRegionRowWire): String {
        val name = city.displayName ?: city.cityKey ?: "City"
        val captured = city.capturedCells ?: 0
        val total = city.totalCaptureCells
        return if (total != null && total > 0) {
            "$name · $captured / $total cells"
        } else {
            "$name · $captured cells"
        }
    }

    fun captureMessage(summary: TerritoryCaptureSummaryWire): String? {
        if (!summary.ok) return captureFailureMessage(summary.reason)
        val gained = summary.cellsGained ?: 0
        val taken = summary.cellsTaken ?: 0
        if (gained == 0) return null
        val parts = mutableListOf("Captured $gained map cells")
        if (taken > 0) {
            parts += "taking $taken from others"
        }
        val bbox = summary.bbox
        val lat = bbox?.minLat
        val lon = bbox?.minLon
        if (lat != null && lon != null) {
            parts += "near ${"%.3f".format(lat)}, ${"%.3f".format(lon)}"
        }
        return parts.joinToString(", ") + "."
    }

    fun captureFailureMessage(reason: String?): String = when (reason) {
        "activity_not_eligible" -> "Territory capture only applies to outdoor GPS cardio."
        "missing_route" -> "Territory capture needs a GPS route on this workout."
        "route_too_short" -> "Route is too short to capture territory."
        "speed_unrealistic" -> "Route speed looks unrealistic for territory capture."
        "no_cells" -> "No territory cells were captured on this route."
        "capture_geom_failed" -> "Territory capture could not build a capture area."
        else -> "Territory capture could not be applied."
    }

    private fun captureFailureMessage(error: Throwable): String {
        val text = error.message?.trim().orEmpty()
        return if (text.isEmpty()) {
            "Territory capture could not be applied."
        } else {
            "Territory capture failed: $text"
        }
    }
}
