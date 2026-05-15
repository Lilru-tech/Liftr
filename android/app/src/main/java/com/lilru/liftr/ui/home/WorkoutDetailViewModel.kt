package com.lilru.liftr.ui.home

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.territory.TerritoryCaptureClient
import com.lilru.liftr.territory.TerritoryWorkoutTakeoverRowWire
import com.lilru.liftr.ui.compare.CompareCandidateLoader
import com.lilru.liftr.ui.compare.CompareWorkoutCandidate
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import com.lilru.liftr.cardio.CardioKmPaceSplits
import com.lilru.liftr.hyrox.HyroxExerciseFormatting
import com.lilru.liftr.ui.add.AddCardioActivity
import com.lilru.liftr.ui.add.AddWorkoutIntensity
import com.lilru.liftr.ui.add.StrengthExerciseDraft
import com.lilru.liftr.ui.add.StrengthSetDraft
import com.lilru.liftr.ui.add.draftSetToStrengthPayload
import com.lilru.liftr.ui.add.weightSegmentsToJsonArray
import com.lilru.liftr.ui.add.SportStatsPayloadBuilder
import com.lilru.liftr.ui.add.duplicate.SportEditEnrichment
import com.lilru.liftr.ui.add.duplicate.loadSportEditEnrichment
import com.lilru.liftr.ui.active.normalizeSportMatchResult
import com.lilru.liftr.ui.add.AddSportType
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import com.lilru.liftr.ui.active.patchWorkoutStartedAtNow
import java.time.Instant
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject

@Serializable
data class CardioSessionEmbed(
    @SerialName("activity_code") val activityCode: String? = null,
    @SerialName("distance_km") val distanceKm: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    val modality: String? = null
)

/**
 * Carga de [Liftr.WorkoutDetailView.CardioDetailBlock]: fila de [cardio_sessions] + stats JSON.
 */
data class CardioSessionDetail(
    val id: Int,
    val activityCode: String? = null,
    val modality: String? = null,
    val distanceKm: Double? = null,
    val durationSec: Int? = null,
    val avgHr: Int? = null,
    val maxHr: Int? = null,
    val avgPaceSecPerKm: Int? = null,
    val elevationGainM: Int? = null,
    val notes: String? = null,
    val routeGeojson: String? = null,
    val extras: CardioSessionExtras? = null,
    val territoryCellsGained: Int? = null,
    val territoryCellsTaken: Int? = null,
    val territoryPreviewRings: List<List<Pair<Double, Double>>> = emptyList(),
    val territoryTakeovers: List<TerritoryWorkoutTakeoverRowWire> = emptyList()
)

@Serializable
private data class CardioSessionWire(
    val id: Int,
    @SerialName("activity_code") val activityCode: String? = null,
    val modality: String? = null,
    @SerialName("distance_km") val distanceKm: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("avg_hr") val avgHr: Int? = null,
    @SerialName("max_hr") val maxHr: Int? = null,
    @SerialName("avg_pace_sec_per_km") val avgPaceSecPerKm: Int? = null,
    @SerialName("elevation_gain_m") val elevationGainM: Int? = null,
    val notes: String? = null,
    @SerialName("route_geojson") val routeGeojson: String? = null
)

@Serializable
data class CardioSessionExtras(
    @SerialName("cadence_rpm") val cadenceRpm: Int? = null,
    @SerialName("watts_avg") val wattsAvg: Int? = null,
    @SerialName("incline_pct") val inclinePct: Double? = null,
    @SerialName("swim_laps") val swimLaps: Int? = null,
    @SerialName("pool_length_m") val poolLengthM: Int? = null,
    @SerialName("swim_style") val swimStyle: String? = null,
    @SerialName("split_sec_per_500m") val splitSecPer500m: Int? = null,
    @SerialName("km_split_pace_sec") val kmSplitPaceSec: List<Int>? = null
)

@Serializable
private data class CardioSessionStatsRow(
    val stats: CardioSessionExtras? = null
)

@Serializable
data class SportSessionEmbed(
    val sport: String? = null
)

/** Fila de [SPORT_SESSIONS] cargada al ver el detalle (más rica que el embed mínimo). */
data class SportSessionDetail(
    val id: Int,
    val sport: String,
    val durationSec: Int?,
    val scoreFor: Int?,
    val scoreAgainst: Int?,
    val matchResult: String?,
    val matchScoreText: String?,
    val location: String?,
    val notes: String?
)

@Serializable
private data class SportSessionWire(
    val id: Int,
    val sport: String,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("score_for") val scoreFor: Int? = null,
    @SerialName("score_against") val scoreAgainst: Int? = null,
    @SerialName("match_result") val matchResult: String? = null,
    @SerialName("match_score_text") val matchScoreText: String? = null,
    val location: String? = null,
    val notes: String? = null
)

@Serializable
data class WorkoutDetailRow(
    val id: Int,
    @SerialName("user_id") val userId: String,
    val kind: String? = null,
    val title: String? = null,
    val notes: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("duration_min") val durationMin: Int? = null,
    val state: String? = null,
    @SerialName("perceived_intensity") val perceivedIntensity: String? = null,
    @SerialName("calories_kcal") val caloriesKcal: Double? = null,
    @SerialName("cardio_sessions") val cardioSessions: List<CardioSessionEmbed>? = null,
    @SerialName("sport_sessions") val sportSessions: List<SportSessionEmbed>? = null
)

@Serializable
data class ProfileLite(
    @SerialName("user_id") val userId: String,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null
)

@Serializable
private data class ScoreRow(
    @SerialName("workout_id") val workoutId: Int,
    val score: Double? = null
)

@Serializable
private data class LikeRow(
    @SerialName("user_id") val userId: String
)

@Serializable
private data class WorkoutLikeTimeRow(
    @SerialName("user_id") val userId: String,
    @SerialName("created_at") val createdAt: String? = null
)

@Serializable
private data class ParticipantRow(
    @SerialName("user_id") val userId: String
)

@Serializable
private data class CommentRow(
    val id: Int,
    @SerialName("user_id") val userId: String,
    val body: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("parent_id") val parentId: Int? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("likes_count") val likesCount: Int? = null,
    @SerialName("replies_count") val repliesCount: Int? = null
)

@Serializable
private data class CommentInsert(
    @SerialName("workout_id") val workoutId: Int,
    @SerialName("user_id") val userId: String,
    val body: String,
    @SerialName("parent_id") val parentId: Int? = null
)

data class WorkoutCommentUi(
    val id: Int,
    val userId: String,
    val parentId: Int?,
    val username: String?,
    val body: String,
    val createdAt: String?,
    val canDelete: Boolean = false,
    val likesCount: Int = 0,
    val likedByMe: Boolean = false,
    val repliesCount: Int = 0,
    val repliesLoaded: Boolean = false,
    val isExpanded: Boolean = false,
    val replies: List<WorkoutCommentUi> = emptyList()
)

@Serializable
private data class CommentLikeRow(
    @SerialName("comment_id") val commentId: Int
)

@Serializable
private data class CommentLikeInsert(
    @SerialName("comment_id") val commentId: Int,
    @SerialName("user_id") val userId: String
)

