package com.lilru.liftr.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.loadProfileAvatarUrl
import com.lilru.liftr.data.SupabaseResponseDecoding
import com.lilru.liftr.ui.goals.LiftrGoalsTime
import com.lilru.liftr.ui.notifications.UnreadNotificationCounter
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.floor

@Serializable
private data class ProfileRow(
    @SerialName("user_id") val userId: String,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    val bio: String? = null,
    /** [Double] (no [Int]) para que JSON con decimales o numeric no rompa la deserialización. */
    @SerialName("height_cm") val heightCm: Double? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    @SerialName("date_of_birth") val dateOfBirth: String? = null
)

@Serializable
private data class ProfileCountsRow(
    @SerialName("user_id") val userId: String,
    val followers: Int = 0,
    val following: Int = 0
)

@Serializable
private data class UserLevelRow(
    val level: Int = 1,
    val xp: Long = 0
)

@Serializable
private data class FollowEdge(
    @SerialName("follower_id") val followerId: String,
    @SerialName("followee_id") val followeeId: String
)

@Serializable
private data class WeeklyGoalHeaderWire(
    val id: Long,
    @SerialName("user_id") val userId: String,
    @SerialName("week_start") val weekStart: String,
    val metric: String,
    @SerialName("target_value") val targetValue: Double,
    val title: String? = null
)

@Serializable
private data class WeeklyResultHeaderWire(
    @SerialName("goal_id") val goalId: Long,
    @SerialName("is_completed") val isCompleted: Boolean = false
)

@Serializable
private data class AchHeaderWire(
    @SerialName("is_unlocked") val isUnlocked: Boolean = false
)

private data class HeaderSnippets(
    val goalsDone: Int,
    val goalsTotal: Int,
    val achUnlocked: Int,
    val achTotal: Int
)

data class ProfileUiState(
    val loading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val userId: String? = null,
    val isOwnProfile: Boolean = true,
    val isFollowing: Boolean = false,
    val followBusy: Boolean = false,
    val email: String? = null,
    val username: String? = null,
    val avatarUrl: String? = null,
    val bio: String? = null,
    val followers: Int = 0,
    val following: Int = 0,
    val unreadNotifications: Int = 0,
    val level: Int = 1,
    val xp: Long = 0,
    /** XP necesarios para el siguiente nivel (umbral nivel+1; paridad iOS [ProfileView] `nextLevelXP`). */
    val nextLevelXp: Long = 120L,
    /** Nombre de usuario con fallback a prefijo de email (cabecera). */
    val displayName: String? = null,
    val saveBioBusy: Boolean = false,
    val uploadAvatarBusy: Boolean = false,
    val deleteAccountBusy: Boolean = false,
    /** Borradores de “Personal information” (paridad [Liftr/ProfileView.swift] settings). */
    val heightCmDraft: String = "",
    val weightKgDraft: String = "",
    val hasBirthDate: Boolean = false,
    val birthDateMillis: Long? = null,
    val saveProfileMetricsBusy: Boolean = false,
    val weeklyGoalsDone: Int = 0,
    val weeklyGoalsTotal: Int = 0,
    val achievementsUnlocked: Int = 0,
    val achievementsTotal: Int = 0
)

