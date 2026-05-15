package com.lilru.liftr.territory

import android.content.Context
import android.util.Log
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.AppSnackbar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
    @SerialName("cells_gained_last_7d") val cellsGainedLast7d: Int? = null,
    @SerialName("capture_workouts_last_7d") val captureWorkoutsLast7d: Int? = null,
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

@Serializable
data class TerritoryCaptureEventRowWire(
    @SerialName("cells_gained") val cellsGained: Int? = null,
    @SerialName("cells_taken") val cellsTaken: Int? = null
)

@Serializable
data class TerritoryWorkoutTakeoverRowWire(
    @SerialName("victim_user_id") val victimUserId: String? = null,
    @SerialName("victim_username") val victimUsername: String? = null,
    @SerialName("victim_avatar_url") val victimAvatarUrl: String? = null,
    @SerialName("cells_taken") val cellsTaken: Int? = null,
    @SerialName("share_taken_pct") val shareTakenPct: Double? = null
)

object TerritoryCaptureClient {
    private const val LOG_TAG = "TerritoryShare"
    private val json = Json { ignoreUnknownKeys = true }
    private val municipalityRefreshMutex = Mutex()
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

    suspend fun fetchCaptureEvent(
        supabase: SupabaseClient,
        workoutId: Int
    ): TerritoryCaptureEventRowWire? {
        return runCatching {
            val res = supabase
                .from(BackendContracts.Tables.TERRITORY_CAPTURE_EVENTS)
                .select(columns = Columns.raw("cells_gained, cells_taken")) {
                    filter { eq("workout_id", workoutId) }
                    limit(1)
                }
            val row = json.decodeFromString<List<TerritoryCaptureEventRowWire>>(res.data).firstOrNull()
            if (row == null || (row.cellsGained ?: 0) <= 0) null else row
        }.getOrNull()
    }