data class WorkoutDetailUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val workout: WorkoutDetailRow? = null,
    val owner: ProfileLite? = null,
    val totalScore: Double? = null,
    val meUserId: String? = null,
    val likeCount: Int = 0,
    val isLikedByMe: Boolean = false,
    val participants: List<ProfileLite> = emptyList(),
    val comments: List<WorkoutCommentUi> = emptyList(),
    val likeBusy: Boolean = false,
    val commentBusy: Boolean = false,
    val publishBusy: Boolean = false,
    val deleteBusy: Boolean = false,
    val saveMetaBusy: Boolean = false,
    val sportSession: SportSessionDetail? = null,
    /** Fila de cardio + [cardio_session_stats] (paridad con [Liftr.WorkoutDetailView.CardioDetailBlock]). */
    val cardioSession: CardioSessionDetail? = null,
    /** Orden alineado a [WorkoutDetailView.loadLikers] (workout_likes por fecha). */
    val likers: List<ProfileLite> = emptyList(),
    val likersLoading: Boolean = false,
    val commentsCanLoadMore: Boolean = false,
    val commentsLoadingMore: Boolean = false,
    /** Candidatos para [Liftr.WorkoutDetailView.loadCompareCandidates] (RPC list_comparable_workouts_v1). */
    val compareCandidates: List<CompareWorkoutCandidate> = emptyList(),
    val compareReady: Boolean = false,
    val compareCandidateId: Int? = null,
    /** [p_stats] + Hyrox al editar sport (cargado con [loadSportEditEnrichment]). */
    val sportEditEnrichment: SportEditEnrichment = SportEditEnrichment.empty(),
    /** Editor de fuerza en detalle (iOS [EditWorkoutMetaSheet] `strengthSection`). */
    val strengthEditExercises: List<StrengthExerciseDraft> = emptyList(),
    val strengthEditInitialWorkoutExerciseIds: Set<Int> = emptySet(),
    /** Solo lectura: iOS [StrengthDetailBlock]. */
    val strengthReadonly: StrengthReadonlyDetail? = null,
    /** iOS [SportDetailBlock] `loadStats`. */
    val sportDetailStats: WorkoutSportDetailStatsBundle = WorkoutSportDetailStatsBundle()
)