class ProfileViewModel(
    private val supabase: SupabaseClient,
    private val targetUserId: String? = null
) : ViewModel() {
    private val _uiState = MutableStateFlow(ProfileUiState())
    val uiState: StateFlow<ProfileUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    /**
     * @param showBlockingLoader false al tirar de refresh sin ocultar la pantalla (p. ej. pull-to-refresh).
     */
    fun refresh(showBlockingLoader: Boolean = true) {
        viewModelScope.launch {
            _uiState.value = if (showBlockingLoader) {
                _uiState.value.copy(loading = true, error = null, isRefreshing = false)
            } else {
                _uiState.value.copy(isRefreshing = true, error = null)
            }
            try {
                val user = supabase.auth.currentUserOrNull() ?: error("No active session")
                val uid = targetUserId ?: user.id
                val isOwnProfile = uid == user.id

                val profile = runCatching {
                    supabase.from(BackendContracts.Tables.PROFILES)
                        .select(
                            columns = Columns.raw(
                                "user_id, username, avatar_url, bio, height_cm, weight_kg, date_of_birth"
                            )
                        ) {
                            filter { eq("user_id", uid) }
                            limit(1)
                        }
                        .let { SupabaseResponseDecoding.decodeListOrObject<ProfileRow>(it.data).firstOrNull() }
                }.getOrNull()

                // Si la fila no deserializó, el icono de perfil aún leía el avatar con el parser básico; alineamos aquí.
                val resolvedAvatar: String? =
                    profile?.avatarUrl?.trim()?.takeIf { it.isNotEmpty() }
                        ?: if (profile == null) loadProfileAvatarUrl(supabase, uid) else null

                val counts = runCatching {
                    supabase.from(BackendContracts.Views.VW_PROFILE_COUNTS)
                        .select(columns = Columns.raw("user_id, followers, following")) {
                            filter { eq("user_id", uid) }
                            limit(1)
                        }
                        .let { SupabaseResponseDecoding.decodeListOrObject<ProfileCountsRow>(it.data).firstOrNull() }
                }.getOrNull()

                val level = runCatching {
                    supabase.postgrest
                        .rpc(
                            BackendContracts.Rpc.GET_USER_LEVEL,
                            buildJsonObject { put("p_user", uid) }
                        ) { }
                        .let { SupabaseResponseDecoding.decodeListOrObject<UserLevelRow>(it.data).firstOrNull() }
                }.getOrNull()

                val currentLevel = level?.level?.takeIf { it > 0 } ?: 1
                val levelAny: List<Any> = listOf(currentLevel, currentLevel + 1).map { it as Any }
                val nextLevelXp: Long = runCatching {
                    supabase.from(BackendContracts.Tables.LEVEL_THRESHOLDS)
                        .select(columns = Columns.raw("level, xp_required")) {
                            filter { isIn("level", levelAny) }
                        }
                        .let { res ->
                            val rows = SupabaseResponseDecoding.decodeListOrObject<LevelThresholdRow>(res.data)
                            val next = rows.firstOrNull { it.level == currentLevel + 1 }?.xpRequired
                            val fallback = rows.firstOrNull { it.level == currentLevel }?.xpRequired
                            (next ?: fallback) ?: 120L
                        }
                }.getOrDefault(120L)

                val unreadNotifications = if (isOwnProfile) {
                    UnreadNotificationCounter.count(supabase)
                } else {
                    0
                }

                val isFollowing = if (isOwnProfile) {
                    false
                } else {
                    runCatching {
                        supabase.from(BackendContracts.Tables.FOLLOWS)
                            // Necesitamos ambas columnas: si solo pides follower_id, el JSON no trae
                            // followee_id y la deserialización a [FollowEdge] falla → siempre "no sigo".
                            .select(columns = Columns.raw("follower_id, followee_id")) {
                                filter {
                                    eq("follower_id", user.id)
                                    eq("followee_id", uid)
                                }
                                limit(1)
                            }
                            .let { SupabaseResponseDecoding.decodeListOrObject<FollowEdge>(it.data).isNotEmpty() }
                    }.getOrDefault(false)
                }

                val dobStr = profile?.dateOfBirth?.trim()?.takeIf { it.isNotEmpty() }
                val dobMillis = dobStr?.let { parseIsoDateToMillis(it) }
                val handle =
                    profile?.username?.trim()?.takeIf { it.isNotEmpty() }
                        ?: if (isOwnProfile) {
                            user.email?.substringBefore("@")?.trim()?.takeIf { it.isNotEmpty() }
                        } else {
                            null
                        }
                val headerSnippets = runCatching { loadProfileHeaderSnippets(supabase, uid) }.getOrNull()
                _uiState.value = ProfileUiState(
                    loading = false,
                    isRefreshing = false,
                    userId = uid,
                    isOwnProfile = isOwnProfile,
                    isFollowing = isFollowing,
                    email = if (isOwnProfile) user.email else null,
                    username = profile?.username,
                    displayName = handle,
                    avatarUrl = resolvedAvatar,
                    bio = profile?.bio,
                    followers = counts?.followers ?: 0,
                    following = counts?.following ?: 0,
                    unreadNotifications = unreadNotifications,
                    level = level?.level ?: 1,
                    xp = level?.xp ?: 0,
                    nextLevelXp = nextLevelXp,
                    heightCmDraft = profile?.heightCm?.let { v ->
                        if (v == floor(v)) v.toInt().toString() else String.format(Locale.US, "%.1f", v)
                    } ?: "",
                    weightKgDraft = profile?.weightKg?.let { String.format(Locale.US, "%.1f", it) } ?: "",
                    hasBirthDate = dobStr != null,
                    birthDateMillis = dobMillis,
                    weeklyGoalsDone = headerSnippets?.goalsDone ?: 0,
                    weeklyGoalsTotal = headerSnippets?.goalsTotal ?: 0,
                    achievementsUnlocked = headerSnippets?.achUnlocked ?: 0,
                    achievementsTotal = headerSnippets?.achTotal ?: 0
                )
            } catch (e: Throwable) {
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    /** Error visible bajo el perfil; [message] null limpia el error. */
    fun setUserVisibleError(message: String?) {
        _uiState.value = _uiState.value.copy(error = message)
    }

    /** Sube a Storage `avatars` y actualiza [profiles]; misma ruta de datos que [ProfileView.swift] `handlePickedItem`. */
    fun uploadAvatarJpeg(jpeg: ByteArray) {
        val s = _uiState.value
        if (!s.isOwnProfile || s.userId == null) return
        if (jpeg.isEmpty() || s.uploadAvatarBusy || s.saveBioBusy) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            if (me != s.userId) return@launch
            _uiState.value = s.copy(uploadAvatarBusy = true, error = null)
            runCatching {
                val fileName = "$me-${System.currentTimeMillis()}.jpg"
                val bucket = supabase.storage.from(BackendContracts.Tables.AVATARS)
                bucket.upload(fileName, jpeg) { upsert = true }
                val publicUrl = bucket.publicUrl(fileName)
                supabase.from(BackendContracts.Tables.PROFILES).update(
                    buildJsonObject { put("avatar_url", JsonPrimitive(publicUrl)) }
                ) {
                    filter { eq("user_id", me) }
                }
                publicUrl
            }.onSuccess { url ->
                _uiState.value = _uiState.value.copy(
                    uploadAvatarBusy = false,
                    avatarUrl = url
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    uploadAvatarBusy = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun updateBio(newBio: String) {
        val s = _uiState.value
        if (!s.isOwnProfile || s.userId == null) return
        if (s.saveBioBusy || s.uploadAvatarBusy) return
        val trimmed = newBio.trim()
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            if (me != s.userId) return@launch
            _uiState.value = s.copy(saveBioBusy = true, error = null)
            runCatching {
                supabase.from(BackendContracts.Tables.PROFILES).update(
                    buildJsonObject {
                        if (trimmed.isNotEmpty()) {
                            put("bio", JsonPrimitive(trimmed))
                        } else {
                            put("bio", JsonNull)
                        }
                    }
                ) {
                    filter { eq("user_id", me) }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    saveBioBusy = false,
                    bio = trimmed.ifEmpty { null }
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    saveBioBusy = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    /**
     * Paridad con [Liftr/ProfileView.swift] `performDeleteAccount`: primero `delete_my_account`, luego edge [EdgeFunctions.DELETE_AUTH_USER].
     * La UI debe cerrar sesión siempre (éxito o fallo del edge, como iOS). [onComplete] indica si el edge respondió OK.
     */
    fun deleteAccount(
        onComplete: (edgeFunctionSucceeded: Boolean) -> Unit
    ) {
        val s = _uiState.value
        if (!s.isOwnProfile || s.deleteAccountBusy) return
        viewModelScope.launch {
            _uiState.value = s.copy(deleteAccountBusy = true, error = null)
            runCatching {
                supabase.postgrest.rpc(BackendContracts.Rpc.DELETE_MY_ACCOUNT) { }
            }
            // iOS ignora el error del RPC; seguimos al edge
            val edgeResult = runCatching {
                supabase.functions.invoke(BackendContracts.EdgeFunctions.DELETE_AUTH_USER)
            }
            _uiState.value = _uiState.value.copy(deleteAccountBusy = false)
            onComplete(edgeResult.isSuccess)
        }
    }

    fun setHeightCmDraft(value: String) {
        _uiState.value = _uiState.value.copy(heightCmDraft = value)
    }

    fun setWeightKgDraft(value: String) {
        _uiState.value = _uiState.value.copy(weightKgDraft = value)
    }

    fun setHasBirthDate(value: Boolean) {
        val cur = _uiState.value
        val defaultDob = java.util.Calendar.getInstance().apply { add(java.util.Calendar.YEAR, -20) }.timeInMillis
        _uiState.value = cur.copy(
            hasBirthDate = value,
            birthDateMillis = when {
                !value -> null
                cur.birthDateMillis != null -> cur.birthDateMillis
                else -> defaultDob
            }
        )
    }

    fun setBirthDateMillis(value: Long?) {
        _uiState.value = _uiState.value.copy(birthDateMillis = value)
    }

    /**
     * Paridad con [Liftr/ProfileView.swift] `saveProfileMetrics` (altura, peso, `date_of_birth`).
     */
    fun saveProfileMetrics(onSuccess: () -> Unit) {
        val s = _uiState.value
        if (!s.isOwnProfile || s.userId == null || s.saveProfileMetricsBusy) return
        if (s.uploadAvatarBusy || s.saveBioBusy) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            if (me != s.userId) return@launch
            _uiState.value = s.copy(saveProfileMetricsBusy = true, error = null)
            val hText = s.heightCmDraft.trim()
            runCatching {
                val heightForPayload: Int? = if (hText.isEmpty()) {
                    null
                } else {
                    hText.toIntOrNull()?.takeIf { it > 0 }
                        ?: error("Height must be a positive whole number, or leave empty.")
                }
                if (s.hasBirthDate && s.birthDateMillis == null) {
                    error("Choose a birth date or turn off “Show birth date”.")
                }
                val payload = buildJsonObject {
                    if (hText.isEmpty()) {
                        put("height_cm", JsonNull)
                    } else {
                        put("height_cm", JsonPrimitive(heightForPayload!!))
                    }
                    if (s.hasBirthDate) {
                        val d = Instant.ofEpochMilli(s.birthDateMillis!!).atZone(ZoneId.systemDefault())
                            .toLocalDate().format(DateTimeFormatter.ISO_LOCAL_DATE)
                        put("date_of_birth", JsonPrimitive(d))
                    } else {
                        put("date_of_birth", JsonNull)
                    }
                }
                supabase.from(BackendContracts.Tables.PROFILES).update(payload) {
                    filter { eq("user_id", me) }
                }
                val newH = if (hText.isEmpty()) "" else "${heightForPayload!!}"
                _uiState.value = _uiState.value.copy(
                    saveProfileMetricsBusy = false,
                    heightCmDraft = newH,
                    hasBirthDate = s.hasBirthDate,
                    birthDateMillis = s.birthDateMillis
                )
                onSuccess()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    saveProfileMetricsBusy = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun toggleFollow() {
        if (_uiState.value.followBusy || _uiState.value.isOwnProfile || _uiState.value.uploadAvatarBusy) return
        viewModelScope.launch {
            val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
            val target = _uiState.value.userId ?: return@launch
            val currentlyFollowing = _uiState.value.isFollowing
            _uiState.value = _uiState.value.copy(followBusy = true, error = null)

            runCatching {
                if (currentlyFollowing) {
                    supabase.from(BackendContracts.Tables.FOLLOWS).delete {
                        filter {
                            eq("follower_id", me)
                            eq("followee_id", target)
                        }
                    }
                } else {
                    supabase.from(BackendContracts.Tables.FOLLOWS).insert(
                        FollowEdge(followerId = me, followeeId = target)
                    ) { }
                }
            }.onSuccess {
                val newFollowing = !currentlyFollowing
                val newFollowers = (_uiState.value.followers + if (newFollowing) 1 else -1).coerceAtLeast(0)
                _uiState.value = _uiState.value.copy(
                    followBusy = false,
                    isFollowing = newFollowing,
                    followers = newFollowers
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    followBusy = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    private suspend fun loadProfileHeaderSnippets(
        supabase: SupabaseClient,
        uid: String
    ): HeaderSnippets {
        var achUnlocked = 0
        var achTotal = 0
        runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.GET_USER_ACHIEVEMENTS,
                buildJsonObject { put("p_user_id", uid) }
            ) { }
            val rows = SupabaseResponseDecoding.decodeListOrObject<AchHeaderWire>(res.data)
            achTotal = rows.size
            achUnlocked = rows.count { it.isUnlocked }
        }
        var gDone = 0
        var gTotal = 0
        runCatching {
            val weekStr = LiftrGoalsTime.currentWeekStartDateString()
            supabase.postgrest.rpc(
                BackendContracts.Rpc.RECOMPUTE_WEEKLY_GOAL_RESULTS,
                buildJsonObject {
                    put("p_user_id", uid)
                    put("p_week_start", weekStr)
                }
            ) { }
            val gRes = supabase.from(BackendContracts.Tables.WEEKLY_GOALS)
                .select(
                    columns = Columns.raw("id,user_id,week_start,metric,target_value,title")
                ) {
                    filter {
                        eq("user_id", uid)
                        eq("week_start", weekStr)
                    }
                    order("updated_at", Order.DESCENDING)
                }
            val goals = SupabaseResponseDecoding.decodeListOrObject<WeeklyGoalHeaderWire>(gRes.data)
            gTotal = goals.size
            if (goals.isNotEmpty()) {
                val goalIds = goals.map { it.id }
                val rRes = supabase.from(BackendContracts.Tables.WEEKLY_GOAL_RESULTS)
                    .select(
                        columns = Columns.raw("goal_id,user_id,week_start,achieved_value,is_completed")
                    ) {
                        filter {
                            isIn("goal_id", goalIds.map { it.toString() })
                            eq("week_start", weekStr)
                        }
                    }
                val byGoal = SupabaseResponseDecoding.decodeListOrObject<WeeklyResultHeaderWire>(rRes.data)
                    .associateBy { it.goalId }
                gDone = goals.count { byGoal[it.id]?.isCompleted == true }
            }
        }
        return HeaderSnippets(
            goalsDone = gDone,
            goalsTotal = gTotal,
            achUnlocked = achUnlocked,
            achTotal = achTotal
        )
    }

    private fun parseIsoDateToMillis(s: String): Long? = runCatching {
        val d = LocalDate.parse(s.take(10))
        d.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
    }.getOrNull()

}

class ProfileViewModelFactory(
    private val supabase: SupabaseClient,
    private val targetUserId: String? = null
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ProfileViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ProfileViewModel(supabase, targetUserId) as T
    }
}