    suspend fun fetchWorkoutTakeovers(
        supabase: SupabaseClient,
        workoutId: Int
    ): List<TerritoryWorkoutTakeoverRowWire> {
        return runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.LIST_WORKOUT_TERRITORY_TAKEOVERS_V1,
                buildJsonObject { put("p_workout_id", workoutId) }
            )
            json.decodeFromString<List<TerritoryWorkoutTakeoverRowWire>>(res.data)
        }.getOrDefault(emptyList())
    }

    suspend fun fetchTerritoryPreviewRings(
        supabase: SupabaseClient,
        routeGeoJson: String
    ): List<List<Pair<Double, Double>>> {
        return runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.PREVIEW_TERRITORY_CAPTURE_V1,
                buildJsonObject { put("p_route_geojson", routeGeoJson) }
            )
            val decoded = json.decodeFromString<TerritoryPreviewResponseWire>(res.data)
            if (!decoded.ok) {
                emptyList()
            } else {
                decoded.cells.mapNotNull { cell ->
                    cell.cellGeojson?.ringLatLng()?.takeIf { it.size >= 3 }
                }
            }
        }.getOrDefault(emptyList())
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

    suspend fun fetchTerritoryCityRegions(
        supabase: SupabaseClient,
        query: String? = null,
        ownedFirst: Boolean = true,
        limit: Int = 200
    ): List<TerritoryCityRegionRowWire> {
        return runCatching {
            val trimmedQuery = query?.trim()?.takeIf { it.isNotEmpty() }
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.LIST_TERRITORY_CITY_REGIONS_V1,
                buildJsonObject {
                    trimmedQuery?.let { put("p_query", it) }
                    put("p_limit", limit)
                    put("p_owned_first", ownedFirst)
                }
            )
            json.decodeFromString<List<TerritoryCityRegionRowWire>>(res.data)
        }.onFailure { error ->
            logTerritoryShare("city regions fetch failed error=${error.message}")
        }.getOrDefault(emptyList())
    }

    fun filterTerritoryCities(
        cities: List<TerritoryCityRegionRowWire>,
        query: String
    ): List<TerritoryCityRegionRowWire> {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return cities
        return cities.filter { city ->
            val name = city.displayName?.lowercase().orEmpty()
            val key = city.cityKey?.lowercase().orEmpty()
            name.contains(needle) || key.contains(needle)
        }
    }

    fun selectedTerritoryCity(
        cities: List<TerritoryCityRegionRowWire>,
        preferredKey: String?,
        referenceLatitude: Double?,
        referenceLongitude: Double?
    ): TerritoryCityRegionRowWire? {
        preferredKey?.let { key ->
            cities.firstOrNull { it.cityKey == key }?.let { return it }
        }
        nearestCityKey(referenceLatitude, referenceLongitude, cities)?.let { key ->
            cities.firstOrNull { it.cityKey == key }?.let { return it }
        }
        preferredCityKey(referenceLatitude, referenceLongitude, cities)?.let { key ->
            cities.firstOrNull { it.cityKey == key }?.let { return it }
        }
        return cities.firstOrNull()
    }

    private const val RECENT_TERRITORY_CITY_KEYS = "recentTerritoryCityKeysV1"
    private const val RECENT_TERRITORY_CITY_KEYS_LIMIT = 5

    fun recentTerritoryCityKeys(context: Context): List<String> {
        return LiftrPreferences.getStringList(context, RECENT_TERRITORY_CITY_KEYS)
    }

    fun recordRecentTerritoryCityKey(context: Context, cityKey: String?) {
        if (cityKey.isNullOrBlank() || isPendingTerritoryCityKey(cityKey)) return
        val keys = recentTerritoryCityKeys(context).filter { it != cityKey }.toMutableList()
        keys.add(0, cityKey)
        while (keys.size > RECENT_TERRITORY_CITY_KEYS_LIMIT) {
            keys.removeAt(keys.lastIndex)
        }
        LiftrPreferences.setStringList(context, RECENT_TERRITORY_CITY_KEYS, keys)
    }

    suspend fun fetchTerritoryTotalCellsLeaderboard(
        supabase: SupabaseClient,
        scope: String = "global",
        limit: Int = 100
    ): List<TerritoryShareLeaderRowWire> {
        return runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.GET_TERRITORY_TOTAL_CELLS_LEADERBOARD_V1,
                buildJsonObject {
                    put("p_scope", scope)
                    put("p_limit", limit)
                }
            )
            json.decodeFromString<List<TerritoryShareLeaderRowWire>>(res.data)
        }.getOrDefault(emptyList())
    }

    fun isPendingTerritoryCityKey(cityKey: String?): Boolean {
        return cityKey?.startsWith("pending:") == true
    }

    fun pendingResolveCoordinates(city: TerritoryCityRegionRowWire): Pair<Double, Double>? {
        val key = city.cityKey
        if (key != null && isPendingTerritoryCityKey(key)) {
            val parts = key.split(":")
            if (parts.size >= 3) {
                val lat = parts[1].toDoubleOrNull()
                val lon = parts[2].toDoubleOrNull()
                if (lat != null && lon != null) {
                    return lat to lon
                }
            }
        }
        val lat = city.centerLat
        val lon = city.centerLon
        return if (lat != null && lon != null) lat to lon else null
    }

    fun pendingBucketCoordinates(city: TerritoryCityRegionRowWire): Pair<Double, Double>? {
        val key = city.cityKey ?: return null
        if (!isPendingTerritoryCityKey(key)) return null
        val parts = key.split(":")
        if (parts.size < 3) return null
        val lat = parts[1].toDoubleOrNull() ?: return null
        val lon = parts[2].toDoubleOrNull() ?: return null
        return lat to lon
    }

    fun logTerritoryShare(message: String) {
        Log.d(LOG_TAG, message)
    }

    suspend fun refreshPendingTerritoryCityRegions(
        supabase: SupabaseClient,
        maxResolveItems: Int = 2,
        maxBatches: Int = 8,
        timeBudgetMillis: Long = 60_000,
        onUpdate: ((List<TerritoryCityRegionRowWire>) -> Unit)? = null
    ): List<TerritoryCityRegionRowWire> {
        val started = System.currentTimeMillis()
        val deadline = started + timeBudgetMillis
        var refreshed = fetchTerritoryCityRegions(supabase)
        var batchesRun = 0
        while (batchesRun < maxBatches && System.currentTimeMillis() < deadline) {
            val pending = refreshed.filter { isPendingTerritoryCityKey(it.cityKey) }
            logTerritoryShare("refresh batch=${batchesRun + 1} total=${refreshed.size} pending=${pending.size}")
            if (pending.isEmpty()) break
            val resolveLimit = maxOf(1, minOf(maxResolveItems, pending.size))
            pending.take(resolveLimit).forEachIndexed { index, city ->
                val coordinates = pendingResolveCoordinates(city) ?: run {
                    logTerritoryShare("resolve skipped missing coordinates key=${city.cityKey}")
                    return@forEachIndexed
                }
                val bucket = pendingBucketCoordinates(city)
                logTerritoryShare(
                    "resolve batch=${batchesRun + 1} item=${index + 1}/$resolveLimit lat=${coordinates.first} lon=${coordinates.second} key=${city.cityKey}"
                )
                resolveMunicipalityAt(
                    supabase = supabase,
                    latitude = coordinates.first,
                    longitude = coordinates.second,
                    bucketLatitude = bucket?.first,
                    bucketLongitude = bucket?.second
                )
                if (index + 1 < resolveLimit) {
                    delay(800)
                }
            }
            invokeTerritoryMunicipalityResolve(
                supabase = supabase,
                limit = 1,
                processQueue = true,
                runAssignmentBackfill = false
            )
            refreshed = fetchTerritoryCityRegions(supabase)
            onUpdate?.invoke(refreshed)
            batchesRun += 1
        }
        val remainingPending = refreshed.count { isPendingTerritoryCityKey(it.cityKey) }
        logTerritoryShare(
            "refresh finished batches=$batchesRun elapsedMs=${System.currentTimeMillis() - started} pending=$remainingPending"
        )
        return refreshed
    }

    fun refreshPendingTerritoryCityRegionsInBackground(
        supabase: SupabaseClient,
        scope: CoroutineScope,
        maxResolveItems: Int = 2,
        maxBatches: Int = 8,
        onUpdate: (List<TerritoryCityRegionRowWire>) -> Unit
    ) {
        scope.launch {
            municipalityRefreshMutex.withLock {
                refreshPendingTerritoryCityRegions(
                    supabase = supabase,
                    maxResolveItems = maxResolveItems,
                    maxBatches = maxBatches,
                    onUpdate = onUpdate
                )
            }
        }
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

    fun shouldMarkHistoricalBackfillDone(hasMore: Boolean): Boolean = !hasMore

    suspend fun backfillHistoricalCaptures(
        supabase: SupabaseClient,
        context: Context,
        batchSize: Int = 5,
        maxBatchesPerVisit: Int = 40
    ) {
        if (LiftrPreferences.territoryHistoricalBackfillDone(context)) {
            refreshTerritoryMunicipalitiesInBackground(supabase)
            return
        }
        var shouldMarkDone = false
        batchLoop@ for (_i in 0 until maxBatchesPerVisit) {
            val batch = runCatching {
                val res = supabase.postgrest.rpc(
                    BackendContracts.Rpc.BACKFILL_MY_TERRITORY_CAPTURES_V1,
                    buildJsonObject { put("p_limit", batchSize) }
                )
                json.decodeFromString<TerritoryBackfillResponseWire>(res.data)
            }.getOrNull() ?: break@batchLoop
            if (!batch.ok) break@batchLoop
            if ((batch.processed ?: 0) == 0) break@batchLoop
            if (shouldMarkHistoricalBackfillDone(batch.hasMore == true)) {
                shouldMarkDone = true
                break@batchLoop
            }
        }
        if (shouldMarkDone) {
            LiftrPreferences.setTerritoryHistoricalBackfillDone(context, true)
        }
        refreshTerritoryMunicipalitiesInBackground(supabase)
    }

    fun refreshTerritoryMunicipalitiesInBackground(supabase: SupabaseClient, limit: Int = 1) {
        backgroundScope.launch {
            invokeTerritoryMunicipalityResolve(
                supabase = supabase,
                limit = limit,
                processQueue = true,
                runAssignmentBackfill = false
            )
        }
    }

    private suspend fun resolveMunicipalityAt(
        supabase: SupabaseClient,
        latitude: Double,
        longitude: Double,
        bucketLatitude: Double? = null,
        bucketLongitude: Double? = null
    ) {
        invokeTerritoryMunicipalityResolve(
            supabase = supabase,
            limit = 1,
            processQueue = false,
            runAssignmentBackfill = false,
            latitude = latitude,
            longitude = longitude,
            bucketLatitude = bucketLatitude,
            bucketLongitude = bucketLongitude
        )
    }

    private suspend fun invokeTerritoryMunicipalityResolve(
        supabase: SupabaseClient,
        limit: Int,
        processQueue: Boolean,
        runAssignmentBackfill: Boolean,
        latitude: Double? = null,
        longitude: Double? = null,
        bucketLatitude: Double? = null,
        bucketLongitude: Double? = null
    ) {
        runCatching {
            supabase.functions.invoke(
                BackendContracts.EdgeFunctions.RESOLVE_TERRITORY_MUNICIPALITY,
                body = buildJsonObject {
                    put("limit", limit)
                    put("max_items", limit)
                    put("process_queue", processQueue)
                    put("run_assignment_backfill", runAssignmentBackfill)
                    latitude?.let { put("lat", it) }
                    longitude?.let { put("lon", it) }
                    bucketLatitude?.let { put("bucket_lat", it) }
                    bucketLongitude?.let { put("bucket_lon", it) }
                }
            )
        }.onFailure { error ->
            logTerritoryShare("municipality resolve failed error=${error.message}")
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

    fun profileCitySummaryLabel(city: TerritoryCityRegionRowWire): String {
        val name = city.displayName ?: city.cityKey ?: "City"
        val owned = city.myOwnedCells ?: city.ownedCells ?: 0
        val communityCaptured = city.capturedCells ?: 0
        val total = city.totalCaptureCells
        return if (total != null && total > owned && total >= communityCaptured) {
            "$name · you own $owned of $total cells"
        } else {
            "$name · you own $owned cells"
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

    fun takeoverRowSubtitle(cells: Int, sharePct: Double): String {
        val shareText = if (sharePct % 1.0 == 0.0) {
            "%.0f".format(sharePct)
        } else {
            "%.1f".format(sharePct)
        }
        return "$cells cells · $shareText%"
    }

    fun profileTerritorySummaryLine(
        totalCells: Int,
        cellsGained7d: Int,
        workouts7d: Int,
        isOwnProfile: Boolean
    ): String {
        val prefix = if (isOwnProfile) "You own $totalCells cells" else "Owns $totalCells cells"
        if (cellsGained7d <= 0 && workouts7d <= 0) return prefix
        val workoutWord = if (workouts7d == 1) "workout" else "workouts"
        val newWord = if (cellsGained7d == 1) "new cell" else "new cells"
        return "$prefix · $cellsGained7d $newWord (in $workouts7d $workoutWord) in the last 7 days"
    }

    fun mapTerritory7dLine(cellsGained7d: Int, workouts7d: Int): String? {
        if (cellsGained7d <= 0 && workouts7d <= 0) return null
        val newCellsWord = if (cellsGained7d == 1) "new cell" else "new cells"
        val workoutWord = if (workouts7d == 1) "workout" else "workouts"
        return "7d: $cellsGained7d $newCellsWord ($workouts7d $workoutWord)"
    }

    fun workoutDetailLabel(gained: Int, taken: Int): String {
        return if (taken > 0) {
            "$gained cells ($taken from others)"
        } else {
            "$gained cells"
        }
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