class WorkoutDetailViewModel(
    private val supabase: SupabaseClient,
    private val workoutId: Int
) : ViewModel() {
    private companion object {
        const val TAG = "WorkoutDetailVM"
        /** Paridad con [Liftr/CommentView] `pageSize`. */
        const val COMMENT_PAGE_SIZE = 20
    }

    private var nextCommentPage = 0

    private val json = Json { ignoreUnknownKeys = true }
    private val _uiState = MutableStateFlow(WorkoutDetailUiState())
    val uiState: StateFlow<WorkoutDetailUiState> = _uiState.asStateFlow()

    private fun strengthSetDraftHasData(s: StrengthSetDraft): Boolean =
        draftSetToStrengthPayload(s) != null

    init {
        refresh()
    }

    /**
     * Carga [likers] desde [workout_likes] y [profiles] en el orden de [WorkoutDetailView.loadLikers] en iOS.
     */
    fun loadLikers() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(likersLoading = true, error = null)
            runCatching { loadLikersOrdered() }
                .onSuccess { list ->
                    _uiState.value = _uiState.value.copy(
                        likers = list,
                        likersLoading = false
                    )
                }
                .onFailure { e ->
                    Log.w(TAG, "loadLikers failed workoutId=$workoutId", e)
                    _uiState.value = _uiState.value.copy(
                        likers = emptyList(),
                        likersLoading = false
                    )
                }
        }
    }

    private fun loadCompareCandidatesWithWorkout(workout: WorkoutDetailRow, meUserId: String?) {
        viewModelScope.launch {
            val me = meUserId ?: supabase.auth.currentUserOrNull()?.id
            if (me == null) {
                _uiState.value = _uiState.value.copy(
                    compareCandidates = emptyList(),
                    compareReady = false,
                    compareCandidateId = null
                )
                return@launch
            }
            val res = runCatching {
                CompareCandidateLoader.load(
                    supabase = supabase,
                    sessionUserId = me,
                    currentWorkoutId = workoutId,
                    workout = workout
                )
            }
            res.onSuccess { r ->
                _uiState.value = _uiState.value.copy(
                    compareCandidates = r.candidates,
                    compareReady = r.candidates.isNotEmpty(),
                    compareCandidateId = r.defaultOtherId
                )
            }.onFailure { e ->
                Log.w(TAG, "loadCompareCandidates failed workoutId=$workoutId", e)
                _uiState.value = _uiState.value.copy(
                    compareCandidates = emptyList(),
                    compareReady = false,
                    compareCandidateId = null
                )
            }
        }
    }

    private suspend fun loadLikersOrdered(): List<ProfileLite> {
        val response = supabase
            .from(BackendContracts.Tables.WORKOUT_LIKES)
            .select(columns = Columns.raw("user_id, created_at")) {
                filter { eq("workout_id", workoutId) }
                order("created_at", Order.DESCENDING)
                limit(200)
            }
        val rows = decodeFlexibleList<WorkoutLikeTimeRow>(response.data)
        if (rows.isEmpty()) return emptyList()
        val orderedUserIds = rows.map { it.userId }.distinct()
        if (orderedUserIds.isEmpty()) return emptyList()
        val profRes = supabase
            .from(BackendContracts.Tables.PROFILES)
            .select(columns = Columns.raw("user_id, username, avatar_url")) {
                filter { isIn("user_id", orderedUserIds) }
            }
        val profiles = decodeFlexibleList<ProfileLite>(profRes.data)
        val byId = profiles.associateBy { it.userId }
        return orderedUserIds.mapNotNull { byId[it] }
    }

    /**
     * @param showBlockingLoader Si false, se actualizan los datos sin pantalla de carga completa (p. ej. tras guardar metadatos).
     */
    fun refresh(showBlockingLoader: Boolean = true) {
        viewModelScope.launch {
            _uiState.value = if (showBlockingLoader) {
                _uiState.value.copy(loading = true, error = null)
            } else {
                _uiState.value.copy(error = null)
            }
            runCatching {
                val workout = supabase
                    .from(BackendContracts.Tables.WORKOUTS)
                    .select(
                        columns = Columns.raw(
                            "id, user_id, kind, title, notes, started_at, ended_at, duration_min, state, " +
                                "perceived_intensity, calories_kcal, " +
                                "cardio_sessions(activity_code, distance_km, duration_sec, modality), " +
                                "sport_sessions(sport)"
                        )
                    ) {
                        filter { eq("id", workoutId) }
                    }
                    .let { decodeFlexibleList<WorkoutDetailRow>(it.data).firstOrNull() }
                    ?: error("Workout not found: $workoutId")

                val owner = runCatching {
                    supabase
                        .from(BackendContracts.Tables.PROFILES)
                        .select(columns = Columns.raw("user_id, username, avatar_url")) {
                            filter { eq("user_id", workout.userId) }
                        }
                        .let { decodeFlexibleList<ProfileLite>(it.data).firstOrNull() }
                }.getOrNull()

                val scores = runCatching {
                    val response = supabase
                        .from(BackendContracts.Tables.WORKOUT_SCORES)
                        .select(columns = Columns.raw("workout_id, score")) {
                            filter { eq("workout_id", workoutId) }
                        }
                    decodeFlexibleList<ScoreRow>(response.data)
                }.getOrDefault(emptyList())
                val totalScore = scores.mapNotNull { it.score }.sum().takeIf { scores.isNotEmpty() }

                val likes = runCatching {
                    val response = supabase
                        .from(BackendContracts.Tables.WORKOUT_LIKES)
                        .select(columns = Columns.raw("user_id")) {
                            filter { eq("workout_id", workoutId) }
                            limit(500)
                        }
                    decodeFlexibleList<LikeRow>(response.data)
                }.getOrDefault(emptyList())
                val me = supabase.auth.currentUserOrNull()?.id
                val mine = me != null && likes.any { it.userId == me }

                val participantIds = runCatching {
                    val response = supabase
                        .from(BackendContracts.Tables.WORKOUT_PARTICIPANTS)
                        .select(columns = Columns.raw("user_id")) {
                            filter { eq("workout_id", workoutId) }
                        }
                    decodeFlexibleList<ParticipantRow>(response.data)
                        .map { it.userId }
                }.getOrDefault(emptyList())

                val participants = if (participantIds.isEmpty()) {
                    emptyList()
                } else {
                    runCatching {
                        val response = supabase
                            .from(BackendContracts.Tables.PROFILES)
                            .select(columns = Columns.raw("user_id, username, avatar_url")) {
                                filter { isIn("user_id", participantIds) }
                                order("username", Order.ASCENDING)
                            }
                        decodeFlexibleList<ProfileLite>(response.data)
                    }.getOrDefault(emptyList())
                }
                val (comments, commentsCanLoadMore) = runCatching {
                    loadFirstPageOfRootComments(
                        meUserId = me,
                        workoutOwnerUserId = workout.userId
                    )
                }.getOrDefault(emptyList<WorkoutCommentUi>() to false)

                val sportSess: SportSessionDetail? =
                    if (workout.kind?.lowercase() == "sport") {
                        runCatching { loadSportSessionForWorkout() }.getOrNull()
                    } else {
                        null
                    }
                val sportEnrich: SportEditEnrichment =
                    if (sportSess != null) {
                        runCatching {
                            loadSportEditEnrichment(
                                supabase = supabase,
                                workoutId = workoutId,
                                sessionId = sportSess.id,
                                spFromSession = sportSess.sport
                            )
                        }.getOrDefault(SportEditEnrichment.empty())
                    } else {
                        SportEditEnrichment.empty()
                    }
                val cardioSess: CardioSessionDetail? =
                    if (workout.kind?.lowercase() == "cardio") {
                        runCatching { loadCardioSessionForWorkout() }.getOrNull()
                    } else {
                        null
                    }
                val strengthEdit: StrengthEditLoadResult? =
                    if (workout.kind?.lowercase() == "strength") {
                        runCatching { loadStrengthEditsForWorkout(supabase, workoutId) }.getOrNull()
                    } else {
                        null
                    }
                val strengthRead: StrengthReadonlyDetail? =
                    if (workout.kind?.lowercase() == "strength") {
                        runCatching { loadStrengthReadonlyForDetail(supabase, workoutId) }.getOrNull()
                    } else {
                        null
                    }
                val sportStatsBundle: WorkoutSportDetailStatsBundle =
                    if (sportSess != null) {
                        runCatching {
                            loadWorkoutSportDetailStats(supabase, sportSess.id, sportSess.sport)
                        }.getOrDefault(WorkoutSportDetailStatsBundle())
                    } else {
                        WorkoutSportDetailStatsBundle()
                    }
                val prev = _uiState.value
                WorkoutDetailUiState(
                    loading = false,
                    workout = workout,
                    owner = owner,
                    totalScore = totalScore,
                    meUserId = me,
                    likeCount = likes.size,
                    isLikedByMe = mine,
                    participants = participants,
                    comments = comments,
                    commentsCanLoadMore = commentsCanLoadMore,
                    commentsLoadingMore = false,
                    sportSession = sportSess,
                    cardioSession = cardioSess,
                    likers = emptyList(),
                    likersLoading = false,
                    compareCandidates = prev.compareCandidates,
                    compareReady = prev.compareReady,
                    compareCandidateId = prev.compareCandidateId,
                    sportEditEnrichment = sportEnrich,
                    strengthEditExercises = strengthEdit?.exercises ?: emptyList(),
                    strengthEditInitialWorkoutExerciseIds = strengthEdit?.initialWorkoutExerciseIds ?: emptySet(),
                    strengthReadonly = strengthRead,
                    sportDetailStats = sportStatsBundle
                )
            }.onSuccess { state ->
                Log.i(TAG, "DETAIL_V2 success. workoutId=$workoutId likes=${state.likeCount} participants=${state.participants.size}")
                _uiState.value = state
                val wk = state.workout
                if (wk != null) {
                    loadCompareCandidatesWithWorkout(wk, state.meUserId)
                }
            }.onFailure { e ->
                Log.e(TAG, "DETAIL_V2 failure workoutId=$workoutId", e)
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    error = "DETAIL_V2: " + (e.message?.take(260) ?: e::class.java.simpleName)
                )
            }
        }
    }

    fun publishPlannedWorkout() {
        val s = _uiState.value
        val w = s.workout ?: return
        if (s.publishBusy) return
        if (w.state?.lowercase() != "planned") return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            if (w.userId != me) return@launch
            _uiState.value = s.copy(publishBusy = true, error = null)
            val result = runCatching {
                val started = w.startedAt?.trim()?.takeIf { it.isNotEmpty() } ?: Instant.now().toString()
                supabase.from(BackendContracts.Tables.WORKOUTS).update(
                    buildJsonObject {
                        put("state", JsonPrimitive("published"))
                        put("started_at", JsonPrimitive(started))
                    }
                ) {
                    filter {
                        eq("id", workoutId)
                        eq("user_id", me)
                    }
                }
            }
            if (result.isSuccess) {
                _uiState.value = _uiState.value.copy(publishBusy = false)
                // Paridad con iOS [WorkoutDetailView] `publishWorkout`: solo update de `workouts`, sin RPC competición.
                refresh(showBlockingLoader = false)
                notifyHomeFeedUpdated()
            } else {
                val e = result.exceptionOrNull()!!
                Log.e(TAG, "publish failed", e)
                _uiState.value = _uiState.value.copy(
                    publishBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun deleteWorkoutAsOwner(onDeleted: () -> Unit) {
        val s = _uiState.value
        if (s.deleteBusy) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            val w = s.workout ?: return@launch
            if (w.userId != me) return@launch
            _uiState.value = s.copy(deleteBusy = true, error = null)
            runCatching {
                supabase.from(BackendContracts.Tables.WORKOUTS).delete {
                    filter {
                        eq("id", workoutId)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(deleteBusy = false)
                notifyHomeFeedUpdated()
                onDeleted()
            }.onFailure { e ->
                Log.e(TAG, "delete failed", e)
                _uiState.value = _uiState.value.copy(
                    deleteBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun updateWorkoutMetaCommon(
        title: String,
        notes: String,
        startedAtIso: String,
        endedAtIso: String,
        endedAtEnabled: Boolean,
        intensity: AddWorkoutIntensity,
        onResult: (Throwable?) -> Unit = {}
    ) {
        val s = _uiState.value
        val w = s.workout ?: return
        if (s.saveMetaBusy) return
        val k = w.kind?.lowercase() ?: return
        if (k !in setOf("strength", "cardio", "sport")) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            if (w.userId != me) return@launch
            _uiState.value = s.copy(saveMetaBusy = true, error = null)
            val result = runCatching {
                val started = startedAtIso.trim()
                    .takeIf { it.isNotEmpty() }
                    ?.let { raw -> Instant.parse(raw) }
                    ?: error("Invalid started time (use ISO-8601).")
                val startedStr = started.toString()
                val endedEl = if (endedAtEnabled) {
                    val e = endedAtIso.trim()
                    if (e.isNotEmpty()) Instant.parse(e) else null
                } else {
                    null
                }
                supabase.from(BackendContracts.Tables.WORKOUTS).update(
                    buildJsonObject {
                        if (title.isNotBlank()) {
                            put("title", JsonPrimitive(title.trim()))
                        } else {
                            put("title", JsonNull)
                        }
                        if (notes.isNotBlank()) {
                            put("notes", JsonPrimitive(notes.trim()))
                        } else {
                            put("notes", JsonNull)
                        }
                        put("started_at", JsonPrimitive(startedStr))
                        if (endedEl != null) {
                            put("ended_at", JsonPrimitive(endedEl.toString()))
                        } else {
                            put("ended_at", JsonNull)
                        }
                        put("perceived_intensity", JsonPrimitive(intensity.wire))
                    }
                ) {
                    filter {
                        eq("id", workoutId)
                        eq("user_id", me)
                    }
                }
            }
            result.onSuccess {
                _uiState.value = _uiState.value.copy(saveMetaBusy = false)
                refresh(showBlockingLoader = false)
                notifyHomeFeedUpdated()
                onResult(null)
            }.onFailure { e ->
                Log.e(TAG, "update meta failed", e)
                _uiState.value = _uiState.value.copy(
                    saveMetaBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
                onResult(e)
            }
        }
    }

    /**
     * Metadatos comunes + ejercicios/series (iOS [EditWorkoutMetaSheet] `case "strength":`).
     */
    fun saveStrengthWorkoutWithExercises(
        title: String,
        notes: String,
        startedAtIso: String,
        endedAtIso: String,
        endedAtEnabled: Boolean,
        intensity: AddWorkoutIntensity,
        exercises: List<StrengthExerciseDraft>,
        onResult: (Throwable?) -> Unit = {}
    ) {
        val s = _uiState.value
        val w = s.workout ?: return
        if (s.saveMetaBusy) return
        if (w.kind?.lowercase() != "strength") return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            if (w.userId != me) return@launch
            if (exercises.isEmpty() || exercises.any { it.exerciseId == null || it.workoutExerciseId == null }) {
                onResult(IllegalArgumentException("Missing strength exercise data"))
                return@launch
            }
            _uiState.value = s.copy(saveMetaBusy = true, error = null)
            val result = runCatching {
                val started = startedAtIso.trim()
                    .takeIf { it.isNotEmpty() }
                    ?.let { raw -> Instant.parse(raw) }
                    ?: error("Invalid started time (use ISO-8601).")
                val startedStr = started.toString()
                val endedEl = if (endedAtEnabled) {
                    val e = endedAtIso.trim()
                    if (e.isNotEmpty()) Instant.parse(e) else null
                } else {
                    null
                }
                supabase.from(BackendContracts.Tables.WORKOUTS).update(
                    buildJsonObject {
                        if (title.isNotBlank()) {
                            put("title", JsonPrimitive(title.trim()))
                        } else {
                            put("title", JsonNull)
                        }
                        if (notes.isNotBlank()) {
                            put("notes", JsonPrimitive(notes.trim()))
                        } else {
                            put("notes", JsonNull)
                        }
                        put("started_at", JsonPrimitive(startedStr))
                        if (endedEl != null) {
                            put("ended_at", JsonPrimitive(endedEl.toString()))
                        } else {
                            put("ended_at", JsonNull)
                        }
                        put("perceived_intensity", JsonPrimitive(intensity.wire))
                    }
                ) {
                    filter {
                        eq("id", workoutId)
                        eq("user_id", me)
                    }
                }

                val initial = s.strengthEditInitialWorkoutExerciseIds
                val currentWids = exercises.map { it.workoutExerciseId!! }.toSet()
                val removed = initial - currentWids
                for (wid in removed) {
                    supabase.from(BackendContracts.Tables.EXERCISE_SETS).delete {
                        filter { eq("workout_exercise_id", wid) }
                    }
                    supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES).delete {
                        filter {
                            eq("id", wid)
                            eq("workout_id", workoutId)
                        }
                    }
                }

                exercises.forEachIndexed { orderIdx, ex ->
                    val weId = ex.workoutExerciseId!!
                    supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES).update(
                        buildJsonObject {
                            put("exercise_id", ex.exerciseId!!)
                            put("order_index", orderIdx + 1)
                            if (ex.notes.isNotBlank()) {
                                put("notes", JsonPrimitive(ex.notes.trim()))
                            } else {
                                put("notes", JsonNull)
                            }
                            if (ex.customName.isNotBlank()) {
                                put("custom_name", JsonPrimitive(ex.customName.trim()))
                            } else {
                                put("custom_name", JsonNull)
                            }
                        }
                    ) {
                        filter { eq("id", weId) }
                    }
                }

                if (currentWids.isNotEmpty()) {
                    supabase.from(BackendContracts.Tables.EXERCISE_SETS).delete {
                        filter { isIn("workout_exercise_id", currentWids.toList()) }
                    }
                }
                for (ex in exercises) {
                    val weId = ex.workoutExerciseId!!
                    for (st in ex.sets) {
                        val p = draftSetToStrengthPayload(st) ?: continue
                        val row = buildJsonObject {
                            put("workout_exercise_id", weId)
                            put("set_number", p.setNumber.coerceIn(1, 99))
                            if (p.reps != null) put("reps", p.reps)
                            if (p.weightKg != null) put("weight_kg", p.weightKg)
                            if (p.rpe != null) put("rpe", p.rpe)
                            if (p.restSec != null) put("rest_sec", p.restSec)
                            p.weightSegments?.takeIf { it.size >= 2 }?.let { segs ->
                                put("weight_segments", weightSegmentsToJsonArray(segs))
                            }
                        }
                        supabase.from(BackendContracts.Tables.EXERCISE_SETS).insert(row) { }
                    }
                }
            }
            result.onSuccess {
                _uiState.value = _uiState.value.copy(saveMetaBusy = false)
                refresh(showBlockingLoader = false)
                notifyHomeFeedUpdated()
                onResult(null)
            }.onFailure { e ->
                Log.e(TAG, "save strength meta failed", e)
                _uiState.value = _uiState.value.copy(
                    saveMetaBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
                onResult(e)
            }
        }
    }

    private suspend fun loadSportSessionForWorkout(): SportSessionDetail? {
        val cRes = supabase
            .from(BackendContracts.Tables.SPORT_SESSIONS)
            .select(
                columns = Columns.raw(
                    "id, sport, duration_sec, score_for, score_against, " +
                        "match_result, match_score_text, location, notes"
                )
            ) {
                filter { eq("workout_id", workoutId) }
                limit(1)
            }
        val row = decodeFlexibleList<SportSessionWire>(cRes.data).firstOrNull() ?: return null
        return SportSessionDetail(
            id = row.id,
            sport = row.sport,
            durationSec = row.durationSec,
            scoreFor = row.scoreFor,
            scoreAgainst = row.scoreAgainst,
            matchResult = row.matchResult,
            matchScoreText = row.matchScoreText,
            location = row.location,
            notes = row.notes
        )
    }

    private suspend fun loadCardioSessionForWorkout(): CardioSessionDetail? {
        val cRes = supabase
            .from(BackendContracts.Tables.CARDIO_SESSIONS)
            .select(
                columns = Columns.raw(
                    "id, activity_code, modality, distance_km, duration_sec, " +
                        "avg_hr, max_hr, avg_pace_sec_per_km, elevation_gain_m, notes, route_geojson"
                )
            ) {
                filter { eq("workout_id", workoutId) }
                limit(1)
            }
        val w = decodeFlexibleList<CardioSessionWire>(cRes.data).firstOrNull() ?: return null
        val extras: CardioSessionExtras? = runCatching {
            val sRes = supabase
                .from(BackendContracts.Tables.CARDIO_SESSION_STATS)
                .select(columns = Columns.raw("stats")) {
                    filter { eq("session_id", w.id) }
                    limit(1)
                }
            decodeFlexibleList<CardioSessionStatsRow>(sRes.data).firstOrNull()?.stats
        }.getOrNull()
        val capture = TerritoryCaptureClient.fetchCaptureEvent(supabase, workoutId)
        val territoryTakeovers = TerritoryCaptureClient.fetchWorkoutTakeovers(supabase, workoutId)
        val territoryPreviewRings =
            if ((capture?.cellsGained ?: 0) > 0 && !w.routeGeojson.isNullOrBlank()) {
                TerritoryCaptureClient.fetchTerritoryPreviewRings(supabase, w.routeGeojson)
            } else {
                emptyList()
            }
        return CardioSessionDetail(
            id = w.id,
            activityCode = w.activityCode,
            modality = w.modality,
            distanceKm = w.distanceKm,
            durationSec = w.durationSec,
            avgHr = w.avgHr,
            maxHr = w.maxHr,
            avgPaceSecPerKm = w.avgPaceSecPerKm,
            elevationGainM = w.elevationGainM,
            notes = w.notes,
            routeGeojson = w.routeGeojson,
            extras = extras,
            territoryCellsGained = capture?.cellsGained,
            territoryCellsTaken = capture?.cellsTaken,
            territoryPreviewRings = territoryPreviewRings,
            territoryTakeovers = territoryTakeovers
        )
    }

    fun updateSportWorkoutMeta(
        title: String,
        notes: String,
        startedAtIso: String,
        endedAtIso: String,
        endedAtEnabled: Boolean,
        intensity: AddWorkoutIntensity,
        durationMinText: String,
        scoreForText: String,
        scoreAgainstText: String,
        matchResultRaw: String,
        matchScoreText: String,
        location: String,
        sessionNotes: String,
        onResult: (Throwable?) -> Unit = {}
    ) {
        val s = _uiState.value
        val w = s.workout ?: return
        val session = s.sportSession
        if (s.saveMetaBusy) return
        if (w.kind?.lowercase() != "sport" || session == null) return
        val sportType = addSportTypeFromWire(session.sport) ?: return
        val enrich = s.sportEditEnrichment
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            if (w.userId != me) return@launch
            _uiState.value = s.copy(saveMetaBusy = true, error = null)
            val result = runCatching {
                val started = startedAtIso.trim()
                    .takeIf { it.isNotEmpty() }
                    ?.let { raw -> Instant.parse(raw) } ?: error("Invalid started time (use ISO-8601).")
                val startedStr = started.toString()
                val endedEl = if (endedAtEnabled) {
                    val e = endedAtIso.trim()
                    if (e.isNotEmpty()) Instant.parse(e) else null
                } else {
                    null
                }
                val durationMin = parseIntLocal(durationMinText) ?: session.durationSec?.let { d ->
                    ((d + 59) / 60).coerceAtLeast(1)
                }
                val sFor = parseIntLocal(scoreForText)
                val sAgainst = parseIntLocal(scoreAgainstText)
                val p = buildJsonObject {
                    if (title.isNotBlank()) put("p_title", JsonPrimitive(title.trim())) else put("p_title", JsonNull)
                    if (notes.isNotBlank()) put("p_notes", JsonPrimitive(notes.trim())) else put("p_notes", JsonNull)
                    put("p_started_at", JsonPrimitive(startedStr))
                    if (endedEl != null) {
                        put("p_ended_at", JsonPrimitive(endedEl.toString()))
                    } else {
                        put("p_ended_at", JsonNull)
                    }
                    put("p_perceived_intensity", JsonPrimitive(intensity.wire))
                    put("p_sport", JsonPrimitive(session.sport.trim().lowercase()))
                    if (durationMin != null) {
                        put("p_duration_min", JsonPrimitive(durationMin))
                    } else {
                        put("p_duration_min", JsonNull)
                    }
                    if (sFor != null) {
                        put("p_score_for", JsonPrimitive(sFor))
                    } else {
                        put("p_score_for", JsonNull)
                    }
                    if (sAgainst != null) {
                        put("p_score_against", JsonPrimitive(sAgainst))
                    } else {
                        put("p_score_against", JsonNull)
                    }
                    if (sportType != AddSportType.SKI) {
                        val mr = normalizeSportMatchResult(matchResultRaw)
                        put("p_match_result", JsonPrimitive(mr))
                    } else {
                        put("p_match_result", JsonNull)
                    }
                    if (matchScoreText.isNotBlank()) {
                        put("p_match_score_text", JsonPrimitive(matchScoreText.trim()))
                    } else {
                        put("p_match_score_text", JsonNull)
                    }
                    if (location.isNotBlank()) {
                        put("p_location", JsonPrimitive(location.trim()))
                    } else {
                        put("p_location", JsonNull)
                    }
                    if (sessionNotes.isNotBlank()) {
                        put("p_session_notes", JsonPrimitive(sessionNotes.trim()))
                    } else {
                        put("p_session_notes", JsonNull)
                    }
                }
                val pStats = SportStatsPayloadBuilder.build(
                    sport = sportType,
                    durationMinText = durationMinText,
                    footballPosition = enrich.footballPosition,
                    racketMode = enrich.racketMode,
                    racketFormat = enrich.racketFormat,
                    sportStats = enrich.sportStats,
                    hyroxExercisesText = enrich.hyroxExercisesJson
                )
                val wrapper = buildJsonObject {
                    put("p_workout_id", JsonPrimitive(workoutId))
                    put("p", p)
                    put("p_stats", pStats)
                }
                supabase.postgrest.rpc(BackendContracts.Rpc.UPDATE_SPORT_WORKOUT_V2, wrapper) { }
                if (sportType == AddSportType.HYROX) {
                    patchHyroxDisplayNamesAfterSportEdit(session.id, enrich.hyroxExercisesJson)
                }
            }
            result.onSuccess {
                _uiState.value = _uiState.value.copy(saveMetaBusy = false)
                refresh(showBlockingLoader = false)
                notifyHomeFeedUpdated()
                onResult(null)
            }.onFailure { e ->
                Log.e(TAG, "update sport meta failed", e)
                _uiState.value = _uiState.value.copy(
                    saveMetaBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
                onResult(e)
            }
        }
    }

    private suspend fun patchHyroxDisplayNamesAfterSportEdit(
        sessionId: Int,
        hyroxExercisesText: String
    ) {
        if (hyroxExercisesText.isBlank()) return
        val arr = runCatching { json.parseToJsonElement(hyroxExercisesText.trim()).jsonArray }
            .getOrNull() ?: return
        if (arr.isEmpty()) return
        @Serializable
        data class HyroxDisplayNamePatch(
            @SerialName("exercise_display_name") val exerciseDisplayName: String
        )
        for ((idx, el) in arr.withIndex()) {
            val o = el as? JsonObject ?: continue
            val code = o["exercise_code"]?.jsonPrimitive?.contentOrNull
                ?: o["exerciseCode"]?.jsonPrimitive?.contentOrNull
                ?: continue
            val custom = o["exercise_display_name"]?.jsonPrimitive?.contentOrNull
                ?: o["custom_display_name"]?.jsonPrimitive?.contentOrNull
                ?: ""
            val notes = o["notes"]?.jsonPrimitive?.contentOrNull ?: ""
            val order = idx + 1
            val display = HyroxExerciseFormatting.persistedPayload(code, custom, notes).displayName
                ?: continue
            runCatching {
                supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES).update(
                    HyroxDisplayNamePatch(exerciseDisplayName = display)
                ) {
                    filter {
                        eq("session_id", sessionId)
                        eq("exercise_order", order)
                    }
                }
            }.onFailure { e ->
                Log.w(TAG, "hyrox display name patch failed order=$order", e)
            }
        }
    }

    fun updateCardioWorkoutMeta(
        title: String,
        notes: String,
        startedAtIso: String,
        endedAtIso: String,
        endedAtEnabled: Boolean,
        intensity: AddWorkoutIntensity,
        activity: AddCardioActivity,
        distanceKm: String,
        durH: String,
        durM: String,
        durS: String,
        avgHr: String,
        maxHr: String,
        avgPaceSecPerKm: String,
        elevationM: String,
        cadenceRpm: String,
        wattsAvg: String,
        inclinePct: String,
        splitSecPer500m: String,
        kmSplitsPaceText: String,
        swimLaps: String,
        poolLengthM: String,
        swimStyle: String,
        onResult: (Throwable?) -> Unit = {}
    ) {
        val s = _uiState.value
        val w = s.workout ?: return
        val card = s.cardioSession
        if (s.saveMetaBusy) return
        if (w.kind?.lowercase() != "cardio" || card == null) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            if (w.userId != me) return@launch
            _uiState.value = s.copy(saveMetaBusy = true, error = null)
            val result = runCatching {
                val started = startedAtIso.trim()
                    .takeIf { it.isNotEmpty() }
                    ?.let { raw -> Instant.parse(raw) }
                    ?: error("Invalid started time (use ISO-8601).")
                val startedStr = started.toString()
                val endedEl = if (endedAtEnabled) {
                    val e = endedAtIso.trim()
                    if (e.isNotEmpty()) Instant.parse(e) else null
                } else {
                    null
                }
                supabase.from(BackendContracts.Tables.WORKOUTS).update(
                    buildJsonObject {
                        if (title.isNotBlank()) {
                            put("title", JsonPrimitive(title.trim()))
                        } else {
                            put("title", JsonNull)
                        }
                        if (notes.isNotBlank()) {
                            put("notes", JsonPrimitive(notes.trim()))
                        } else {
                            put("notes", JsonNull)
                        }
                        put("started_at", JsonPrimitive(startedStr))
                        if (endedEl != null) {
                            put("ended_at", JsonPrimitive(endedEl.toString()))
                        } else {
                            put("ended_at", JsonNull)
                        }
                        put("perceived_intensity", JsonPrimitive(intensity.wire))
                    }
                ) {
                    filter {
                        eq("id", workoutId)
                        eq("user_id", me)
                    }
                }
                val durationSec = parseHmsToSec(durH, durM, durS) ?: card.durationSec
                supabase.from(BackendContracts.Tables.CARDIO_SESSIONS).update(
                    buildJsonObject {
                        put("modality", JsonPrimitive(activity.wire))
                        put("activity_code", JsonPrimitive(activity.wire))
                        distanceKm.trim().replace(",", ".").toDoubleOrNull()?.let {
                            put("distance_km", JsonPrimitive(it))
                        }
                        if (durationSec != null && durationSec > 0) {
                            put("duration_sec", JsonPrimitive(durationSec))
                        }
                        parseIntLocal(avgHr)?.let { put("avg_hr", JsonPrimitive(it)) }
                        parseIntLocal(maxHr)?.let { put("max_hr", JsonPrimitive(it)) }
                        parseIntLocal(avgPaceSecPerKm)?.let { put("avg_pace_sec_per_km", JsonPrimitive(it)) }
                        parseIntLocal(elevationM)?.let { put("elevation_gain_m", JsonPrimitive(it)) }
                    }
                ) {
                    filter { eq("workout_id", workoutId) }
                }
                val statsObj = buildJsonObject {
                    parseIntLocal(cadenceRpm)?.let { put("cadence_rpm", JsonPrimitive(it)) }
                    parseIntLocal(wattsAvg)?.let { put("watts_avg", JsonPrimitive(it)) }
                    parseDoubleLocal(inclinePct)?.let { put("incline_pct", JsonPrimitive(it)) }
                    parseIntLocal(splitSecPer500m)?.let { put("split_sec_per_500m", JsonPrimitive(it)) }
                    parseIntLocal(swimLaps)?.let { put("swim_laps", JsonPrimitive(it)) }
                    parseIntLocal(poolLengthM)?.let { put("pool_length_m", JsonPrimitive(it)) }
                    if (swimStyle.isNotBlank()) {
                        put("swim_style", JsonPrimitive(swimStyle.trim()))
                    }
                    val splits = CardioKmPaceSplits.parseFieldText(kmSplitsPaceText)
                    if (splits.isNotEmpty()) {
                        put(
                            CardioKmPaceSplits.JSON_KEY,
                            buildJsonArray { splits.forEach { add(JsonPrimitive(it)) } }
                        )
                    }
                }
                supabase.from(BackendContracts.Tables.CARDIO_SESSION_STATS).upsert(
                    buildJsonObject {
                        put("session_id", card.id)
                        put("stats", statsObj)
                    }
                ) {
                    onConflict = "session_id"
                }
            }
            result.onSuccess {
                _uiState.value = _uiState.value.copy(saveMetaBusy = false)
                refresh(showBlockingLoader = false)
                notifyHomeFeedUpdated()
                onResult(null)
            }.onFailure { e ->
                Log.e(TAG, "update cardio meta failed", e)
                _uiState.value = _uiState.value.copy(
                    saveMetaBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
                onResult(e)
            }
        }
    }

    private fun parseHmsToSec(h: String, m: String, s: String): Int? {
        val hour = h.trim().toIntOrNull() ?: 0
        val min = m.trim().toIntOrNull() ?: 0
        val sec = s.trim().toIntOrNull() ?: 0
        if (min !in 0..59 || sec !in 0..59 || hour < 0) return null
        val total = hour * 3600 + min * 60 + sec
        return total.takeIf { it > 0 }
    }

    private fun parseDoubleLocal(t: String): Double? =
        t.trim().replace(",", ".").toDoubleOrNull()

    private fun parseIntLocal(t: String): Int? = t.trim().toIntOrNull()

    fun toggleLike() {
        if (_uiState.value.likeBusy) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            _uiState.value = _uiState.value.copy(likeBusy = true, error = null)
            runCatching {
                if (_uiState.value.isLikedByMe) {
                    supabase.from(BackendContracts.Tables.WORKOUT_LIKES).delete {
                        filter {
                            eq("workout_id", workoutId)
                            eq("user_id", me)
                        }
                    }
                } else {
                    @Serializable
                    data class LikeInsert(
                        @SerialName("workout_id") val workoutId: Int,
                        @SerialName("user_id") val userId: String
                    )
                    supabase.from(BackendContracts.Tables.WORKOUT_LIKES).insert(
                        LikeInsert(workoutId = workoutId, userId = me)
                    ) { }
                }
            }.onSuccess {
                val nowLiked = !_uiState.value.isLikedByMe
                val newCount = (_uiState.value.likeCount + if (nowLiked) 1 else -1).coerceAtLeast(0)
                _uiState.value = _uiState.value.copy(
                    isLikedByMe = nowLiked,
                    likeCount = newCount,
                    likeBusy = false
                )
                notifyHomeFeedUpdated()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    likeBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
            }
        }
    }

    private fun notifyHomeFeedUpdated() {
        HomeFeedSync.notifyWorkoutChanged(workoutId)
    }

    fun sendComment(body: String, parentId: Int? = null, onSent: () -> Unit = {}) {
        val trimmed = body.trim()
        if (trimmed.isEmpty() || _uiState.value.commentBusy) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            _uiState.value = _uiState.value.copy(commentBusy = true, error = null)
            runCatching {
                supabase.from(BackendContracts.Tables.WORKOUT_COMMENTS).insert(
                    CommentInsert(
                        workoutId = workoutId,
                        userId = me,
                        body = trimmed,
                        parentId = parentId
                    )
                ) { }
                val (comments, canMore) = loadFirstPageOfRootComments(
                    meUserId = me,
                    workoutOwnerUserId = _uiState.value.workout?.userId
                )
                comments to canMore
            }.onSuccess { (comments, canMore) ->
                _uiState.value = _uiState.value.copy(
                    commentBusy = false,
                    comments = comments,
                    commentsCanLoadMore = canMore
                )
                onSent()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    commentBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
            }
        }
    }

    /**
     * Paridad con [Liftr/CommentView] `loadPage` (más comentarios raíz).
     */
    fun loadMoreComments() {
        val s = _uiState.value
        if (s.commentsLoadingMore || !s.commentsCanLoadMore || s.workout == null) return
        viewModelScope.launch {
            val page = nextCommentPage
            if (page <= 0) return@launch
            _uiState.value = _uiState.value.copy(commentsLoadingMore = true, error = null)
            val me = _uiState.value.meUserId
            val owner = _uiState.value.workout?.userId
            runCatching {
                val (newRows, canMore) = loadRootCommentsPage(page, me, owner)
                val merged = _uiState.value.comments + newRows
                nextCommentPage = if (canMore) page + 1 else page
                _uiState.value = _uiState.value.copy(
                    comments = merged,
                    commentsCanLoadMore = canMore,
                    commentsLoadingMore = false
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    commentsLoadingMore = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun toggleCommentLike(commentId: Int) {
        if (_uiState.value.commentBusy) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            val comment = findCommentById(_uiState.value.comments, commentId) ?: return@launch
            _uiState.value = _uiState.value.copy(commentBusy = true, error = null)
            runCatching {
                if (comment.likedByMe) {
                    supabase.from(BackendContracts.Tables.WORKOUT_COMMENT_LIKES).delete {
                        filter {
                            eq("comment_id", commentId)
                            eq("user_id", me)
                        }
                    }
                } else {
                    supabase.from(BackendContracts.Tables.WORKOUT_COMMENT_LIKES).insert(
                        CommentLikeInsert(commentId = commentId, userId = me)
                    ) { }
                }
            }.onSuccess {
                val updated = updateCommentById(_uiState.value.comments, commentId) { current ->
                    val nowLiked = !current.likedByMe
                    current.copy(
                        likedByMe = nowLiked,
                        likesCount = (current.likesCount + if (nowLiked) 1 else -1).coerceAtLeast(0)
                    )
                }
                _uiState.value = _uiState.value.copy(commentBusy = false, comments = updated)
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    commentBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun toggleReplies(commentId: Int) {
        viewModelScope.launch {
            val root = findCommentById(_uiState.value.comments, commentId) ?: return@launch
            if (root.repliesLoaded) {
                _uiState.value = _uiState.value.copy(
                    comments = updateCommentById(_uiState.value.comments, commentId) {
                        it.copy(isExpanded = !it.isExpanded)
                    }
                )
                return@launch
            }

            val loadedReplies = runCatching {
                loadReplies(commentId)
            }.getOrElse { e ->
                _uiState.value = _uiState.value.copy(error = e.message?.take(250) ?: e::class.java.simpleName)
                return@launch
            }
            _uiState.value = _uiState.value.copy(
                comments = updateCommentById(_uiState.value.comments, commentId) {
                    it.copy(
                        repliesLoaded = true,
                        isExpanded = true,
                        replies = loadedReplies
                    )
                }
            )
        }
    }

    private suspend fun loadReplies(parentId: Int): List<WorkoutCommentUi> {
        val rows = supabase
            .from(BackendContracts.Tables.WORKOUT_COMMENTS)
            .select(columns = Columns.raw("id, user_id, body, created_at, parent_id, deleted_at, likes_count, replies_count")) {
                filter {
                    eq("workout_id", workoutId)
                    eq("parent_id", parentId)
                }
                order("created_at", Order.ASCENDING)
                limit(200)
            }
            .let { decodeFlexibleList<CommentRow>(it.data) }

        return mapCommentRows(
            rows = rows,
            meUserId = _uiState.value.meUserId,
            workoutOwnerUserId = _uiState.value.workout?.userId
        )
    }

    fun deleteComment(commentId: Int) {
        if (_uiState.value.commentBusy) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            _uiState.value = _uiState.value.copy(commentBusy = true, error = null)
            runCatching {
                @Serializable
                data class DeletePatch(
                    @SerialName("deleted_at") val deletedAt: String,
                    @SerialName("deleted_by") val deletedBy: String
                )
                supabase.from(BackendContracts.Tables.WORKOUT_COMMENTS).update(
                    DeletePatch(
                        deletedAt = Instant.now().toString(),
                        deletedBy = me
                    )
                ) {
                    filter { eq("id", commentId) }
                }

                val (comments, canMore) = loadFirstPageOfRootComments(
                    meUserId = me,
                    workoutOwnerUserId = _uiState.value.workout?.userId
                )
                comments to canMore
            }.onSuccess { (comments, canMore) ->
                _uiState.value = _uiState.value.copy(
                    commentBusy = false,
                    comments = comments,
                    commentsCanLoadMore = canMore
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    commentBusy = false,
                    error = e.message?.take(250) ?: e::class.java.simpleName
                )
            }
        }
    }

    private suspend fun loadFirstPageOfRootComments(
        meUserId: String?,
        workoutOwnerUserId: String?
    ): Pair<List<WorkoutCommentUi>, Boolean> {
        nextCommentPage = 0
        val (list, canMore) = loadRootCommentsPage(0, meUserId, workoutOwnerUserId)
        nextCommentPage = if (canMore) 1 else 0
        return list to canMore
    }

    private suspend fun loadRootCommentsPage(
        pageIndex: Int,
        meUserId: String?,
        workoutOwnerUserId: String?
    ): Pair<List<WorkoutCommentUi>, Boolean> {
        val from = pageIndex * COMMENT_PAGE_SIZE
        val to = from + COMMENT_PAGE_SIZE - 1
        val rows = supabase
            .from(BackendContracts.Tables.WORKOUT_COMMENTS)
            .select(columns = Columns.raw("id, user_id, body, created_at, parent_id, deleted_at, likes_count, replies_count")) {
                filter {
                    eq("workout_id", workoutId)
                    filter("parent_id", FilterOperator.IS, null)
                }
                order("created_at", Order.ASCENDING)
                range(from.toLong(), to.toLong())
            }
            .let { decodeFlexibleList<CommentRow>(it.data) }
        val mapped = mapCommentRows(rows, meUserId, workoutOwnerUserId)
        return mapped to (rows.size == COMMENT_PAGE_SIZE)
    }

    private suspend fun mapCommentRows(
        rows: List<CommentRow>,
        meUserId: String?,
        workoutOwnerUserId: String?
    ): List<WorkoutCommentUi> {
        if (rows.isEmpty()) return emptyList()

        val userIds = rows.map { it.userId }.distinct()
        val byUser = runCatching {
            supabase
                .from(BackendContracts.Tables.PROFILES)
                .select(columns = Columns.raw("user_id, username, avatar_url")) {
                    filter { isIn("user_id", userIds) }
                }
                .let { decodeFlexibleList<ProfileLite>(it.data) }
                .associateBy { it.userId }
        }.getOrDefault(emptyMap())

        val likedByMe = if (meUserId != null) {
            runCatching {
                supabase
                    .from(BackendContracts.Tables.WORKOUT_COMMENT_LIKES)
                    .select(columns = Columns.raw("comment_id")) {
                        filter {
                            eq("user_id", meUserId)
                            isIn("comment_id", rows.map { it.id })
                        }
                        limit(500)
                    }
                    .let { decodeFlexibleList<CommentLikeRow>(it.data).map { row -> row.commentId }.toSet() }
            }.getOrDefault(emptySet())
        } else {
            emptySet()
        }

        return rows.map { row ->
            WorkoutCommentUi(
                id = row.id,
                userId = row.userId,
                parentId = row.parentId,
                username = byUser[row.userId]?.username,
                body = if (row.deletedAt != null) "[deleted]" else (row.body ?: ""),
                createdAt = row.createdAt,
                canDelete = meUserId != null && (meUserId == row.userId || meUserId == workoutOwnerUserId),
                likesCount = row.likesCount ?: 0,
                likedByMe = likedByMe.contains(row.id),
                repliesCount = row.repliesCount ?: 0
            )
        }
    }

    private fun findCommentById(list: List<WorkoutCommentUi>, id: Int): WorkoutCommentUi? {
        list.forEach { c ->
            if (c.id == id) return c
            val nested = findCommentById(c.replies, id)
            if (nested != null) return nested
        }
        return null
    }

    private fun updateCommentById(
        list: List<WorkoutCommentUi>,
        id: Int,
        transform: (WorkoutCommentUi) -> WorkoutCommentUi
    ): List<WorkoutCommentUi> = list.map { comment ->
        when {
            comment.id == id -> transform(comment)
            comment.replies.isNotEmpty() -> comment.copy(
                replies = updateCommentById(comment.replies, id, transform)
            )
            else -> comment
        }
    }

    /**
     * Paridad con [WorkoutDetailView.rpcCreateLinkedStrengthCopy] (iOS): copia vinculada de fuerza
     * para un usuario participante.
     */
    suspend fun createLinkedStrengthWorkoutCopy(targetUserId: String): Int =
        withContext(Dispatchers.IO) {
            val p = buildJsonObject {
                put("p_source_workout_id", JsonPrimitive(workoutId))
                put("p_target_user_id", JsonPrimitive(targetUserId))
            }
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.CREATE_LINKED_STRENGTH_WORKOUT_COPY,
                p
            ) { }
            parseIdFromCreateLinkedRpc(res.data) ?: error("Invalid linked copy response")
        }

    /**
     * Marca inicio, fuerza [kind] = strength si aplica, y crea entreno vinculado para un participante.
     * [participantUserId] nulo = solo tú (sin RPC de copia).
     */
    fun preparePlannedStrengthAndLinkedGuest(
        participantUserId: String?,
        onResult: (Result<Int?>) -> Unit
    ) {
        val w = _uiState.value.workout ?: return
        viewModelScope.launch {
            val r = runCatching {
                patchWorkoutStartedAtNow(supabase, workoutId)
                if (w.kind?.lowercase() != "strength") {
                    supabase.from(BackendContracts.Tables.WORKOUTS).update(
                        buildJsonObject { put("kind", JsonPrimitive("strength")) }
                    ) {
                        filter { eq("id", workoutId) }
                    }
                }
                if (participantUserId == null) return@runCatching null
                createLinkedStrengthWorkoutCopy(participantUserId)
            }
            onResult(r)
        }
    }

    /**
     * Paridad con iOS [WorkoutDetailView.startPlannedTrioStrength]: dos copias vinculadas.
     * Devuelve Pair(guest1WorkoutId, guest2WorkoutId).
     */
    fun preparePlannedStrengthTrio(
        guestAUserId: String,
        guestBUserId: String,
        onResult: (Result<Pair<Int, Int>>) -> Unit
    ) {
        val w = _uiState.value.workout ?: return
        viewModelScope.launch {
            val r = runCatching {
                patchWorkoutStartedAtNow(supabase, workoutId)
                if (w.kind?.lowercase() != "strength") {
                    supabase.from(BackendContracts.Tables.WORKOUTS).update(
                        buildJsonObject { put("kind", JsonPrimitive("strength")) }
                    ) {
                        filter { eq("id", workoutId) }
                    }
                }
                val id1 = createLinkedStrengthWorkoutCopy(guestAUserId)
                val id2 = createLinkedStrengthWorkoutCopy(guestBUserId)
                id1 to id2
            }
            onResult(r)
        }
    }

    private fun parseIdFromCreateLinkedRpc(raw: String): Int? {
        val trimmed = raw.trim()
        trimmed.toLongOrNull()?.let { return it.toInt() }
        runCatching { JSONArray(trimmed).optLong(0) }.getOrNull()?.let { if (it > 0) return it.toInt() }
        runCatching { JSONObject(trimmed).optLong("id") }.getOrNull()?.let { if (it > 0) return it.toInt() }
        return null
    }

    private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }
}

class WorkoutDetailViewModelFactory(
    private val supabase: SupabaseClient,
    private val workoutId: Int
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != WorkoutDetailViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return WorkoutDetailViewModel(supabase, workoutId) as T
    }
}
